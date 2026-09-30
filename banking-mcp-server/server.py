"""
Banking MCP Server for Google Cloud Agent Gateway & Semantic Governance Policies (SGP) Codelab.
Implements Model Context Protocol (MCP) JSON-RPC 2.0 transport over HTTP (/mcp)
and direct tool discovery endpoint (/tools).
"""

import json
import logging
import os
import uuid
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional

from fastapi import FastAPI, HTTPException, Request, Response
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
logger = logging.getLogger("banking-mcp-server")

app = FastAPI(
    title="Banking MCP Server",
    description="Model Context Protocol server for Banking Operations",
    version="1.0.0",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Mock in-memory database
CUSTOMERS = {
    "CUST005": {
        "customer_id": "CUST005",
        "name": "Alice Smith",
        "phone": "555-0005",
        "account_number": "ACT-1005",
        "balance": 10000.0,
        "currency": "USD",
        "status": "ACTIVE",
    },
    "CUST001": {
        "customer_id": "CUST001",
        "name": "Bob Jones",
        "phone": "555-0001",
        "account_number": "ACT-1001",
        "balance": 3500.0,
        "currency": "USD",
        "status": "ACTIVE",
    },
    "CUST002": {
        "customer_id": "CUST002",
        "name": "Charlie Brown",
        "phone": "555-0002",
        "account_number": "ACT-1002",
        "balance": 1200.0,
        "currency": "USD",
        "status": "ACTIVE",
    },
}

TOOLS: List[Dict[str, Any]] = [
    {
        "name": "get_account",
        "description": "Retrieves account details and current balance for a customer ID.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "customer_id": {
                    "type": "string",
                    "description": "The unique customer identifier, e.g. CUST005",
                }
            },
            "required": ["customer_id"],
        },
    },
    {
        "name": "lookup_customer_by_phone",
        "description": "Resolves a customer's identity and basic information using their phone number.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "phone": {
                    "type": "string",
                    "description": "The customer phone number, e.g. 555-0001",
                }
            },
            "required": ["phone"],
        },
    },
    {
        "name": "transfer_to_phone",
        "description": "Transfers funds from a customer's account to a recipient identified by their phone number.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "customer_id": {
                    "type": "string",
                    "description": "The sender's customer ID, e.g. CUST005",
                },
                "target_phone": {
                    "type": "string",
                    "description": "The recipient's phone number, e.g. 555-0001",
                },
                "amount": {
                    "type": "number",
                    "description": "The amount to transfer in USD",
                },
            },
            "required": ["customer_id", "target_phone", "amount"],
        },
    },
    {
        "name": "pay_bill",
        "description": "Settles utility, merchant, or invoice payments from a customer's account.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "customer_id": {
                    "type": "string",
                    "description": "The customer ID making the payment, e.g. CUST005",
                },
                "biller_name": {
                    "type": "string",
                    "description": "The name of the merchant or utility company, e.g. Electric Co",
                },
                "account_number": {
                    "type": "string",
                    "description": "The account or invoice number for the bill",
                },
                "amount": {
                    "type": "number",
                    "description": "The payment amount in USD",
                },
            },
            "required": ["customer_id", "biller_name", "account_number", "amount"],
        },
    },
]


