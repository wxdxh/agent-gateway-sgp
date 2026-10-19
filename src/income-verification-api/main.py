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

from fastapi import FastAPI
from fastapi.responses import JSONResponse
from fastmcp import FastMCP
from fastmcp.tools.base import ToolResult
from pydantic import BaseModel
from starlette.applications import Starlette
from starlette.responses import JSONResponse as StarletteJSONResponse
from starlette.routing import Mount, Route

from otel_setup import init_telemetry, trace_endpoint, trace_tool

tracer = init_telemetry()

# ---------------------------------------------------------------------------
# Shared verification logic (Korean Financial Scenario: 김민준 & 이서연 + Sterling)
# ---------------------------------------------------------------------------

_APPLICANTS = {
    "minjun": {
        "name": "김민준 (Minjun Kim)",
        "rrn": "850315-1234566",
        "ssn": "323-45-6789",
        "employer": "서울중앙병원 (Seoul Central General Hospital)",
        "title": "중환자실 전문간호사 (Registered Nurse - ICU)",
        "employment_status": "재직 중 - 정규직 (Active - Full Time)",
        "start_date": "2018-01-10",
        "current_annual_salary": 92000,
        "year_to_date_earnings": 19200,
        "verification_date": "2026-03-13",
    },
    "seoyeon": {
        "name": "이서연 (Seoyeon Lee)",
        "rrn": "870822-2345673",
        "ssn": "321-54-9876",
        "employer": "서밋 어드바이저리 그룹 (Summit Advisory Group)",
        "title": "재무설계 총괄 이사 (Director of Financial Planning)",
        "employment_status": "재직 중 - 정규직 (Active - Full Time)",
        "start_date": "2025-11-15",
        "current_annual_salary": 98000,
        "year_to_date_earnings": 20400,
        "verification_date": "2026-03-13",
    },
    "julian": {
        "name": "Julian A. Sterling",
        "rrn": "850315-1234566",
        "ssn": "323-45-6789",
        "employer": "City General Hospital",
        "title": "Registered Nurse - ICU",
        "employment_status": "Active - Full Time",
        "start_date": "2018-01-10",
        "current_annual_salary": 92000,
        "year_to_date_earnings": 19200,
        "verification_date": "2026-03-13",
    },
    "elena": {
        "name": "Elena M. Sterling",
        "rrn": "870822-2345673",
        "ssn": "321-54-9876",
        "employer": "Summit Advisory Group",
        "title": "Director of Financial Planning",
        "employment_status": "Active - Full Time",
        "start_date": "2025-11-15",
        "current_annual_salary": 98000,
        "year_to_date_earnings": 20400,
        "verification_date": "2026-03-13",
    },
}

_INCOME_SUMMARY = {
    "combined_current_salary": 190000,
    "two_year_average_agi": 174300,
    "dti_threshold_2026_max_percent": 45.0,
    "estimated_household_dti_percent": 28.4,
    "meets_2026_dti_requirements": True,
    "income_trend": "INCREASING",
    "confidence": "HIGH",
}


def _resolve_applicant_key(first_name: str, last_name: str) -> str | None:
    fn = (first_name or "").strip().lower()
    ln = (last_name or "").strip().lower()
    combined = f"{fn} {ln}"

    if any(k in combined for k in ("minjun", "민준", "김민준")):
        return "minjun"
    if any(k in combined for k in ("seoyeon", "서연", "이서연")):
        return "seoyeon"
    if ln == "sterling" and fn in ("julian", "elena"):
        return fn
    if fn in ("김", "kim") and not ln:
        return "minjun"
    if ln in ("김", "kim") and fn in ("민준", "minjun", "김민준"):
        return "minjun"
    if ln in ("이", "lee", "김", "kim") and fn in ("서연", "seoyeon", "이서연"):
        return "seoyeon"
    return None


def _verify(first_name: str, last_name: str) -> dict | None:
    """Return verification data for a known applicant, or None."""
    key = _resolve_applicant_key(first_name, last_name)
    if key and key in _APPLICANTS:
        return {
            "status": "success",
            "verification": {
                "applicant": _APPLICANTS[key],
                "income_summary": _INCOME_SUMMARY,
                "source": "National Income Verification Database (한국신용정보원 · 외부 소득검증 DB)",
            },
        }
    return None


# ---------------------------------------------------------------------------
# FastMCP server
# ---------------------------------------------------------------------------

mcp = FastMCP(name="income-verification")


@mcp.tool()
def verify_applicant(first_name: str, last_name: str) -> ToolResult:
    """Verify applicant income through third-party income verification service (외부 소득검증 기관을 통한 신청자 재직/연봉/DTI 검증).

    Args:
        first_name: Applicant's first name (e.g. 'Minjun', '민준', 'Seoyeon', '서연', 'Julian', 'Elena').
        last_name: Applicant's last name (e.g. 'Kim', '김', 'Lee', '이', 'Sterling').

    Returns:
        ToolResult with verified income data in structured_content.
    """
    # content=[] suppresses the duplicate raw-text representation; Model Armor's
    # CONTENT_AUTHZ only redacts structuredContent, so leaving content[] populated
    # leaks SSNs/RRNs around the redactor.
    with trace_tool(tracer, "verify_applicant"):
        result = _verify(first_name, last_name) or {
            "status": "error",
            "error": f"No verification records found for {first_name} {last_name}.",
        }
        return ToolResult(content=[], structured_content=result)


# ---------------------------------------------------------------------------
# FastAPI REST app (existing endpoints)
# ---------------------------------------------------------------------------


class VerifyRequest(BaseModel):
    first_name: str
    last_name: str


PREFIX = "/income-verification"

rest_app = FastAPI(
    title="Income Verification API",
    description="Verify applicant income through third-party income verification service.",
    version="1.0.0",
)


@rest_app.get(f"{PREFIX}/health")
async def rest_health():
    return {"status": "ok"}


@rest_app.post(f"{PREFIX}/verify")
async def verify(req: VerifyRequest):
    with trace_endpoint(tracer, "verify_applicant"):
        result = _verify(req.first_name, req.last_name)
        if result:
            return result
        return JSONResponse(
            status_code=404,
            content={
                "status": "error",
                "error": f"No verification records found for {req.first_name} {req.last_name}.",
            },
        )


# ---------------------------------------------------------------------------
# Starlette app combining health, MCP, and REST
# ---------------------------------------------------------------------------


async def health(request):
    return StarletteJSONResponse({"status": "ok"})


_mcp_app = mcp.http_app(path="/mcp", stateless_http=True, json_response=True)

app = Starlette(
    routes=[
        Route("/health", health),
        Mount("/api", app=rest_app),
        Mount("/", app=_mcp_app),
    ],
    lifespan=_mcp_app.lifespan,
)
