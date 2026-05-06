import json
import logging
import os
import re
import tempfile
import time
import uuid
from pathlib import Path
from typing import Any, Dict, Optional

from fastapi import Body, FastAPI, File, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field

from scenario_runner import run_many as run_lca_for_scenarios

try:
    import pdfplumber
except Exception as exc:  # pragma: no cover - env-specific
    pdfplumber = None  # type: ignore[assignment]
    PDFPLUMBER_IMPORT_ERROR = str(exc)
else:
    PDFPLUMBER_IMPORT_ERROR = None

app = FastAPI(title="Brightway LCA Service")
logging.basicConfig(level=logging.INFO)
L = logging.getLogger(__name__)

DOCUMENT_STORE: Dict[str, Dict[str, Any]] = {}
DOCUMENT_CACHE_DIR = Path(tempfile.gettempdir()) / "earlylca_documents"
DOCUMENT_CACHE_DIR.mkdir(parents=True, exist_ok=True)

_TABLE_SETTINGS_PRIMARY = {
    "vertical_strategy": "lines",
    "horizontal_strategy": "lines",
    "intersection_tolerance": 5,
    "snap_tolerance": 3,
    "join_tolerance": 3,
}
_TABLE_SETTINGS_FALLBACK = {
    "vertical_strategy": "text",
    "horizontal_strategy": "text",
    "intersection_tolerance": 8,
    "snap_tolerance": 4,
    "join_tolerance": 4,
    "min_words_vertical": 2,
    "min_words_horizontal": 1,
}
_WORD_RE = re.compile(r"[A-Za-z0-9_./%-]+")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.get("/")
def health() -> Dict[str, str]:
    return {"status": "ok"}


class DocumentQueryItem(BaseModel):
    query: str = Field(..., min_length=1)
    page_numbers: Optional[list[int]] = None
    max_tables: Optional[int] = None
    max_rows: Optional[int] = None


class DocumentQueryRequest(BaseModel):
    document_id: str = Field(..., min_length=1)
    query: Optional[str] = None
    queries: Optional[list[DocumentQueryItem]] = None
    page_numbers: Optional[list[int]] = None
    max_tables: int = 5
    max_rows: int = 15


@app.post("/run_lca_all")
def run_all(payload: Dict[str, Any] = Body(...)) -> Dict[str, Any]:
    try:
        L.info("Received payload top-level keys: %s", list(payload.keys()))
    except Exception:
        pass

    scenarios = payload.get("scenarios")
    if not isinstance(scenarios, dict):
        raise HTTPException(
            status_code=400,
            detail="'scenarios' must be an object mapping names to {model: …}",
        )

    # Pick custom CF file: payload override > env var > default filename
    custom_cf_file: Optional[str] = payload.get("custom_cf_file") \
        or os.environ.get("CUSTOM_CF_FILE") \
        or "upsert_custom_cfs_from_table.xlsx"

    # Check presence, but do not crash if missing
    if custom_cf_file and not os.path.isfile(custom_cf_file):
        L.warning("Custom CF file not found: %s (proceeding without overlay)", custom_cf_file)
        custom_cf_file = None
    else:
        L.info("Using custom CF file: %s", custom_cf_file)

    try:
        start = time.perf_counter()
        results = run_lca_for_scenarios(
            scenarios=scenarios,
            custom_cf_file=custom_cf_file,
        )
        elapsed = time.perf_counter() - start

        L.info("Full results:\n%s", json.dumps(results, indent=2))
        L.info("Returning results for scenarios: %s", list(results.keys()))
        L.info("Time to compute LCA for %d scenarios: %.3f seconds", len(scenarios), elapsed)

        return results
    except Exception as e:
        L.exception("Exception in run_lca_for_scenarios")
        raise HTTPException(status_code=500, detail=f"LCA error: {e}") from e


