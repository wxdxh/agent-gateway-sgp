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

"""Legacy Document Management System (통합 문서관리 시스템) MCP server."""

from __future__ import annotations

from fastmcp import FastMCP
from fastmcp.tools.base import ToolResult
from starlette.applications import Starlette
from starlette.responses import JSONResponse
from starlette.routing import Mount, Route

from otel_setup import init_telemetry, trace_tool

tracer = init_telemetry()

mcp = FastMCP(name="legacy-dms")

# ---------------------------------------------------------------------------
# Mock document store (Korean Financial Scenario: 김민준 & 이서연 부부 + Sterling)
# ---------------------------------------------------------------------------

_DOCUMENTS = {
    "DOC-2024-KM-1040": {
        "document_id": "DOC-2024-KM-1040",
        "title": "2024년 귀속 종합소득세 및 근로소득원천징수영수증 통합 신고서 (TY2024)",
        "tax_year": 2024,
        "applicants": "김민준 & 이서연 (Minjun Kim & Seoyeon Lee)",
        "filing_status": "부부 합산 신고 (Married Filing Jointly)",
        "content": {
            "taxpayer_primary": {
                "name": "김민준 (Minjun Kim)",
                "rrn": "850315-1234566",
                "ssn": "323-45-6789",
                "occupation": "중환자실 전문간호사 (Registered Nurse - ICU)",
                "employer": "서울중앙병원 (Seoul Central General Hospital)",
                "wages_salaries_tips": 88000,
            },
            "taxpayer_spouse": {
                "name": "이서연 (Seoyeon Lee)",
                "rrn": "870822-2345673",
                "ssn": "321-54-9876",
                "occupation": "수석 재무분석가 (Senior Financial Analyst)",
                "employer": "에이펙스 금융서비스 (Apex Financial Services, Inc.)",
                "wages_salaries_tips": 85000,
            },
            "income": {
                "total_wages": 173000,
                "taxable_interest": 3200,
                "ordinary_dividends": 5500,
                "capital_gains": 5000,
                "adjusted_gross_income": 186700,
            },
            "deductions": {
                "standard_deduction": 29200,
                "taxable_income": 157500,
            },
            "tax_summary": {
                "total_tax": 24750,
                "federal_tax_withheld": 27500,
                "refund_amount": 2750,
            },
        },
    },
    "DOC-2023-KM-1040": {
        "document_id": "DOC-2023-KM-1040",
        "title": "2023년 귀속 종합소득세 및 근로소득원천징수영수증 통합 신고서 (TY2023)",
        "tax_year": 2023,
        "applicants": "김민준 & 이서연 (Minjun Kim & Seoyeon Lee)",
        "filing_status": "부부 합산 신고 (Married Filing Jointly)",
        "content": {
            "taxpayer_primary": {
                "name": "김민준 (Minjun Kim)",
                "rrn": "850315-1234566",
                "ssn": "323-45-6789",
                "occupation": "중환자실 전문간호사 (Registered Nurse - ICU)",
                "employer": "서울중앙병원 (Seoul Central General Hospital)",
                "wages_salaries_tips": 85000,
            },
            "taxpayer_spouse": {
                "name": "이서연 (Seoyeon Lee)",
                "rrn": "870822-2345673",
                "ssn": "321-54-9876",
                "occupation": "재무분석가 (Financial Analyst)",
                "employer": "에이펙스 금융서비스 (Apex Financial Services, Inc.)",
                "wages_salaries_tips": 68000,
            },
            "income": {
                "total_wages": 153000,
                "taxable_interest": 2800,
                "ordinary_dividends": 4100,
                "capital_gains": 2000,
                "adjusted_gross_income": 161900,
            },
            "deductions": {
                "standard_deduction": 27700,
                "taxable_income": 134200,
            },
            "tax_summary": {
                "total_tax": 20100,
                "federal_tax_withheld": 22800,
                "refund_amount": 2700,
            },
        },
    },
    "DOC-2024-SM-1040": {
        "document_id": "DOC-2024-SM-1040",
        "title": "U.S. Individual Income Tax Return - Form 1040 (TY2024)",
        "tax_year": 2024,
        "applicants": "Julian & Elena Sterling",
        "filing_status": "Married Filing Jointly",
        "content": {
            "taxpayer_primary": {
                "name": "Julian A. Sterling",
                "rrn": "850315-1234566",
                "ssn": "323-45-6789",
                "occupation": "Registered Nurse - ICU",
                "employer": "City General Hospital",
                "wages_salaries_tips": 88000,
            },
            "taxpayer_spouse": {
                "name": "Elena M. Sterling",
                "rrn": "870822-2345673",
                "ssn": "321-54-9876",
                "occupation": "Senior Financial Analyst",
                "employer": "Acme Financial Services, Inc.",
                "wages_salaries_tips": 85000,
            },
            "income": {
                "total_wages": 173000,
                "taxable_interest": 3200,
                "ordinary_dividends": 5500,
                "capital_gains": 5000,
                "adjusted_gross_income": 186700,
            },
            "deductions": {
                "standard_deduction": 29200,
                "taxable_income": 157500,
            },
            "tax_summary": {
                "total_tax": 24750,
                "federal_tax_withheld": 27500,
                "refund_amount": 2750,
            },
        },
    },
    "DOC-2023-SM-1040": {
        "document_id": "DOC-2023-SM-1040",
        "title": "U.S. Individual Income Tax Return - Form 1040 (TY2023)",
        "tax_year": 2023,
        "applicants": "Julian & Elena Sterling",
        "filing_status": "Married Filing Jointly",
        "content": {
            "taxpayer_primary": {
                "name": "Julian A. Sterling",
                "rrn": "850315-1234566",
                "ssn": "323-45-6789",
                "occupation": "Registered Nurse - ICU",
                "employer": "City General Hospital",
                "wages_salaries_tips": 85000,
            },
            "taxpayer_spouse": {
                "name": "Elena M. Sterling",
                "rrn": "870822-2345673",
                "ssn": "321-54-9876",
                "occupation": "Financial Analyst",
                "employer": "Acme Financial Services, Inc.",
                "wages_salaries_tips": 68000,
            },
            "income": {
                "total_wages": 153000,
                "taxable_interest": 2800,
                "ordinary_dividends": 4100,
                "capital_gains": 2000,
                "adjusted_gross_income": 161900,
            },
            "deductions": {
                "standard_deduction": 27700,
                "taxable_income": 134200,
            },
            "tax_summary": {
                "total_tax": 20100,
                "federal_tax_withheld": 22800,
                "refund_amount": 2700,
            },
        },
    },
}

