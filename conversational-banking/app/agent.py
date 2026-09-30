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

import ssl
import urllib3
import requests

# Disable insecure request warnings
urllib3.disable_warnings()

# Ensure Google APIs route through standard endpoints rather than mTLS when behind Agent Gateway
os.environ["GOOGLE_API_USE_MTLS_ENDPOINT"] = "never"
os.environ["GOOGLE_API_USE_CLIENT_CERTIFICATE"] = "false"

# Configure SSL context and HTTP clients to bypass TLS inspection validation errors
try:
    _orig_create_default_context = ssl.create_default_context
    def _custom_create_default_context(*args, **kwargs):
        ctx = _orig_create_default_context(*args, **kwargs)
        ctx.check_hostname = False
        ctx.verify_mode = ssl.CERT_NONE
        return ctx
    ssl.create_default_context = _custom_create_default_context
    ssl._create_default_https_context = _custom_create_default_context
except Exception:
    pass

try:
    _orig_request = requests.Session.request
    def _custom_request(self, *args, **kwargs):
        kwargs["verify"] = False
        return _orig_request(self, *args, **kwargs)
    requests.Session.request = _custom_request
except Exception:
    pass

try:
    import httpx
    _orig_httpx_init = httpx.Client.__init__
    def _custom_httpx_init(self, *args, **kwargs):
        kwargs["verify"] = False
        _orig_httpx_init(self, *args, **kwargs)
    httpx.Client.__init__ = _custom_httpx_init

    _orig_async_httpx_init = httpx.AsyncClient.__init__
    def _custom_async_httpx_init(self, *args, **kwargs):
        kwargs["verify"] = False
        _orig_async_httpx_init(self, *args, **kwargs)
    httpx.AsyncClient.__init__ = _custom_async_httpx_init

    def _get_cloud_run_auth_token():
        # 1. Try Compute Engine metadata server
        try:
            import urllib.request
            req = urllib.request.Request(
                "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/identity?audience=https://banking-mcp-server-vd47jgunrq-uc.a.run.app",
                headers={"Metadata-Flavor": "Google"}
            )
            with urllib.request.urlopen(req, timeout=2) as resp:
                return resp.read().decode().strip()
        except Exception:
            pass
        # 2. Try google.oauth2.id_token
        try:
            import google.auth.transport.requests
            import google.oauth2.id_token
            auth_req = google.auth.transport.requests.Request()
            return google.oauth2.id_token.fetch_id_token(
                auth_req, "https://banking-mcp-server-vd47jgunrq-uc.a.run.app"
            )
        except Exception:
            pass
        # 3. Fallback to access token
        try:
            import google.auth
            import google.auth.transport.requests
            creds, _ = google.auth.default()
            creds.refresh(google.auth.transport.requests.Request())
            return creds.token
        except Exception:
            return ""

    _orig_async_send = httpx.AsyncClient.send
    async def _custom_async_send(self, request, *args, **kwargs):
        if "banking-mcp-server" in str(request.url) and "Authorization" not in request.headers:
            tok = _get_cloud_run_auth_token()
            if tok:
                request.headers["Authorization"] = f"Bearer {tok}"
        return await _orig_async_send(self, request, *args, **kwargs)
    httpx.AsyncClient.send = _custom_async_send
except Exception:
    pass

PROJECT_ID = os.environ.get("PROJECT_ID") or os.environ.get("GOOGLE_CLOUD_PROJECT", "")
LOCATION = os.environ.get("GOOGLE_CLOUD_LOCATION") or os.environ.get("LOCATION", "us-central1")
MCP_SERVER_NAME = os.environ.get("MCP_SERVER_NAME", "")
MODEL = os.environ.get("MODEL", "gemini-2.5-flash")

tools = []
if PROJECT_ID and MCP_SERVER_NAME:
    import time
    for attempt in range(5):
        try:
            registry = AgentRegistry(project_id=PROJECT_ID, location=LOCATION)
            toolset = registry.get_mcp_toolset(
                f"projects/{PROJECT_ID}/locations/{LOCATION}/mcpServers/{MCP_SERVER_NAME}",
            )
            tools.append(toolset)
            print("Successfully loaded MCP toolset.")
            break
        except Exception as e:
            print(f"[Attempt {attempt+1}/5] Failed to initialize MCP toolset: {e}")
            if attempt == 4:
                raise e
            time.sleep(3 * (attempt + 1))

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
