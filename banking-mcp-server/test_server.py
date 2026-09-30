import json
from server import app, CUSTOMERS, TOOLS, execute_tool, handle_jsonrpc

def test_tools():
    print("Testing TOOLS structure...")
    assert len(TOOLS) == 4
    tool_names = [t["name"] for t in TOOLS]
    assert "get_account" in tool_names
    assert "lookup_customer_by_phone" in tool_names
    assert "transfer_to_phone" in tool_names
    assert "pay_bill" in tool_names
    print("✓ Tool schemas verified")

def test_get_account():
    print("Testing get_account...")
    res = execute_tool("get_account", {"customer_id": "CUST005"})
    assert not res["isError"]
    data = json.loads(res["content"][0]["text"])
    assert data["name"] == "Alice Smith"
    assert data["balance"] == 10000.0
    print(f"✓ get_account passed: {data['name']}, balance: {data['balance']}")

def test_lookup_phone():
    print("Testing lookup_customer_by_phone...")
    res = execute_tool("lookup_customer_by_phone", {"phone": "555-0001"})
    assert not res["isError"]
    data = json.loads(res["content"][0]["text"])
    assert data["name"] == "Bob Jones"
    print(f"✓ lookup_customer_by_phone passed: {data['name']}")

def test_transfer():
    print("Testing transfer_to_phone under limit...")
    res = execute_tool("transfer_to_phone", {"customer_id": "CUST005", "target_phone": "555-0001", "amount": 50})
    assert not res["isError"]
    assert "completed successfully" in res["content"][0]["text"]
    assert CUSTOMERS["CUST005"]["balance"] == 9950.0
    assert CUSTOMERS["CUST001"]["balance"] == 3550.0
    print("✓ transfer_to_phone passed")

def test_jsonrpc():
    print("Testing JSON-RPC handler...")
    init_res = handle_jsonrpc({"jsonrpc": "2.0", "id": 1, "method": "initialize"})
    assert init_res["result"]["serverInfo"]["name"] == "banking-mcp-server"

    tools_res = handle_jsonrpc({"jsonrpc": "2.0", "id": 2, "method": "tools/list"})
    assert len(tools_res["result"]["tools"]) == 4

    call_res = handle_jsonrpc({
        "jsonrpc": "2.0",
        "id": 3,
        "method": "tools/call",
        "params": {
            "name": "get_account",
            "arguments": {"customer_id": "CUST005"}
        }
    })
    assert not call_res["result"]["isError"]
    print("✓ JSON-RPC protocol methods passed")

if __name__ == "__main__":
    test_tools()
    test_get_account()
    test_lookup_phone()
    test_transfer()
    test_jsonrpc()
    print("\nALL MCP SERVER TESTS PASSED SUCCESSFULLY!")