# ---------------------------------------------------------------------------
# MCP tools
# ---------------------------------------------------------------------------

_KIM_ALIASES = {"kim", "김", "김민준", "민준", "minjun", "lee", "이", "이서연", "서연", "seoyeon"}
_STERLING_ALIASES = {"sterling", "스털링", "julian", "elena"}
_TAX_DOC_KEYWORDS = ("tax", "1040", "소득", "세금", "원천징수", "신고", "증명", "return", "all")


def _matches_tax_doc(document_type: str) -> bool:
    doc_lower = (document_type or "").strip().lower()
    if not doc_lower:
        return True
    return any(k in doc_lower for k in _TAX_DOC_KEYWORDS)


def _search_documents(applicant_last_name: str, document_type: str, years: int = 2) -> dict:
    """Search for applicant documents and return matching metadata."""
    name_key = (applicant_last_name or "").strip().lower()

    if name_key in _KIM_ALIASES and _matches_tax_doc(document_type):
        results = [
            {
                "document_id": "DOC-2024-KM-1040",
                "title": "2024년 귀속 종합소득세 및 근로소득원천징수영수증 통합 신고서 (TY2024)",
                "tax_year": 2024,
                "applicants": "김민준 & 이서연 (Minjun Kim & Seoyeon Lee)",
                "filing_status": "부부 합산 신고 (Married Filing Jointly)",
                "date_filed": "2025-03-15",
            },
            {
                "document_id": "DOC-2023-KM-1040",
                "title": "2023년 귀속 종합소득세 및 근로소득원천징수영수증 통합 신고서 (TY2023)",
                "tax_year": 2023,
                "applicants": "김민준 & 이서연 (Minjun Kim & Seoyeon Lee)",
                "filing_status": "부부 합산 신고 (Married Filing Jointly)",
                "date_filed": "2024-04-10",
            },
        ]
        return {
            "status": "success",
            "query": {
                "applicant_last_name": applicant_last_name,
                "document_type": document_type,
                "years": years,
            },
            "results": results[:years],
            "total_results": min(years, len(results)),
        }

    if name_key in _STERLING_ALIASES and _matches_tax_doc(document_type):
        results = [
            {
                "document_id": "DOC-2024-SM-1040",
                "title": "U.S. Individual Income Tax Return - Form 1040 (TY2024)",
                "tax_year": 2024,
                "applicants": "Julian & Elena Sterling",
                "filing_status": "Married Filing Jointly",
                "date_filed": "2025-03-15",
            },
            {
                "document_id": "DOC-2023-SM-1040",
                "title": "U.S. Individual Income Tax Return - Form 1040 (TY2023)",
                "tax_year": 2023,
                "applicants": "Julian & Elena Sterling",
                "filing_status": "Married Filing Jointly",
                "date_filed": "2024-04-10",
            },
        ]
        return {
            "status": "success",
            "query": {
                "applicant_last_name": applicant_last_name,
                "document_type": document_type,
                "years": years,
            },
            "results": results[:years],
            "total_results": min(years, len(results)),
        }

    return {
        "status": "success",
        "query": {
            "applicant_last_name": applicant_last_name,
            "document_type": document_type,
            "years": years,
        },
        "results": [],
        "total_results": 0,
    }