def execute_tool(name: str, args: Dict[str, Any]) -> Dict[str, Any]:
    logger.info(f"Executing tool '{name}' with args: {args}")

    if name == "get_account":
        customer_id = args.get("customer_id", "").strip().upper()
        if customer_id not in CUSTOMERS:
            return {
                "isError": True,
                "content": [
                    {
                        "type": "text",
                        "text": f"Error: Customer ID '{customer_id}' not found.",
                    }
                ],
            }
        cust = CUSTOMERS[customer_id]
        return {
            "isError": False,
            "content": [
                {
                    "type": "text",
                    "text": json.dumps(
                        {
                            "customer_id": cust["customer_id"],
                            "name": cust["name"],
                            "account_number": cust["account_number"],
                            "balance": cust["balance"],
                            "currency": cust["currency"],
                            "status": cust["status"],
                        },
                        indent=2,
                    ),
                }
            ],
        }

    elif name == "lookup_customer_by_phone":
        phone = args.get("phone", "").strip()
        for cust in CUSTOMERS.values():
            if cust["phone"] == phone:
                return {
                    "isError": False,
                    "content": [
                        {
                            "type": "text",
                            "text": json.dumps(
                                {
                                    "customer_id": cust["customer_id"],
                                    "name": cust["name"],
                                    "phone": cust["phone"],
                                },
                                indent=2,
                            ),
                        }
                    ],
                }
        return {
            "isError": True,
            "content": [
                {
                    "type": "text",
                    "text": f"Error: No customer found with phone number '{phone}'.",
                }
            ],
        }

    elif name == "transfer_to_phone":
        customer_id = args.get("customer_id", "").strip().upper()
        target_phone = args.get("target_phone", "").strip()
        try:
            amount = float(args.get("amount", 0))
        except (ValueError, TypeError):
            return {
                "isError": True,
                "content": [{"type": "text", "text": "Error: Invalid amount value."}],
            }

        if amount <= 0:
            return {
                "isError": True,
                "content": [{"type": "text", "text": "Error: Amount must be greater than 0."}],
            }

        if customer_id not in CUSTOMERS:
            return {
                "isError": True,
                "content": [{"type": "text", "text": f"Error: Sender '{customer_id}' not found."}],
            }

        sender = CUSTOMERS[customer_id]
        if sender["balance"] < amount:
            return {
                "isError": True,
                "content": [
                    {
                        "type": "text",
                        "text": f"Error: Insufficient funds. Available: ${sender['balance']:.2f}, Requested: ${amount:.2f}",
                    }
                ],
            }

        # Deduct from sender
        sender["balance"] -= amount

        # Credit recipient if found in database
        recipient_name = "External Contact"
        for cust in CUSTOMERS.values():
            if cust["phone"] == target_phone:
                cust["balance"] += amount
                recipient_name = cust["name"]
                break

        txn_id = f"TXN-{uuid.uuid4().hex[:8].upper()}"
        result_data = {
            "status": "SUCCESS",
            "transaction_id": txn_id,
            "amount": amount,
            "currency": "USD",
            "sender_customer_id": customer_id,
            "sender_name": sender["name"],
            "recipient_phone": target_phone,
            "recipient_name": recipient_name,
            "remaining_balance": sender["balance"],
            "timestamp": datetime.now(timezone.utc).isoformat(),
        }

        logger.info(f"Transfer successful: {result_data}")
        return {
            "isError": False,
            "content": [
                {
                    "type": "text",
                    "text": f"Transfer of ${amount:.2f} to {recipient_name} ({target_phone}) completed successfully. Transaction ID: {txn_id}. Remaining balance: ${sender['balance']:.2f}.",
                }
            ],
        }

    elif name == "pay_bill":
        customer_id = args.get("customer_id", "").strip().upper()
        biller_name = args.get("biller_name", "").strip()
        account_number = args.get("account_number", "").strip()
        try:
            amount = float(args.get("amount", 0))
        except (ValueError, TypeError):
            return {
                "isError": True,
                "content": [{"type": "text", "text": "Error: Invalid amount value."}],
            }

        if amount <= 0:
            return {
                "isError": True,
                "content": [{"type": "text", "text": "Error: Amount must be greater than 0."}],
            }

        if customer_id not in CUSTOMERS:
            return {
                "isError": True,
                "content": [{"type": "text", "text": f"Error: Customer '{customer_id}' not found."}],
            }

        sender = CUSTOMERS[customer_id]
        if sender["balance"] < amount:
            return {
                "isError": True,
                "content": [
                    {
                        "type": "text",
                        "text": f"Error: Insufficient funds. Available: ${sender['balance']:.2f}, Required: ${amount:.2f}",
                    }
                ],
            }

        sender["balance"] -= amount
        confirmation_id = f"BILL-{uuid.uuid4().hex[:8].upper()}"

        return {
            "isError": False,
            "content": [
                {
                    "type": "text",
                    "text": f"Bill payment of ${amount:.2f} to {biller_name} (Acc: {account_number}) successful. Confirmation: {confirmation_id}. Remaining balance: ${sender['balance']:.2f}.",
                }
            ],
        }

    else:
        return {
            "isError": True,
            "content": [{"type": "text", "text": f"Error: Unknown tool '{name}'."}],
        }


def handle_jsonrpc(req: Dict[str, Any]) -> Optional[Dict[str, Any]]:
    jsonrpc_ver = req.get("jsonrpc", "2.0")
    req_id = req.get("id")
    method = req.get("method")
    params = req.get("params") or {}

    logger.info(f"JSON-RPC Request: method={method}, id={req_id}")

    if method == "initialize":
        return {
            "jsonrpc": jsonrpc_ver,
            "id": req_id,
            "result": {
                "protocolVersion": "2024-11-05",
                "capabilities": {
                    "tools": {
                        "listChanged": False,
                    }
                },
                "serverInfo": {
                    "name": "banking-mcp-server",
                    "version": "1.0.0",
                },
            },
        }

    elif method in ("notifications/initialized", "initialized"):
        # Notifications don't require responses
        return None

    elif method == "tools/list":
        return {
            "jsonrpc": jsonrpc_ver,
            "id": req_id,
            "result": {
                "tools": TOOLS,
            },
        }

    elif method == "tools/call":
        tool_name = params.get("name")
        tool_args = params.get("arguments") or {}
        res = execute_tool(tool_name, tool_args)
        return {
            "jsonrpc": jsonrpc_ver,
            "id": req_id,
            "result": res,
        }

    elif method == "ping":
        return {
            "jsonrpc": jsonrpc_ver,
            "id": req_id,
            "result": {},
        }

    else:
        return {
            "jsonrpc": jsonrpc_ver,
            "id": req_id,
            "error": {
                "code": -32601,
                "message": f"Method not found: {method}",
            },
        }


# --- Endpoints ---

@app.get("/")
@app.get("/healthz")
async def health_check():
    return {
        "status": "healthy",
        "service": "banking-mcp-server",
        "version": "1.0.0",
        "tools_count": len(TOOLS),
    }


@app.get("/tools")
async def list_tools():
    """Returns the list of tools directly for tool-spec extraction."""
    return TOOLS


@app.post("/mcp")
@app.post("/")
async def mcp_endpoint(request: Request):
    """MCP JSON-RPC 2.0 endpoint handling tool invocations."""
    try:
        body = await request.json()
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Invalid JSON: {e}")

    # Handle batch requests
    if isinstance(body, list):
        responses = []
        for single_req in body:
            resp = handle_jsonrpc(single_req)
            if resp is not None:
                responses.append(resp)
        return responses

    # Handle single request
    resp = handle_jsonrpc(body)
    if resp is None:
        return Response(status_code=204)
    return resp


if __name__ == "__main__":
    import uvicorn
    port = int(os.environ.get("PORT", "8080"))
    uvicorn.run(app, host="0.0.0.0", port=port)
