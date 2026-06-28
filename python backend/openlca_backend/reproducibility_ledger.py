from __future__ import annotations

import csv
import io
import json
import os
import sqlite3
import threading
from pathlib import Path
from typing import Any

from fastapi import FastAPI, HTTPException, Query
from fastapi.responses import FileResponse, PlainTextResponse
from pydantic import BaseModel, Field


_BUNDLE_ALIASES = {
    "normal": "normal",
    "uncertainty": "uncertainty",
    "optimization": "optimisation",
    "optimisation": "optimisation",
    "goal_seek": "optimisation",
}
_DEFAULT_LEDGER_PATH = (
    Path(__file__).resolve().parent / "runtime" / "reproducibility_ledger.sqlite"
)
_LEDGER_LOCK = threading.Lock()


class ReproducibilityRunRequest(BaseModel):
    bundle_name: str = Field(..., min_length=1)
    model_name: str = Field(..., min_length=1)
    prompt_hash: str = Field(..., min_length=1)
    status: str = Field(..., min_length=1)
    run_uid: str = Field(..., min_length=1)
    provider_label: str | None = None
    created_at: str | None = None
    metadata: dict[str, Any] | None = None


def register_reproducibility_ledger_routes(app: FastAPI) -> None:
    @app.post("/openlca/reproducibility-ledger/runs")
    def register_run(request: ReproducibilityRunRequest) -> dict[str, Any]:
        try:
            row, inserted = register_run_in_ledger(request)
        except ValueError as exc:
            raise HTTPException(status_code=400, detail=str(exc)) from exc

        bundle_name = row["bundle_name"]
        return {
            "success": True,
            "inserted": inserted,
            "run": row,
            "snapshot_filename": "Sequential_snapshot.csv",
            "bundle_name": bundle_name,
        }

    @app.get("/openlca/reproducibility-ledger/{bundle_name}/snapshot.csv")
    def download_bundle_snapshot(
        bundle_name: str,
        up_to_ledger_id: int | None = Query(default=None, ge=1),
    ) -> PlainTextResponse:
        normalized = _normalize_bundle_name(bundle_name)
        csv_text = build_bundle_snapshot_csv(
            bundle_name=normalized,
            up_to_ledger_id=up_to_ledger_id,
        )
        return PlainTextResponse(
            content=csv_text,
            media_type="text/csv; charset=utf-8",
            headers={
                "Content-Disposition": (
                    f'attachment; filename="{normalized}_Sequential_snapshot.csv"'
                )
            },
        )

    @app.get("/openlca/reproducibility-ledger/database.sqlite")
    def download_database() -> FileResponse:
        db_path = _ledger_path()
        _ensure_schema_path(db_path)
        return FileResponse(
            path=db_path,
            media_type="application/vnd.sqlite3",
            filename="run_ledger.sqlite",
        )


def register_run_in_ledger(
    request: ReproducibilityRunRequest,
    *,
    db_path: Path | None = None,
) -> tuple[dict[str, Any], bool]:
    bundle_name = _normalize_bundle_name(request.bundle_name)
    normalized_status = request.status.strip()
    if not normalized_status:
        raise ValueError("status must not be blank.")

    normalized_model_name = request.model_name.strip()
    if not normalized_model_name:
        raise ValueError("model_name must not be blank.")

    normalized_prompt_hash = request.prompt_hash.strip()
    if not normalized_prompt_hash:
        raise ValueError("prompt_hash must not be blank.")

    normalized_run_uid = request.run_uid.strip()
    if not normalized_run_uid:
        raise ValueError("run_uid must not be blank.")

    normalized_created_at = (request.created_at or "").strip() or None
    normalized_provider = (request.provider_label or "").strip() or None
    metadata_json = None
    if request.metadata is not None:
        metadata_json = json.dumps(request.metadata, sort_keys=True)

    path = db_path or _ledger_path()
    with _LEDGER_LOCK:
        _ensure_schema_path(path)
        conn = _open_connection(path)
        try:
            conn.execute("BEGIN IMMEDIATE")
            existing = conn.execute(
                """
                SELECT ledger_id, run_uid, bundle_name, model_name, prompt_hash,
                       run_index, status, provider_label, created_at, metadata_json
                FROM run_ledger
                WHERE run_uid = ?
                """,
                (normalized_run_uid,),
            ).fetchone()
            if existing is not None:
                conn.commit()
                return _row_to_public_dict(existing), False

            row = conn.execute(
                """
                SELECT COALESCE(MAX(run_index), 0) AS max_run_index
                FROM run_ledger
                WHERE bundle_name = ? AND model_name = ? AND prompt_hash = ?
                """,
                (bundle_name, normalized_model_name, normalized_prompt_hash),
            ).fetchone()
            next_run_index = int(row["max_run_index"]) + 1

            conn.execute(
                """
                INSERT INTO run_ledger (
                    run_uid,
                    bundle_name,
                    model_name,
                    prompt_hash,
                    run_index,
                    status,
                    provider_label,
                    created_at,
                    metadata_json
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, COALESCE(?, strftime('%Y-%m-%dT%H:%M:%fZ', 'now')), ?)
                """,
                (
                    normalized_run_uid,
                    bundle_name,
                    normalized_model_name,
                    normalized_prompt_hash,
                    next_run_index,
                    normalized_status,
                    normalized_provider,
                    normalized_created_at,
                    metadata_json,
                ),
            )
            saved = conn.execute(
                """
                SELECT ledger_id, run_uid, bundle_name, model_name, prompt_hash,
                       run_index, status, provider_label, created_at, metadata_json
                FROM run_ledger
                WHERE run_uid = ?
                """,
                (normalized_run_uid,),
            ).fetchone()
            if saved is None:
                raise RuntimeError("Inserted ledger row could not be reloaded.")
            conn.commit()
            return _row_to_public_dict(saved), True
        except Exception:
            conn.rollback()
            raise
        finally:
            conn.close()


