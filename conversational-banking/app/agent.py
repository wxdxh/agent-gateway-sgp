# ruff: noqa
# Copyright 2026 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

import os
from google.adk.agents import Agent
from google.adk.apps import App
from google.adk.integrations.agent_registry import AgentRegistry
from google.adk.models import Gemini
from google.genai import types

PROJECT_ID = os.environ.get("PROJECT_ID") or os.environ.get("GOOGLE_CLOUD_PROJECT", "")
LOCATION = os.environ.get("GOOGLE_CLOUD_LOCATION") or os.environ.get("LOCATION", "us-central1")
MCP_SERVER_NAME = os.environ.get("MCP_SERVER_NAME", "")
MODEL = os.environ.get("MODEL", "gemini-2.5-flash")

tools = []
if PROJECT_ID and MCP_SERVER_NAME:
    registry = AgentRegistry(project_id=PROJECT_ID, location=LOCATION)
    toolset = registry.get_mcp_toolset(
        f"projects/{PROJECT_ID}/locations/{LOCATION}/mcpServers/{MCP_SERVER_NAME}",
    )
    tools.append(toolset)

INSTRUCTION = """You are a secure, helpful Conversational Banking Assistant.
You assist verified customers with checking account details, looking up customers by phone number, transferring money, and paying bills.

Operational Guidelines:
1. When a user introduces themselves with a customer ID (e.g., "I am customer CUST005"), use `get_account(customer_id)` to verify the customer, retrieve their account details and balance, and display a friendly greeting with their balance and a summary of available actions.
2. For money transfers (e.g., "transfer 50 to 555-0001"):
   - Identify the sender customer ID from the authenticated session context.
   - For high-value transactions or when appropriate, confirm the recipient and amount.
   - Execute the transfer using `transfer_to_phone(customer_id, target_phone, amount)`.
3. If any tool invocation is rejected or fails due to a policy denial (such as exceeding transfer limits):
   - Clearly report the reason to the user politely without retrying the forbidden operation.
4. Always maintain confidentiality and follow security best practices.
"""

root_agent = Agent(
    name="conversational_banking",
    model=Gemini(
        model=MODEL,
        retry_options=types.HttpRetryOptions(attempts=3),
    ),
    instruction=INSTRUCTION,
    tools=tools,
)

app = App(
    root_agent=root_agent,
    name="app",
)