def _get_document(document_id: str) -> dict:
    """Retrieve a full document by ID."""
    doc = _DOCUMENTS.get(document_id)
    if doc:
        return {"status": "success", "document": doc}

    return {
        "status": "error",
        "error": f"Document '{document_id}' not found in the system.",
    }


@mcp.tool()
def search_documents(applicant_last_name: str, document_type: str, years: int = 2) -> ToolResult:
    """Search the document management system for applicant documents (대출 신청자 소득/세무 서류 검색).

    Args:
        applicant_last_name: Last name or full name of the applicant (e.g. 'Kim', '김', '김민준', 'Sterling').
        document_type: Type of document (e.g. 'tax_return', '소득금액증명원', 'pay_stub', 'bank_statement').
        years: Number of years of documents to retrieve (default 2).

    Returns:
        ToolResult with matching document metadata in structured_content.
    """
    # content=[] suppresses the duplicate raw-text representation; Model Armor's
    # CONTENT_AUTHZ only redacts structuredContent, so leaving content[] populated
    # leaks SSNs/RRNs around the redactor.
    with trace_tool(tracer, "search_documents"):
        return ToolResult(content=[], structured_content=_search_documents(applicant_last_name, document_type, years))


@mcp.tool()
def get_document(document_id: str) -> ToolResult:
    """Retrieve a full document from the document management system by ID (문서 ID로 상세 소득/세무 신고서 조회).

    Args:
        document_id: The unique document identifier (e.g. 'DOC-2024-KM-1040' or 'DOC-2024-SM-1040').

    Returns:
        ToolResult with the full document content in structured_content.
    """
    with trace_tool(tracer, "get_document"):
        return ToolResult(content=[], structured_content=_get_document(document_id))


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