@app.post("/documents/pdf")
async def upload_pdf_document(file: UploadFile = File(...)) -> Dict[str, Any]:
    _ensure_pdfplumber_available()

    filename = (file.filename or "uploaded.pdf").strip() or "uploaded.pdf"
    if not filename.lower().endswith(".pdf"):
        raise HTTPException(status_code=400, detail="Only PDF uploads are supported.")

    content = await file.read()
    if not content:
        raise HTTPException(status_code=400, detail="Uploaded PDF was empty.")

    document_id = uuid.uuid4().hex
    stored_path = DOCUMENT_CACHE_DIR / f"{document_id}.pdf"
    stored_path.write_bytes(content)

    try:
        metadata = _scan_pdf_metadata(stored_path)
    except Exception as exc:
        stored_path.unlink(missing_ok=True)
        raise HTTPException(
            status_code=400,
            detail=f"Failed to read uploaded PDF: {exc}",
        ) from exc

    document = {
        "id": document_id,
        "name": filename,
        "kind": "pdf",
        "page_count": metadata["page_count"],
        "detected_table_count": metadata["detected_table_count"],
        "detected_table_pages": metadata["detected_table_pages"],
        "uploaded_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    }
    DOCUMENT_STORE[document_id] = {
        **document,
        "path": str(stored_path),
    }
    return {"success": True, "document": document}


@app.delete("/documents/{document_id}")
def delete_document(document_id: str) -> Dict[str, Any]:
    stored = DOCUMENT_STORE.pop(document_id, None)
    if stored is None:
        raise HTTPException(status_code=404, detail="Document not found.")

    path = Path(stored.get("path", ""))
    if path.exists():
        path.unlink(missing_ok=True)
    return {"success": True, "document_id": document_id}


@app.post("/documents/pdf/query")
def query_pdf_document(payload: DocumentQueryRequest) -> Dict[str, Any]:
    _ensure_pdfplumber_available()
    stored = DOCUMENT_STORE.get(payload.document_id)
    if stored is None:
        raise HTTPException(status_code=404, detail="Uploaded document not found.")

    path = Path(stored.get("path", ""))
    if not path.is_file():
        raise HTTPException(
            status_code=410,
            detail="Uploaded document is no longer available on the backend.",
        )

    def _coerce_pages(raw: Any) -> list[int]:
        return [
            page_number
            for page_number in (raw or [])
            if isinstance(page_number, int) and page_number > 0
        ]

    def _clamp_tables(value: Any) -> int:
        try:
            return max(1, min(int(value), 5))
        except Exception:
            return max(1, min(int(payload.max_tables), 5))

    def _clamp_rows(value: Any) -> int:
        try:
            return max(1, min(int(value), 25))
        except Exception:
            return max(1, min(int(payload.max_rows), 25))

    # Batch queries (preferred): runs up to 5 sub-queries in one request.
    if payload.queries:
        items = payload.queries[:5]
        results: list[dict[str, Any]] = []
        for item in items:
            page_numbers = _coerce_pages(item.page_numbers)
            max_tables = _clamp_tables(item.max_tables)
            max_rows = _clamp_rows(item.max_rows)
            try:
                result = _query_pdf_tables(
                    pdf_path=path,
                    query=item.query,
                    page_numbers=page_numbers,
                    max_tables=max_tables,
                    max_rows=max_rows,
                )
                results.append(
                    {
                        "query": item.query,
                        "page_numbers": page_numbers,
                        "max_tables": max_tables,
                        "max_rows": max_rows,
                        **result,
                    }
                )
            except Exception as exc:
                # Keep other sub-queries usable even if one query fails.
                results.append(
                    {
                        "query": item.query,
                        "page_numbers": page_numbers,
                        "max_tables": max_tables,
                        "max_rows": max_rows,
                        "matches": [],
                        "fallback_text_matches": [],
                        "match_count": 0,
                        "error": str(exc),
                    }
                )
        total_matches = sum(len(item.get("matches") or []) for item in results)
        return {
            "success": True,
            "document": _public_document(stored),
            "results": results,
            "total_results": len(results),
            "total_matches": total_matches,
        }

    # Single query (legacy): kept for backward compatibility.
    query = (payload.query or "").strip()
    if not query:
        raise HTTPException(status_code=400, detail="Missing query.")

    page_numbers = _coerce_pages(payload.page_numbers)
    max_tables = _clamp_tables(payload.max_tables)
    max_rows = _clamp_rows(payload.max_rows)

    try:
        result = _query_pdf_tables(
            pdf_path=path,
            query=query,
            page_numbers=page_numbers,
            max_tables=max_tables,
            max_rows=max_rows,
        )
    except Exception as exc:
        raise HTTPException(
            status_code=500,
            detail=f"Document query failed: {exc}",
        ) from exc

    return {
        "success": True,
        "document": _public_document(stored),
        "query": query,
        "page_numbers": page_numbers,
        "max_tables": max_tables,
        "max_rows": max_rows,
        **result,
    }


def _ensure_pdfplumber_available() -> None:
    if pdfplumber is None:
        raise HTTPException(
            status_code=503,
            detail=(
                "pdfplumber is not installed in the Brightway backend environment. "
                f"Import error: {PDFPLUMBER_IMPORT_ERROR}"
            ),
        )


def _public_document(stored: Dict[str, Any]) -> Dict[str, Any]:
    return {
        "id": stored.get("id", ""),
        "name": stored.get("name", ""),
        "kind": stored.get("kind", "pdf"),
        "page_count": stored.get("page_count", 0),
        "detected_table_count": stored.get("detected_table_count", 0),
        "detected_table_pages": stored.get("detected_table_pages", []),
        "uploaded_at": stored.get("uploaded_at"),
    }


def _scan_pdf_metadata(pdf_path: Path) -> Dict[str, Any]:
    page_count = 0
    detected_table_count = 0
    detected_table_pages: list[int] = []
    with pdfplumber.open(str(pdf_path)) as pdf:
        for index, page in enumerate(pdf.pages, start=1):
            page_count += 1
            tables = _extract_tables_from_page(page)
            if tables:
                detected_table_count += len(tables)
                detected_table_pages.append(index)
    return {
        "page_count": page_count,
        "detected_table_count": detected_table_count,
        "detected_table_pages": detected_table_pages,
    }


def _query_pdf_tables(
    pdf_path: Path,
    query: str,
    page_numbers: list[int],
    max_tables: int,
    max_rows: int,
) -> Dict[str, Any]:
    query_tokens = _tokenize(query)
    table_matches: list[Dict[str, Any]] = []
    text_matches: list[Dict[str, Any]] = []

    with pdfplumber.open(str(pdf_path)) as pdf:
        selected_pages = page_numbers or list(range(1, len(pdf.pages) + 1))
        for page_number in selected_pages:
            if page_number < 1 or page_number > len(pdf.pages):
                continue
            page = pdf.pages[page_number - 1]
            page_text = _normalize_text(page.extract_text() or "")
            page_lines = [line for line in page_text.splitlines() if line.strip()]
            text_score = _score_text_blob(query_tokens, page_text)
            if text_score > 0:
                text_matches.append(
                    {
                        "page_number": page_number,
                        "score": text_score,
                        "lines": page_lines[:10],
                    }
                )

            tables = _extract_tables_from_page(page)
            for table_index, table in enumerate(tables, start=1):
                normalized = _normalize_table(table)
                if not normalized["rows"]:
                    continue
                match = _score_table_match(
                    query_tokens=query_tokens,
                    page_number=page_number,
                    table_index=table_index,
                    page_lines=page_lines,
                    headers=normalized["headers"],
                    rows=normalized["rows"],
                    max_rows=max_rows,
                )
                if match is not None:
                    table_matches.append(match)

    table_matches.sort(
        key=lambda item: (item.get("score", 0.0), -item.get("page_number", 0)),
        reverse=True,
    )
    text_matches.sort(
        key=lambda item: (item.get("score", 0.0), -item.get("page_number", 0)),
        reverse=True,
    )

    return {
        "matches": table_matches[:max_tables],
        "fallback_text_matches": text_matches[:3],
        "match_count": len(table_matches),
    }


def _extract_tables_from_page(page: Any) -> list[list[list[str]]]:
    tables = page.extract_tables(table_settings=_TABLE_SETTINGS_PRIMARY) or []
    cleaned = [_clean_table(table) for table in tables]
    cleaned = [table for table in cleaned if table]
    if cleaned:
        return cleaned

    fallback = page.extract_tables(table_settings=_TABLE_SETTINGS_FALLBACK) or []
    fallback_cleaned = [_clean_table(table) for table in fallback]
    return [table for table in fallback_cleaned if table]


def _clean_table(table: Any) -> list[list[str]]:
    if not isinstance(table, list):
        return []
    cleaned_rows: list[list[str]] = []
    for row in table:
        if not isinstance(row, list):
            continue
        normalized_row = [_normalize_text(cell or "") for cell in row]
        if any(cell for cell in normalized_row):
            cleaned_rows.append(normalized_row)
    return cleaned_rows


def _normalize_table(table: list[list[str]]) -> Dict[str, Any]:
    if not table:
        return {"headers": [], "rows": []}

    width = max(len(row) for row in table)
    padded_rows = [row + [""] * (width - len(row)) for row in table]
    headers = padded_rows[0]
    if not any(headers):
        headers = [f"column_{index + 1}" for index in range(width)]

    normalized_rows: list[Dict[str, Any]] = []
    data_rows = padded_rows[1:] if len(padded_rows) > 1 else padded_rows
    for row_index, row in enumerate(data_rows):
        row_object = {
            headers[col_index] if headers[col_index] else f"column_{col_index + 1}": row[col_index]
            for col_index in range(width)
        }
        normalized_rows.append(
            {
                "row_index": row_index,
                "values": row,
                "row_object": row_object,
            }
        )

    return {"headers": headers, "rows": normalized_rows}


def _score_table_match(
    query_tokens: list[str],
    page_number: int,
    table_index: int,
    page_lines: list[str],
    headers: list[str],
    rows: list[Dict[str, Any]],
    max_rows: int,
) -> Optional[Dict[str, Any]]:
    header_text = _normalize_text(" ".join(headers))
    page_text = _normalize_text(" ".join(page_lines[:8]))
    table_text = _normalize_text(
        " ".join(" ".join(row["values"]) for row in rows[: min(len(rows), 25)])
    )
    score = (
        _score_text_blob(query_tokens, header_text) * 4.0
        + _score_text_blob(query_tokens, page_text) * 1.5
        + _score_text_blob(query_tokens, table_text) * 2.0
    )

    row_matches: list[Dict[str, Any]] = []
    for row in rows:
        row_text = _normalize_text(" ".join(row["values"]))
        row_score = _score_text_blob(query_tokens, row_text)
        matched_cells = []
        for column_index, value in enumerate(row["values"]):
            cell_score = _score_text_blob(query_tokens, _normalize_text(value))
            if cell_score <= 0:
                continue
            matched_cells.append(
                {
                    "column_index": column_index,
                    "header": headers[column_index] if column_index < len(headers) else "",
                    "value": value,
                    "score": round(cell_score, 3),
                }
            )
        if row_score > 0 or matched_cells:
            row_matches.append(
                {
                    "row_index": row["row_index"],
                    "score": round(row_score, 3),
                    "values": row["values"],
                    "row_object": row["row_object"],
                    "matched_cells": matched_cells,
                }
            )

    row_matches.sort(key=lambda item: item.get("score", 0.0), reverse=True)
    if score <= 0 and not row_matches:
        return None

    # If the table matches via heading/page context, prefer returning a contiguous
    # slice of the table in original row order. Relevance-sorted rows are useful
    # for "search", but risky for scenario tables (it can drop non-matching rows).
    if score > 0:
        match_by_index = {item["row_index"]: item for item in row_matches}
        top_rows = []
        for row in rows[:max_rows]:
            matched = match_by_index.get(row["row_index"])
            if matched is None:
                top_rows.append(
                    {
                        "row_index": row["row_index"],
                        "score": 0.0,
                        "values": row["values"],
                        "row_object": row["row_object"],
                        "matched_cells": [],
                    }
                )
            else:
                top_rows.append(matched)
    else:
        top_rows = row_matches[:max_rows] if row_matches else [
            {
                "row_index": row["row_index"],
                "score": 0.0,
                "values": row["values"],
                "row_object": row["row_object"],
                "matched_cells": [],
            }
            for row in rows[:max_rows]
        ]

    return {
        "page_number": page_number,
        "table_index": table_index,
        "score": round(score + sum(item["score"] for item in top_rows[:2]), 3),
        "headers": headers,
        "page_context_lines": page_lines[:5],
        "rows": top_rows,
    }


def _normalize_text(value: str) -> str:
    return re.sub(r"\s+", " ", value.replace("\x00", " ")).strip()


def _tokenize(value: str) -> list[str]:
    tokens = [_normalize_text(token).lower() for token in _WORD_RE.findall(value)]
    return [token for token in tokens if token]


def _score_text_blob(tokens: list[str], blob: str) -> float:
    if not tokens:
        return 0.0
    normalized_blob = blob.lower()
    score = 0.0
    for token in tokens:
        if token in normalized_blob:
            score += 1.0 + (0.25 if len(token) >= 6 else 0.0)
    return score

if __name__ == "__main__":
    import uvicorn
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)
# uvicorn main:app --reload