def build_bundle_snapshot_csv(
    *,
    bundle_name: str,
    up_to_ledger_id: int | None = None,
    db_path: Path | None = None,
) -> str:
    normalized = _normalize_bundle_name(bundle_name)
    path = db_path or _ledger_path()
    with _LEDGER_LOCK:
        _ensure_schema_path(path)
        conn = _open_connection(path)
        try:
            if up_to_ledger_id is None:
                rows = conn.execute(
                    """
                    SELECT bundle_name, model_name, prompt_hash, run_index, status,
                           created_at, provider_label, run_uid
                    FROM run_ledger
                    WHERE bundle_name = ?
                    ORDER BY lower(model_name), prompt_hash, run_index, ledger_id
                    """,
                    (normalized,),
                ).fetchall()
            else:
                rows = conn.execute(
                    """
                    SELECT bundle_name, model_name, prompt_hash, run_index, status,
                           created_at, provider_label, run_uid
                    FROM run_ledger
                    WHERE bundle_name = ? AND ledger_id <= ?
                    ORDER BY lower(model_name), prompt_hash, run_index, ledger_id
                    """,
                    (normalized, up_to_ledger_id),
                ).fetchall()
        finally:
            conn.close()

    out = io.StringIO()
    writer = csv.writer(out, lineterminator="\n")
    writer.writerow(
        [
            "bundle_name",
            "model_name",
            "prompt_hash",
            "run_index",
            "status",
            "created_at",
            "provider_label",
            "run_uid",
        ]
    )
    for row in rows:
        writer.writerow(
            [
                row["bundle_name"],
                row["model_name"],
                row["prompt_hash"],
                row["run_index"],
                row["status"],
                row["created_at"],
                row["provider_label"] or "",
                row["run_uid"],
            ]
        )
    return out.getvalue()


def _ledger_path() -> Path:
    configured = (os.getenv("EARLYLCA_REPRO_LEDGER_PATH") or "").strip()
    if configured:
        return Path(configured).expanduser().resolve()
    return _DEFAULT_LEDGER_PATH


def _normalize_bundle_name(bundle_name: str) -> str:
    normalized = bundle_name.strip().lower()
    resolved = _BUNDLE_ALIASES.get(normalized)
    if resolved is None:
        allowed = ", ".join(sorted(set(_BUNDLE_ALIASES.values())))
        raise ValueError(f"bundle_name must be one of: {allowed}.")
    return resolved


def _ensure_schema_path(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    conn = _open_connection(path)
    try:
        _ensure_schema(conn)
    finally:
        conn.close()


def _open_connection(path: Path) -> sqlite3.Connection:
    conn = sqlite3.connect(path, timeout=30.0)
    conn.row_factory = sqlite3.Row
    return conn


def _ensure_schema(conn: sqlite3.Connection) -> None:
    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS run_ledger (
            ledger_id INTEGER PRIMARY KEY AUTOINCREMENT,
            run_uid TEXT NOT NULL UNIQUE,
            bundle_name TEXT NOT NULL,
            model_name TEXT NOT NULL,
            prompt_hash TEXT NOT NULL,
            run_index INTEGER NOT NULL,
            status TEXT NOT NULL,
            provider_label TEXT,
            created_at TEXT NOT NULL,
            metadata_json TEXT
        )
        """
    )
    conn.execute(
        """
        CREATE UNIQUE INDEX IF NOT EXISTS idx_run_ledger_series_index
        ON run_ledger (bundle_name, model_name, prompt_hash, run_index)
        """
    )
    conn.execute(
        """
        CREATE INDEX IF NOT EXISTS idx_run_ledger_bundle_created
        ON run_ledger (bundle_name, created_at, ledger_id)
        """
    )
    conn.commit()


def _row_to_public_dict(row: sqlite3.Row) -> dict[str, Any]:
    metadata_json = row["metadata_json"]
    return {
        "ledger_id": row["ledger_id"],
        "run_uid": row["run_uid"],
        "bundle_name": row["bundle_name"],
        "model_name": row["model_name"],
        "prompt_hash": row["prompt_hash"],
        "run_index": row["run_index"],
        "status": row["status"],
        "provider_label": row["provider_label"],
        "created_at": row["created_at"],
        "metadata": json.loads(metadata_json) if metadata_json else None,
    }
