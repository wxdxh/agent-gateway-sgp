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

import uuid
from datetime import datetime, timezone

from fastmcp import FastMCP
from fastmcp.tools.base import ToolResult
from starlette.applications import Starlette
from starlette.responses import JSONResponse
from starlette.routing import Mount, Route

from otel_setup import init_telemetry, trace_tool

tracer = init_telemetry()

# ---------------------------------------------------------------------------
# Email data and helpers (Korean & English Mortgage Underwriting Inbox)
# ---------------------------------------------------------------------------


SAMPLE_EMAILS = [
    {
        "id": "msg-001",
        "from": "underwriting@apexbank.co.kr",
        "to": "loan-officers@apexbank.co.kr",
        "subject": "[여신심사팀] 주택담보대출 신청서 #2026-7891 (김민준·이서연 부부 / Sterling Family) 서류 접수 완료",
        "body": (
            "김민준·이서연 부부(Minjun Kim & Seoyeon Lee / Julian & Elena Sterling)의 주택담보대출 신청서 #2026-7891 관련 "
            "모든 필수 서류(2023~2024년 소득금액증명원/종합소득세 신고서, 재직증명서)가 통합 문서관리 시스템(legacy-dms)에 등록되었습니다. "
            "외부 소득검증 기관(income-verification)을 통해 현재 소득 및 2026년 DTI 적격 여부를 검증해 주시기 바랍니다."
        ),
        "timestamp": "2026-03-15T09:30:00Z",
        "read": True,
    },
    {
        "id": "msg-002",
        "from": "compliance@apexbank.co.kr",
        "to": "loan-officers@apexbank.co.kr",
        "subject": "[준법감시팀] 2026년 주택담보대출 DTI(총부채상환비율) 심사 기준 안내 (Updated 2026 DTI Ratio Guidelines)",
        "body": (
            "2026년 적격 주택담보대출(Conforming Loans)의 최대 총부채상환비율(DTI, Debt-to-Income) 한도가 기존 43%에서 45%로 개정되었습니다 "
            "(New maximum DTI is 45%, minimum combined household income requirement for this loan tier is $150,000). "
            "세부 사항은 준법감시 지침서 CB-2026-12를 참고하시기 바랍니다."
        ),
        "timestamp": "2026-03-14T14:15:00Z",
        "read": False,
    },
    {
        "id": "msg-003",
        "from": "appraisals@apexbank.co.kr",
        "to": "loan-officers@apexbank.co.kr",
        "subject": "[감정평가팀] 담보물 감정평가 완료 - 서울 강남구 테헤란로 에이펙스 타워 101동 1502호 (742 Evergreen Terrace)",
        "body": (
            "담보 대상 부동산(서울 강남구 테헤란로 에이펙스 타워 101동 1502호 / 742 Evergreen Terrace)에 대한 감정평가가 완료되었습니다. "
            "감정평가액: $485,000 (신청 대출금 $388,000 기준 LTV 80% 충족). 상세 감정평가서는 대출 심사 파일에 첨부되었습니다."
        ),
        "timestamp": "2026-03-13T11:45:00Z",
        "read": True,
    },
]


def _send(to: str, subject: str, body: str) -> dict:
    """Simulate sending an email and return a mock success response."""
    return {
        "status": "sent",
        "message_id": str(uuid.uuid4()),
        "to": to,
        "subject": subject,
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }


def _read(email_id: str | None = None) -> dict:
    """Read emails from the inbox. Optionally filter by email ID."""
    if email_id:
        for email in SAMPLE_EMAILS:
            if email["id"] == email_id:
                return {"emails": [email]}
        return {"emails": [], "message": f"No email found with ID {email_id}"}
    return {"emails": SAMPLE_EMAILS}


# ---------------------------------------------------------------------------
# FastMCP server
# ---------------------------------------------------------------------------

mcp = FastMCP(name="corporate-email")


@mcp.tool()
def send_email(to: str, subject: str, body: str) -> ToolResult:
    """Send an email through the corporate email system (사내 이메일 시스템을 통한 심사 결과 메일 발송 - 쓰기 작업).

    Args:
        to: Recipient email address.
        subject: Email subject line.
        body: Email body content.

    Returns:
        ToolResult with send status, message ID, and timestamp in structured_content.
    """
    # content=[] suppresses the duplicate raw-text representation; Model Armor's
    # CONTENT_AUTHZ only redacts structuredContent, so leaving content[] populated
    # leaks sensitive fields around the redactor.
    with trace_tool(tracer, "send_email"):
        return ToolResult(content=[], structured_content=_send(to, subject, body))


@mcp.tool()
def read_email(email_id: str | None = None) -> ToolResult:
    """Read emails from the corporate inbox. This is a read-only operation (사내 메일함 조회 - 읽기 전용 작업).

    Args:
        email_id: Optional email ID to fetch a specific email. If not provided,
                  returns all emails in the inbox.

    Returns:
        ToolResult with a list of email messages in structured_content.
    """
    with trace_tool(tracer, "read_email"):
        return ToolResult(content=[], structured_content=_read(email_id))


# ---------------------------------------------------------------------------
# Starlette app with health endpoint + FastMCP mount
# ---------------------------------------------------------------------------


async def health(request):
    return JSONResponse({"status": "ok"})


_mcp_app = mcp.http_app(path="/mcp", stateless_http=True, json_response=True)

app = Starlette(
    routes=[
        Route("/health", health),
        Mount("/", app=_mcp_app),
    ],
    lifespan=_mcp_app.lifespan,
)
