"""Uncertainty propagation routes for the openLCA IPC backend."""

from __future__ import annotations

import csv
import html
import json
import math
import os
import random
import statistics
import tempfile
import threading
import time
import uuid
from statistics import NormalDist
from typing import Any

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field

try:
    from scipy.stats import qmc
except Exception as exc:  # pragma: no cover - env dependent
    qmc = None  # type: ignore[assignment]
    SCIPY_QMC_IMPORT_ERROR = str(exc)
else:
    SCIPY_QMC_IMPORT_ERROR = None

try:
    from reportlab.lib.pagesizes import A4
    from reportlab.lib.styles import getSampleStyleSheet
    from reportlab.platypus import Paragraph, SimpleDocTemplate, Spacer, Table, TableStyle
    from reportlab.lib import colors
except Exception as exc:  # pragma: no cover - env dependent
    REPORTLAB_IMPORT_ERROR = str(exc)
    REPORTLAB_AVAILABLE = False
else:
    REPORTLAB_IMPORT_ERROR = None
    REPORTLAB_AVAILABLE = True


class OpenLcaUncertaintyStartRequest(BaseModel):
    tool: str = Field(..., min_length=1)
    model_id: str | None = None
    product_system: str | None = None
    product_system_id: str | None = None
    functional_unit: dict[str, Any] = Field(default_factory=dict)
    impact_method: str | None = None
    impact_method_id: str | None = None
    impact_categories: list[Any] = Field(..., min_length=1)
    sampling: dict[str, Any] = Field(default_factory=dict)
    parameters: list[dict[str, Any]] = Field(..., min_length=1)
    outputs: dict[str, Any] = Field(default_factory=dict)
    user_prompt: str | None = None
    ipc_url: str | None = None


_UNCERTAINTY_JOBS: dict[str, dict[str, Any]] = {}
_UNCERTAINTY_LOCK = threading.Lock()
_MAX_UNCERTAINTY_EVENTS = 160
_UNSUPPORTED_STRUCTURAL_KEYS = {
    "flows",
    "processes",
    "providers",
    "provider",
    "datasets",
    "dataset",
    "database",
    "allocation",
    "system_boundary",
    "systemBoundary",
    "create_flow",
    "create_process",
    "change_provider",
    "remap_database",
}


def register_uncertainty_routes(app: FastAPI, deps: dict[str, Any]) -> None:
    """Register async uncertainty propagation routes on the main FastAPI app."""

    @app.post("/openlca/uncertainty-propagation/start")
    def start_uncertainty_propagation(
        request: OpenLcaUncertaintyStartRequest,
    ) -> dict[str, Any]:
        deps["ensure_openlca_available"]()
        ipc_url = request.ipc_url or deps["default_ipc_url"]
        client = deps["new_ipc_client"](ipc_url)
        validated = _validate_uncertainty_request(request, client, deps)
        artifact_dir = tempfile.mkdtemp(prefix="earlylca_uncertainty_")
        log_path = os.path.join(artifact_dir, "uncertainty_trace.jsonl")

        job_id = str(uuid.uuid4())
        job = {
            "job_id": job_id,
            "status": "queued",
            "created_at": time.time(),
            "updated_at": time.time(),
            "request": request.model_dump(),
            "validated_request": validated,
            "events": [],
            "result": None,
            "error": None,
            "cancel_requested": False,
            "artifact_dir": artifact_dir,
            "log_path": log_path,
        }
        with _UNCERTAINTY_LOCK:
            _UNCERTAINTY_JOBS[job_id] = job
        _append_uncertainty_event(
            job_id,
            "queued",
            "Uncertainty propagation job queued.",
            details={
                "sample_count": validated["sampling"]["n_samples"],
                "sampling_method": validated["sampling"]["method"],
                "parameter_count": len(validated["parameters"]),
                "impact_category_count": len(validated["impact_categories"]),
                "artifact_dir": artifact_dir,
                "log_path": log_path,
            },
        )

        thread = threading.Thread(
            target=_run_uncertainty_job,
            args=(job_id, validated, deps),
            daemon=True,
        )
        thread.start()
        return {"success": True, "job_id": job_id, "status": "queued"}

    @app.get("/openlca/uncertainty-propagation/{job_id}")
    def get_uncertainty_job(job_id: str) -> dict[str, Any]:
        with _UNCERTAINTY_LOCK:
            job = _UNCERTAINTY_JOBS.get(job_id)
            if job is None:
                raise HTTPException(
                    status_code=404,
                    detail=f"Uncertainty propagation job '{job_id}' not found.",
                )
            return dict(job)

    @app.post("/openlca/uncertainty-propagation/{job_id}/cancel")
    def cancel_uncertainty_job(job_id: str) -> dict[str, Any]:
        with _UNCERTAINTY_LOCK:
            job = _UNCERTAINTY_JOBS.get(job_id)
            if job is None:
                raise HTTPException(
                    status_code=404,
                    detail=f"Uncertainty propagation job '{job_id}' not found.",
                )
            job["cancel_requested"] = True
            job["updated_at"] = time.time()
            current_status = job.get("status")
        _append_uncertainty_event(
            job_id,
            "cancel_requested",
            "Cancellation requested by the client.",
            details={"status": current_status},
        )
        return {"success": True, "job_id": job_id, "status": current_status}


def _update_uncertainty_job(job_id: str, **updates: Any) -> dict[str, Any]:
    with _UNCERTAINTY_LOCK:
        job = _UNCERTAINTY_JOBS[job_id]
        job.update(updates)
        job["updated_at"] = time.time()
        return dict(job)


def _append_uncertainty_event(
    job_id: str,
    stage: str,
    message: str,
    *,
    details: dict[str, Any] | None = None,
) -> None:
    event = {
        "timestamp": time.time(),
        "stage": stage,
        "message": message,
    }
    if details:
        event["details"] = details
    with _UNCERTAINTY_LOCK:
        job = _UNCERTAINTY_JOBS[job_id]
        job.setdefault("events", []).append(event)
        if len(job["events"]) > _MAX_UNCERTAINTY_EVENTS:
            job["events"] = job["events"][-_MAX_UNCERTAINTY_EVENTS:]
        job["updated_at"] = time.time()
        log_path = job.get("log_path")
    _write_uncertainty_log_line(log_path, event)


def _write_uncertainty_log_line(log_path: Any, event: dict[str, Any]) -> None:
    if not isinstance(log_path, str) or not log_path.strip():
        return
    try:
        with open(log_path, "a", encoding="utf-8") as handle:
            handle.write(json.dumps(event, ensure_ascii=True, sort_keys=True))
            handle.write("\n")
    except Exception:
        return


def _uncertainty_cancelled(job_id: str) -> bool:
    with _UNCERTAINTY_LOCK:
        job = _UNCERTAINTY_JOBS.get(job_id)
        return bool(job and job.get("cancel_requested"))


def _validate_uncertainty_request(
    request: OpenLcaUncertaintyStartRequest,
    client: Any,
    deps: dict[str, Any],
) -> dict[str, Any]:
    if request.tool != "uncertainty_propagation":
        raise HTTPException(
            status_code=400,
            detail='tool must be exactly "uncertainty_propagation".',
        )

    raw_request = request.model_dump()
    unsupported_path = _find_unsupported_structural_content(raw_request)
    if unsupported_path is not None:
        raise HTTPException(
            status_code=400,
            detail=(
                "Structural model edits are unsupported in uncertainty propagation: "
                f"'{unsupported_path}'."
            ),
        )

    o = deps["olca_schema"]
    product_system_id = _resolve_product_system_id(
        client,
        o,
        request.product_system_id or request.product_system or "",
    )
    if not product_system_id:
        raise HTTPException(
            status_code=400,
            detail="product_system_id could not be resolved from the request.",
        )

    product_system_ref = client.get_descriptor(o.ProductSystem, uid=product_system_id)
    if product_system_ref is None:
        raise HTTPException(
            status_code=404,
            detail=f"Product system '{product_system_id}' not found.",
        )
    if product_system_ref.ref_type is None:
        product_system_ref.ref_type = o.RefType.ProductSystem

    product_system_entity = client.get(o.ProductSystem, uid=product_system_id)
    if product_system_entity is None:
        raise HTTPException(
            status_code=404,
            detail=f"Product system '{product_system_id}' could not be loaded.",
        )

    parameter_catalog = deps["build_parameter_catalog"](client, product_system_entity)
    if parameter_catalog is None:
        raise HTTPException(
            status_code=400,
            detail="No parameter catalog could be built for the selected product system.",
        )

    normalized_fu = _normalize_functional_unit(request.functional_unit)
    sampling = _normalize_sampling(request.sampling)
    outputs = _normalize_outputs(request.outputs)

    impact_method_ref = deps["pick_impact_method"](
        client,
        impact_method_id=(request.impact_method_id or "").strip()
        or _first_non_empty_method_id(request.impact_categories),
        impact_method_name=(request.impact_method or "").strip()
        or deps["default_impact_method_name"],
    )
    if impact_method_ref is None:
        raise HTTPException(
            status_code=400,
            detail="impact_method could not be resolved from the request.",
        )
    if impact_method_ref.ref_type is None:
        impact_method_ref.ref_type = o.RefType.ImpactMethod

    normalized_impact_categories = _resolve_impact_categories(
        client,
        o,
        impact_method_ref,
        request.impact_categories,
    )

    normalized_parameters = []
    for item in request.parameters:
        normalized_parameters.append(
            _resolve_parameter_spec(parameter_catalog, item),
        )

    return {
        "tool": "uncertainty_propagation",
        "model_id": (request.model_id or "").strip()
        or (product_system_ref.name or product_system_id),
        "product_system": product_system_ref.name or product_system_id,
        "product_system_id": product_system_id,
        "functional_unit": normalized_fu,
        "impact_method": impact_method_ref.name or impact_method_ref.id,
        "impact_method_id": impact_method_ref.id,
        "impact_categories": normalized_impact_categories,
        "sampling": sampling,
        "parameters": normalized_parameters,
        "outputs": outputs,
        "user_prompt": (request.user_prompt or "").strip(),
        "ipc_url": request.ipc_url or deps["default_ipc_url"],
    }


def _find_unsupported_structural_content(
    payload: Any,
    *,
    path: str = "$",
) -> str | None:
    if isinstance(payload, dict):
        for key, value in payload.items():
            normalized_key = str(key).strip().lower()
            if normalized_key in {item.lower() for item in _UNSUPPORTED_STRUCTURAL_KEYS}:
                return f"{path}.{key}"
            child = _find_unsupported_structural_content(
                value,
                path=f"{path}.{key}",
            )
            if child is not None:
                return child
        return None
    if isinstance(payload, list):
        for index, item in enumerate(payload):
            child = _find_unsupported_structural_content(
                item,
                path=f"{path}[{index}]",
            )
            if child is not None:
                return child
    return None


def _resolve_product_system_id(client: Any, o: Any, raw: str) -> str:
    needle = raw.strip()
    if not needle:
        return ""
    try:
        ref = client.get_descriptor(o.ProductSystem, uid=needle)
    except Exception:
        ref = None
    if ref is not None:
        return ref.id

    try:
        descriptors = client.get_descriptors(o.ProductSystem)
    except Exception as exc:
        raise HTTPException(
            status_code=502,
            detail=f"Failed to query product systems from openLCA IPC: {exc}",
        ) from exc

    lower = needle.lower()
    exact = [ref for ref in descriptors if (ref.name or "").strip().lower() == lower]
    if len(exact) == 1:
        return exact[0].id
    if len(exact) > 1:
        raise HTTPException(
            status_code=400,
            detail=(
                f'Product system name "{needle}" is ambiguous. Provide product_system_id.'
            ),
        )
    contains = [ref for ref in descriptors if lower in (ref.name or "").strip().lower()]
    if len(contains) == 1:
        return contains[0].id
    if len(contains) > 1:
        raise HTTPException(
            status_code=400,
            detail=(
                f'Product system name "{needle}" matched multiple results. Provide product_system_id.'
            ),
        )
    return ""


def _normalize_functional_unit(functional_unit: dict[str, Any]) -> dict[str, Any]:
    amount = _to_float(functional_unit.get("amount"))
    if amount is None:
        amount = 1.0
    if amount <= 0:
        raise HTTPException(
            status_code=400,
            detail="functional_unit.amount must be a positive number.",
        )
    unit = str(functional_unit.get("unit") or "").strip()
    return {"amount": amount, **({"unit": unit} if unit else {})}


def _normalize_sampling(sampling: dict[str, Any]) -> dict[str, Any]:
    method = str(sampling.get("method") or "latin_hypercube").strip().lower()
    if method not in {"latin_hypercube", "monte_carlo"}:
        raise HTTPException(
            status_code=400,
            detail='sampling.method must be "latin_hypercube" or "monte_carlo".',
        )
    n_samples = _to_int(sampling.get("n_samples")) or 250
    if n_samples < 10 or n_samples > 5000:
        raise HTTPException(
            status_code=400,
            detail="sampling.n_samples must be between 10 and 5000.",
        )
    random_seed = _to_int(sampling.get("random_seed"))
    return {
        "method": method,
        "n_samples": n_samples,
        "random_seed": 42 if random_seed is None else random_seed,
    }


def _normalize_outputs(outputs: dict[str, Any]) -> dict[str, Any]:
    percentiles = []
    raw_percentiles = outputs.get("percentiles")
    if isinstance(raw_percentiles, list):
        for item in raw_percentiles:
            value = _to_float(item)
            if value is None or value < 0 or value > 100:
                raise HTTPException(
                    status_code=400,
                    detail="outputs.percentiles must contain values between 0 and 100.",
                )
            if value not in percentiles:
                percentiles.append(value)
    if not percentiles:
        percentiles = [5.0, 50.0, 95.0]
    percentiles.sort()
    return {
        "percentiles": percentiles,
        "include_sample_matrix": outputs.get("include_sample_matrix") is not False,
        "include_failed_runs": outputs.get("include_failed_runs") is not False,
    }


def _first_non_empty_method_id(impact_categories: list[Any]) -> str:
    for item in impact_categories:
        if not isinstance(item, dict):
            continue
        method_id = str(item.get("impact_method_id") or "").strip()
        if method_id:
            return method_id
    return ""


def _resolve_impact_categories(
    client: Any,
    o: Any,
    impact_method_ref: Any,
    raw_categories: list[Any],
) -> list[dict[str, Any]]:
    try:
        impact_method = client.get(o.ImpactMethod, uid=impact_method_ref.id)
    except Exception as exc:
        raise HTTPException(
            status_code=502,
            detail=f"Failed to load impact method '{impact_method_ref.id}': {exc}",
        ) from exc
    if impact_method is None:
        raise HTTPException(
            status_code=404,
            detail=f"Impact method '{impact_method_ref.id}' could not be loaded.",
        )

    index = []
    for category in getattr(impact_method, "impact_categories", None) or []:
        if category is None:
            continue
        index.append(
            {
                "impact_category_id": getattr(category, "id", None) or "",
                "indicator": getattr(category, "name", None) or "",
                "unit": _extract_unit_like_name(
                    getattr(category, "reference_unit", None)
                    or getattr(category, "ref_unit", None)
                    or getattr(category, "unit", None)
                ),
            }
        )
    if not index:
        raise HTTPException(
            status_code=400,
            detail="Selected impact method does not expose impact categories.",
        )

    normalized = []
    seen = set()
    for item in raw_categories:
        if isinstance(item, str):
            raw_indicator = item.strip()
            raw_id = ""
        elif isinstance(item, dict):
            raw_indicator = str(item.get("indicator") or item.get("name") or "").strip()
            raw_id = str(item.get("impact_category_id") or "").strip()
            raw_method_id = str(item.get("impact_method_id") or "").strip()
            if raw_method_id and raw_method_id.lower() != impact_method_ref.id.lower():
                raise HTTPException(
                    status_code=400,
                    detail=(
                        "Uncertainty propagation may not mix impact methods in one request."
                    ),
                )
        else:
            raise HTTPException(
                status_code=400,
                detail="impact_categories entries must be strings or objects.",
            )

        resolved = _match_impact_category(index, raw_indicator, raw_id)
        if resolved is None:
            label = raw_indicator or raw_id
            raise HTTPException(
                status_code=400,
                detail=(
                    f'Impact category "{label}" is not available in the selected impact method.'
                ),
            )
        key = (
            resolved["impact_category_id"].strip().lower(),
            resolved["indicator"].strip().lower(),
        )
        if key in seen:
            continue
        seen.add(key)
        normalized.append(
            {
                "impact_method_id": impact_method_ref.id,
                "impact_method_name": impact_method_ref.name,
                "impact_category_id": resolved["impact_category_id"],
                "indicator": resolved["indicator"],
                **({"unit": resolved["unit"]} if resolved.get("unit") else {}),
            }
        )
    return normalized


def _match_impact_category(
    index: list[dict[str, Any]],
    raw_indicator: str,
    raw_id: str,
) -> dict[str, Any] | None:
    if raw_id:
        matches = [
            item
            for item in index
            if item["impact_category_id"].strip().lower() == raw_id.strip().lower()
        ]
        if len(matches) == 1:
            return matches[0]
    needle = _normalize_text(raw_indicator)
    if not needle:
        return None
    exact = [
        item
        for item in index
        if _normalize_text(item["indicator"]) == needle
    ]
    if len(exact) == 1:
        return exact[0]
    contains = [
        item
        for item in index
        if needle in _normalize_text(item["indicator"])
        or _normalize_text(item["indicator"]) in needle
    ]
    if len(contains) == 1:
        return contains[0]
    return None


def _resolve_parameter_spec(
    parameter_catalog: dict[str, Any],
    raw_parameter: dict[str, Any],
) -> dict[str, Any]:
    scope = str(raw_parameter.get("scope") or "").strip().lower()
    if scope not in {"global", "process"}:
        raise HTTPException(
            status_code=400,
            detail='parameters[].scope must be "global" or "process".',
        )
    name = str(raw_parameter.get("name") or "").strip()
    if not name:
        raise HTTPException(
            status_code=400,
            detail="parameters[].name is required.",
        )
    context = raw_parameter.get("context")
    meta = (
        _resolve_global_parameter(parameter_catalog, name)
        if scope == "global"
        else _resolve_process_parameter(parameter_catalog, name, context)
    )
    if not meta.get("editable", False):
        raise HTTPException(
            status_code=400,
            detail=(
                f'Parameter "{meta["name"]}" is dependent/calculated only and cannot be redefined safely.'
            ),
        )

    supplied_baseline = _to_float(raw_parameter.get("baseline_value"))
    if "baseline_value" in raw_parameter and supplied_baseline is None:
        raise HTTPException(
            status_code=400,
            detail=f'Parameter "{meta["name"]}" has a non-numeric baseline_value.',
        )

    uncertainty = raw_parameter.get("uncertainty")
    if not isinstance(uncertainty, dict):
        raise HTTPException(
            status_code=400,
            detail=f'Parameter "{meta["name"]}" is missing an uncertainty object.',
        )

    normalized_uncertainty = _normalize_distribution(uncertainty)
    normalized = {
        "scope": scope,
        "context": None,
        "name": meta["name"],
        "baseline_value": meta["baseline_value"],
        **({"unit": meta["unit"]} if meta.get("unit") else {}),
        "uncertainty": normalized_uncertainty,
    }
    if scope == "process":
        normalized["context"] = {
            **({"process_name": meta["process_name"]} if meta.get("process_name") else {}),
            "process_id": meta["process_id"],
        }
    if supplied_baseline is not None and abs(supplied_baseline - meta["baseline_value"]) > 1e-9:
        normalized["baseline_value_supplied"] = supplied_baseline
    return normalized


def _resolve_global_parameter(
    parameter_catalog: dict[str, Any],
    name: str,
) -> dict[str, Any]:
    key = name.strip().lower()
    meta = parameter_catalog.get("global_details", {}).get(key)
    if meta is None:
        if _parameter_exists_in_any_process(parameter_catalog, key):
            raise HTTPException(
                status_code=400,
                detail=f'Parameter "{name}" exists only in process scope, not global scope.',
            )
        raise HTTPException(
            status_code=400,
            detail=f'Global parameter "{name}" does not exist in the current model.',
        )
    return meta


def _resolve_process_parameter(
    parameter_catalog: dict[str, Any],
    name: str,
    context: Any,
) -> dict[str, Any]:
    key = name.strip().lower()
    if context is not None and not isinstance(context, dict):
        raise HTTPException(
            status_code=400,
            detail="Process parameter context must be null or an object.",
        )
    context_map = context if isinstance(context, dict) else {}
    process_id_hint = str(
        context_map.get("process_id") or context_map.get("id") or ""
    ).strip()
    process_name_hint = str(context_map.get("process_name") or "").strip()

    process_id = ""
    if process_id_hint:
        process_id = _resolve_process_id(parameter_catalog, process_id_hint)
        if not process_id:
            raise HTTPException(
                status_code=400,
                detail=f'Process context "{process_id_hint}" does not exist in the current model.',
            )
    elif process_name_hint:
        matches = parameter_catalog.get("process_name_ids_map", {}).get(
            process_name_hint.lower(),
            [],
        )
        if not matches:
            raise HTTPException(
                status_code=400,
                detail=f'Process name "{process_name_hint}" does not exist in the current model.',
            )
        if len(matches) > 1:
            raise HTTPException(
                status_code=400,
                detail=(
                    f'Process name "{process_name_hint}" is ambiguous. Provide process_id.'
                ),
            )
        process_id = matches[0]
    else:
        matches = []
        for pid, table in parameter_catalog.get("process_param_details", {}).items():
            if key in table:
                matches.append(table[key])
        if not matches:
            raise HTTPException(
                status_code=400,
                detail=f'Process parameter "{name}" does not exist in the current model.',
            )
        if len(matches) > 1:
            labels = sorted(
                [
                    f'{item.get("process_name") or item.get("process_id")} ({item.get("process_id")})'
                    for item in matches
                ]
            )
            raise HTTPException(
                status_code=400,
                detail=(
                    f'Parameter "{name}" is ambiguous across multiple processes: '
                    f'{", ".join(labels)}. Provide process context.'
                ),
            )
        return matches[0]

    table = parameter_catalog.get("process_param_details", {}).get(process_id, {})
    meta = table.get(key)
    if meta is None:
        raise HTTPException(
            status_code=400,
            detail=(
                f'Process parameter "{name}" does not exist for process "{process_id}".'
            ),
        )
    return meta


def _parameter_exists_in_any_process(
    parameter_catalog: dict[str, Any],
    key: str,
) -> bool:
    for table in parameter_catalog.get("process_param_details", {}).values():
        if key in table:
            return True
    return False


def _resolve_process_id(parameter_catalog: dict[str, Any], raw: str) -> str:
    needle = raw.strip()
    if not needle:
        return ""
    for process_id in parameter_catalog.get("process_ids", set()):
        if process_id.lower() == needle.lower():
            return process_id
    matches = parameter_catalog.get("process_name_ids_map", {}).get(
        needle.lower(),
        [],
    )
    if len(matches) == 1:
        return matches[0]
    return ""


def _normalize_distribution(raw: dict[str, Any]) -> dict[str, Any]:
    distribution_type = str(raw.get("distributionType") or "").strip()
    if distribution_type == "UNIFORM_DISTRIBUTION":
        minimum = _required_float(raw, "minimum")
        maximum = _required_float(raw, "maximum")
        if minimum >= maximum:
            raise HTTPException(
                status_code=400,
                detail="UNIFORM_DISTRIBUTION requires minimum < maximum.",
            )
        return {
            "distributionType": distribution_type,
            "minimum": minimum,
            "maximum": maximum,
        }
    if distribution_type == "TRIANGLE_DISTRIBUTION":
        minimum = _required_float(raw, "minimum")
        mode = _required_float(raw, "mode")
        maximum = _required_float(raw, "maximum")
        if minimum >= maximum or mode < minimum or mode > maximum:
            raise HTTPException(
                status_code=400,
                detail=(
                    "TRIANGLE_DISTRIBUTION requires minimum < maximum and minimum <= mode <= maximum."
                ),
            )
        return {
            "distributionType": distribution_type,
            "minimum": minimum,
            "mode": mode,
            "maximum": maximum,
        }
    if distribution_type == "NORMAL_DISTRIBUTION":
        mean = _required_float(raw, "mean")
        sd = _required_float(raw, "sd")
        if sd <= 0:
            raise HTTPException(
                status_code=400,
                detail="NORMAL_DISTRIBUTION requires sd > 0.",
            )
        lower_bound = _to_float(raw.get("lower_bound"))
        upper_bound = _to_float(raw.get("upper_bound"))
        if lower_bound is not None and upper_bound is not None and lower_bound > upper_bound:
            raise HTTPException(
                status_code=400,
                detail="NORMAL_DISTRIBUTION lower_bound must be <= upper_bound.",
            )
        return {
            "distributionType": distribution_type,
            "mean": mean,
            "sd": sd,
            **({"lower_bound": lower_bound} if lower_bound is not None else {}),
            **({"upper_bound": upper_bound} if upper_bound is not None else {}),
        }
    if distribution_type == "LOG_NORMAL_DISTRIBUTION":
        geom_mean = _required_float(raw, "geomMean")
        geom_sd = _required_float(raw, "geomSd")
        if geom_mean <= 0 or geom_sd <= 1:
            raise HTTPException(
                status_code=400,
                detail="LOG_NORMAL_DISTRIBUTION requires geomMean > 0 and geomSd > 1.",
            )
        return {
            "distributionType": distribution_type,
            "geomMean": geom_mean,
            "geomSd": geom_sd,
        }
    raise HTTPException(
        status_code=400,
        detail=f"Unsupported distributionType '{distribution_type}'.",
    )


def _run_uncertainty_job(
    job_id: str,
    request: dict[str, Any],
    deps: dict[str, Any],
) -> None:
    start = time.time()
    try:
        _update_uncertainty_job(job_id, status="running", started_at=start)
        _append_uncertainty_event(
            job_id,
            "started",
            "Uncertainty propagation worker started.",
            details={
                "started_at": start,
                "artifact_dir": _job_value(job_id, "artifact_dir"),
                "log_path": _job_value(job_id, "log_path"),
            },
        )

        client = deps["new_ipc_client"](request["ipc_url"])
        o = deps["olca_schema"]

        product_system_ref = client.get_descriptor(
            o.ProductSystem,
            uid=request["product_system_id"],
        )
        if product_system_ref is None:
            raise RuntimeError(
                f'Product system "{request["product_system_id"]}" not found.'
            )
        if product_system_ref.ref_type is None:
            product_system_ref.ref_type = o.RefType.ProductSystem

        product_system_entity = client.get(
            o.ProductSystem,
            uid=request["product_system_id"],
        )
        if product_system_entity is None:
            raise RuntimeError(
                f'Product system "{request["product_system_id"]}" could not be loaded.'
            )

        parameter_catalog = deps["build_parameter_catalog"](client, product_system_entity)
        impact_method_ref = deps["pick_impact_method"](
            client,
            impact_method_id=request["impact_method_id"],
            impact_method_name=request["impact_method"],
        )
        if impact_method_ref is None:
            raise RuntimeError(
                f'Impact method "{request["impact_method_id"]}" could not be resolved.'
            )
        if impact_method_ref.ref_type is None:
            impact_method_ref.ref_type = o.RefType.ImpactMethod

        _append_uncertainty_event(
            job_id,
            "resolved_inputs",
            "Resolved product system, impact method, and parameter catalog.",
            details={
                "product_system_id": request["product_system_id"],
                "impact_method_id": request["impact_method_id"],
                "parameter_count": len(request["parameters"]),
                "impact_category_count": len(request["impact_categories"]),
            },
        )

        samples, warnings = _generate_samples(request)
        if warnings:
            _append_uncertainty_event(
                job_id,
                "sampling_warning",
                "Sampling completed with warnings.",
                details={"warnings": warnings},
            )
        sample_results = []
        failed_runs = []
        successful_rows = []
        selected_categories = request["impact_categories"]
        n_samples = request["sampling"]["n_samples"]
        amount = request["functional_unit"]["amount"]
        output_dir = str(_job_value(job_id, "artifact_dir") or tempfile.mkdtemp(prefix="earlylca_uncertainty_"))
        partial_sample_results_path = os.path.join(output_dir, "sample_results.partial.csv")
        _init_sample_results_csv(
            partial_sample_results_path,
            selected_categories,
            request["parameters"],
        )

        for sample_index, sampled_values in enumerate(samples, start=1):
            if _uncertainty_cancelled(job_id):
                raise RuntimeError("Uncertainty propagation job was cancelled.")

            parameter_values = []
            changes = []
            for parameter, sampled_value in zip(request["parameters"], sampled_values):
                scope = parameter["scope"]
                name = parameter["name"]
                context = parameter.get("context") or {}
                if scope == "global":
                    changes.append(
                        {
                            "field": f"parameters.global.{name}",
                            "new_value": sampled_value,
                        }
                    )
                else:
                    changes.append(
                        {
                            "field": f"parameters.process.{name}",
                            "process_id": context["process_id"],
                            "new_value": sampled_value,
                        }
                    )
                parameter_values.append(
                    {
                        "scope": scope,
                        "name": name,
                        **({"context": context} if scope == "process" else {}),
                        "value": sampled_value,
                    }
                )

            try:
                result = deps["run_single_scenario"](
                    client=client,
                    scenario_model={
                        "changes": changes,
                        "number_functional_units": amount,
                    },
                    product_system_ref=product_system_ref,
                    impact_method_ref=impact_method_ref,
                    parameter_catalog=parameter_catalog,
                )
                lcia_results = _extract_selected_lcia_results(
                    result,
                    selected_categories,
                    deps["coerce_float"],
                )
                row = {
                    "sample_id": sample_index,
                    "parameter_values": parameter_values,
                    "lcia_results": lcia_results,
                    "run_status": "success",
                    "error_message": "",
                }
                sample_results.append(row)
                successful_rows.append(row)
                _append_sample_result_csv_row(
                    partial_sample_results_path,
                    row,
                    selected_categories,
                )
            except Exception as exc:
                row = {
                    "sample_id": sample_index,
                    "parameter_values": parameter_values,
                    "lcia_results": {},
                    "run_status": "failed",
                    "error_message": str(exc),
                }
                sample_results.append(row)
                failed_runs.append(row)
                _append_sample_result_csv_row(
                    partial_sample_results_path,
                    row,
                    selected_categories,
                )
                if len(failed_runs) <= 5:
                    _append_uncertainty_event(
                        job_id,
                        "sample_failed",
                        f"Sample {sample_index} failed.",
                        details={
                            "sample_index": sample_index,
                            "error": str(exc),
                            "parameter_values": parameter_values,
                        },
                    )

            if sample_index == 1 or sample_index % 10 == 0 or sample_index == n_samples:
                _append_uncertainty_event(
                    job_id,
                    "progress",
                    f"Processed sample {sample_index}/{n_samples}.",
                    details={
                        "sample_index": sample_index,
                        "n_samples": n_samples,
                        "n_successful": len(successful_rows),
                        "n_failed": len(failed_runs),
                    },
                )

        impact_summaries = _summarize_impacts(
            successful_rows,
            selected_categories,
            request["outputs"]["percentiles"],
        )

        sample_results_path = os.path.join(output_dir, "sample_results.csv")
        report_html_path = os.path.join(output_dir, "uncertainty_report.html")
        report_pdf_path = os.path.join(output_dir, "uncertainty_report.pdf")
        _write_sample_results_csv(sample_results_path, sample_results, selected_categories)
        _write_uncertainty_report(
            report_html_path,
            request,
            impact_summaries,
            len(successful_rows),
            len(failed_runs),
            warnings,
        )
        generated_pdf = _write_uncertainty_report_pdf(
            report_pdf_path,
            request,
            impact_summaries,
            len(successful_rows),
            len(failed_runs),
            warnings,
        )
        if not generated_pdf:
            warnings.append(
                "Backend PDF report export was unavailable; HTML report was generated instead."
                + (
                    f" Import error: {REPORTLAB_IMPORT_ERROR}"
                    if REPORTLAB_IMPORT_ERROR
                    else ""
                )
            )

        result_payload = {
            "tool": "uncertainty_propagation",
            "status": "success" if not failed_runs else "partial_success",
            "n_requested": n_samples,
            "n_successful": len(successful_rows),
            "n_failed": len(failed_runs),
            "parameters": [
                _distribution_summary(parameter) for parameter in request["parameters"]
            ],
            "impact_summaries": impact_summaries,
            "sample_results_path": sample_results_path,
            "partial_sample_results_path": partial_sample_results_path,
            "report_path": report_pdf_path if generated_pdf else report_html_path,
            "report_html_path": report_html_path,
            "report_pdf_path": report_pdf_path if generated_pdf else "",
            "log_path": _job_value(job_id, "log_path") or "",
            "warnings": warnings,
        }
        if request["outputs"]["include_sample_matrix"]:
            result_payload["sample_matrix"] = sample_results
        if request["outputs"]["include_failed_runs"]:
            result_payload["failed_runs"] = failed_runs

        _update_uncertainty_job(
            job_id,
            status="completed",
            completed_at=time.time(),
            result=result_payload,
        )
        _append_uncertainty_event(
            job_id,
            "completed",
            "Uncertainty propagation completed.",
            details={
                "n_requested": n_samples,
                "n_successful": len(successful_rows),
                "n_failed": len(failed_runs),
                "sample_results_path": sample_results_path,
                "partial_sample_results_path": partial_sample_results_path,
                "report_html_path": report_html_path,
                "report_pdf_path": report_pdf_path if generated_pdf else "",
                "log_path": _job_value(job_id, "log_path") or "",
            },
        )
    except Exception as exc:
        status = "cancelled" if _uncertainty_cancelled(job_id) else "failed"
        _update_uncertainty_job(
            job_id,
            status=status,
            completed_at=time.time(),
            error=str(exc),
        )
        _append_uncertainty_event(
            job_id,
            status,
            "Uncertainty propagation terminated.",
            details={"error": str(exc)},
        )


def _job_value(job_id: str, key: str) -> Any:
    with _UNCERTAINTY_LOCK:
        job = _UNCERTAINTY_JOBS.get(job_id) or {}
        return job.get(key)


def _generate_samples(request: dict[str, Any]) -> tuple[list[list[float]], list[str]]:
    parameters = request["parameters"]
    sampling = request["sampling"]
    n_samples = sampling["n_samples"]
    seed = sampling["random_seed"]
    method = sampling["method"]
    warnings = []

    unit_matrix = []
    if method == "latin_hypercube":
        if qmc is None:
            warnings.append(
                "SciPy LatinHypercube was unavailable; fell back to pseudo-random Monte Carlo."
                + (f" Import error: {SCIPY_QMC_IMPORT_ERROR}" if SCIPY_QMC_IMPORT_ERROR else "")
            )
            randomizer = random.Random(seed)
            unit_matrix = [
                [randomizer.random() for _ in parameters] for _ in range(n_samples)
            ]
        else:
            sampler = qmc.LatinHypercube(d=len(parameters), seed=seed)
            unit_matrix = sampler.random(n=n_samples).tolist()
    else:
        randomizer = random.Random(seed)
        unit_matrix = [
            [randomizer.random() for _ in parameters] for _ in range(n_samples)
        ]

    samples = []
    for row in unit_matrix:
        samples.append(
            [
                _sample_from_distribution(parameter["uncertainty"], u)
                for parameter, u in zip(parameters, row)
            ]
        )
    return samples, warnings


def _sample_from_distribution(uncertainty: dict[str, Any], u: float) -> float:
    distribution_type = uncertainty["distributionType"]
    u = min(max(float(u), 1e-12), 1 - 1e-12)
    if distribution_type == "UNIFORM_DISTRIBUTION":
        minimum = uncertainty["minimum"]
        maximum = uncertainty["maximum"]
        return minimum + (maximum - minimum) * u
    if distribution_type == "TRIANGLE_DISTRIBUTION":
        minimum = uncertainty["minimum"]
        mode = uncertainty["mode"]
        maximum = uncertainty["maximum"]
        c = (mode - minimum) / (maximum - minimum)
        if u <= c:
            return minimum + math.sqrt(u * (maximum - minimum) * (mode - minimum))
        return maximum - math.sqrt((1 - u) * (maximum - minimum) * (maximum - mode))
    if distribution_type == "NORMAL_DISTRIBUTION":
        mean = uncertainty["mean"]
        sd = uncertainty["sd"]
        value = NormalDist(mu=mean, sigma=sd).inv_cdf(u)
        lower_bound = uncertainty.get("lower_bound")
        upper_bound = uncertainty.get("upper_bound")
        if lower_bound is not None:
            value = max(lower_bound, value)
        if upper_bound is not None:
            value = min(upper_bound, value)
        return value
    if distribution_type == "LOG_NORMAL_DISTRIBUTION":
        mu = math.log(uncertainty["geomMean"])
        sigma = math.log(uncertainty["geomSd"])
        return math.exp(NormalDist(mu=mu, sigma=sigma).inv_cdf(u))
    raise RuntimeError(f"Unsupported distributionType '{distribution_type}'.")


def _extract_selected_lcia_results(
    result: dict[str, Any],
    selected_categories: list[dict[str, Any]],
    coerce_float: Any,
) -> dict[str, dict[str, Any]]:
    selected_by_id = {
        str(item.get("impact_category_id") or "").strip().lower(): item
        for item in selected_categories
        if str(item.get("impact_category_id") or "").strip()
    }
    selected_by_indicator = {
        _normalize_text(str(item.get("indicator") or "")): item
        for item in selected_categories
    }

    extracted = {}
    score_items = result.get("score_items")
    if isinstance(score_items, list):
        for raw_item in score_items:
            if not isinstance(raw_item, dict):
                continue
            item = dict(raw_item)
            impact_category_id = str(item.get("impact_category_id") or "").strip().lower()
            indicator_key = _normalize_text(str(item.get("indicator") or ""))
            selected = selected_by_id.get(impact_category_id) or selected_by_indicator.get(indicator_key)
            if selected is None:
                continue
            value = coerce_float(item.get("value"))
            if value is None:
                continue
            label = str(selected.get("indicator") or item.get("indicator") or "").strip()
            extracted[label] = {
                "value": float(value),
                "unit": str(item.get("unit") or selected.get("unit") or "").strip(),
                "impact_category_id": str(selected.get("impact_category_id") or item.get("impact_category_id") or "").strip(),
            }

    missing = [
        str(item.get("indicator") or "").strip()
        for item in selected_categories
        if str(item.get("indicator") or "").strip() not in extracted
    ]
    if missing:
        raise RuntimeError(
            "Selected impact categories were not returned by openLCA: "
            + ", ".join(missing)
        )
    return extracted


def _summarize_impacts(
    successful_rows: list[dict[str, Any]],
    selected_categories: list[dict[str, Any]],
    percentiles: list[float],
) -> list[dict[str, Any]]:
    summaries = []
    if not successful_rows:
        return summaries
    for category in selected_categories:
        label = str(category.get("indicator") or "").strip()
        unit = str(category.get("unit") or "").strip()
        values = [
            float(row["lcia_results"][label]["value"])
            for row in successful_rows
            if label in row["lcia_results"]
        ]
        if not values:
            continue
        summary = {
            "impact_category": label,
            "unit": unit,
            "mean": statistics.fmean(values),
            "sd": statistics.stdev(values) if len(values) > 1 else 0.0,
            "min": min(values),
            "max": max(values),
        }
        percentile_map = {}
        for percentile in percentiles:
            value = _percentile(values, percentile)
            key = _percentile_key(percentile)
            summary[key] = value
            percentile_map[key] = value
        summary["percentiles"] = percentile_map
        summaries.append(summary)
    return summaries


def _percentile(values: list[float], percentile: float) -> float:
    ordered = sorted(values)
    if len(ordered) == 1:
        return ordered[0]
    rank = (len(ordered) - 1) * (percentile / 100.0)
    low = math.floor(rank)
    high = math.ceil(rank)
    if low == high:
        return ordered[low]
    fraction = rank - low
    return ordered[low] + (ordered[high] - ordered[low]) * fraction


def _percentile_key(percentile: float) -> str:
    if float(percentile).is_integer():
        return f"p{int(percentile)}"
    return f"p{str(percentile).replace('.', '_')}"


def _distribution_summary(parameter: dict[str, Any]) -> dict[str, Any]:
    uncertainty = parameter["uncertainty"]
    summary = {
        "scope": parameter["scope"],
        "context": parameter.get("context"),
        "name": parameter["name"],
        "distributionType": uncertainty["distributionType"],
    }
    for key in (
        "minimum",
        "mode",
        "maximum",
        "mean",
        "sd",
        "geomMean",
        "geomSd",
        "lower_bound",
        "upper_bound",
    ):
        if key in uncertainty:
            summary[key] = uncertainty[key]
    return summary


def _write_sample_results_csv(
    path: str,
    sample_results: list[dict[str, Any]],
    selected_categories: list[dict[str, Any]],
) -> None:
    parameter_columns = []
    seen_parameter_columns = set()
    for row in sample_results:
        for parameter in row["parameter_values"]:
            label = _parameter_column_label(parameter)
            if label not in seen_parameter_columns:
                seen_parameter_columns.add(label)
                parameter_columns.append(label)

    impact_columns = [str(item.get("indicator") or "").strip() for item in selected_categories]
    with open(path, "w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        writer.writerow(
            ["sample_id", "run_status", "error_message", *parameter_columns, *impact_columns]
        )
        for row in sample_results:
            parameter_values = {
                _parameter_column_label(parameter): parameter["value"]
                for parameter in row["parameter_values"]
            }
            impact_values = {
                label: row["lcia_results"].get(label, {}).get("value", "")
                for label in impact_columns
            }
            writer.writerow(
                [
                    row["sample_id"],
                    row["run_status"],
                    row["error_message"],
                    *[parameter_values.get(label, "") for label in parameter_columns],
                    *[impact_values.get(label, "") for label in impact_columns],
                ]
            )


def _init_sample_results_csv(
    path: str,
    selected_categories: list[dict[str, Any]],
    parameters: list[dict[str, Any]],
) -> None:
    parameter_columns = [_parameter_column_label(parameter) for parameter in parameters]
    impact_columns = [str(item.get("indicator") or "").strip() for item in selected_categories]
    with open(path, "w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        writer.writerow(
            ["sample_id", "run_status", "error_message", *parameter_columns, *impact_columns]
        )


def _append_sample_result_csv_row(
    path: str,
    row: dict[str, Any],
    selected_categories: list[dict[str, Any]],
) -> None:
    parameter_values = {
        _parameter_column_label(parameter): parameter["value"]
        for parameter in row["parameter_values"]
    }
    impact_columns = [str(item.get("indicator") or "").strip() for item in selected_categories]
    impact_values = {
        label: row["lcia_results"].get(label, {}).get("value", "")
        for label in impact_columns
    }
    ordered_parameter_columns = [_parameter_column_label(parameter) for parameter in row["parameter_values"]]
    with open(path, "a", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        writer.writerow(
            [
                row["sample_id"],
                row["run_status"],
                row["error_message"],
                *[parameter_values.get(label, "") for label in ordered_parameter_columns],
                *[impact_values.get(label, "") for label in impact_columns],
            ]
        )


def _write_uncertainty_report(
    path: str,
    request: dict[str, Any],
    impact_summaries: list[dict[str, Any]],
    n_successful: int,
    n_failed: int,
    warnings: list[str],
) -> None:
    parameter_rows = "".join(
        [
            "<tr>"
            f"<td>{html.escape(parameter['scope'])}</td>"
            f"<td>{html.escape(_parameter_report_label(parameter))}</td>"
            f"<td>{html.escape(parameter['uncertainty']['distributionType'])}</td>"
            f"<td>{html.escape(_distribution_report_summary(parameter['uncertainty']))}</td>"
            "</tr>"
            for parameter in request["parameters"]
        ]
    )
    summary_rows = "".join(
        [
            "<tr>"
            f"<td>{html.escape(summary['impact_category'])}</td>"
            f"<td>{html.escape(summary.get('unit', ''))}</td>"
            f"<td>{summary['mean']:.6g}</td>"
            f"<td>{summary['sd']:.6g}</td>"
            f"<td>{summary['min']:.6g}</td>"
            f"<td>{summary['max']:.6g}</td>"
            + "".join(
                [
                    f"<td>{summary[key]:.6g}</td>"
                    for key in summary.get("percentiles", {}).keys()
                ]
            )
            + "</tr>"
            for summary in impact_summaries
        ]
    )
    percentile_headers = ""
    if impact_summaries:
        percentile_headers = "".join(
            [
                f"<th>{html.escape(key)}</th>"
                for key in impact_summaries[0].get("percentiles", {}).keys()
            ]
        )
    warning_list = "".join([f"<li>{html.escape(text)}</li>" for text in warnings])

    html_doc = f"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>EarlyLCA Uncertainty Propagation Report</title>
  <style>
    body {{ font-family: Arial, sans-serif; margin: 28px; color: #1d2939; }}
    h1, h2 {{ color: #184d63; }}
    table {{ border-collapse: collapse; width: 100%; margin-bottom: 20px; }}
    th, td {{ border: 1px solid #d0d7de; padding: 8px; text-align: left; font-size: 13px; }}
    th {{ background: #f4f7fb; }}
    .muted {{ color: #667085; }}
    .card {{ background: #f8fafc; border: 1px solid #d0d7de; padding: 14px; margin-bottom: 18px; }}
  </style>
</head>
<body>
  <h1>EarlyLCA Uncertainty Propagation Report</h1>
  <p class="muted">Generated {time.strftime("%Y-%m-%d %H:%M:%S")}</p>
  <div class="card">
    <strong>Product system:</strong> {html.escape(request["product_system"])}<br>
    <strong>Impact method:</strong> {html.escape(request["impact_method"])}<br>
    <strong>Sampling method:</strong> {html.escape(request["sampling"]["method"])}<br>
    <strong>Requested / successful / failed runs:</strong> {request["sampling"]["n_samples"]} / {n_successful} / {n_failed}
  </div>
  <h2>User Prompt</h2>
  <div class="card">{html.escape(request.get("user_prompt") or "Not supplied")}</div>
  <h2>Parameter Uncertainty Table</h2>
  <table>
    <thead>
      <tr><th>Scope</th><th>Parameter</th><th>Distribution</th><th>Specification</th></tr>
    </thead>
    <tbody>{parameter_rows}</tbody>
  </table>
  <h2>Percentile Summary Table</h2>
  <table>
    <thead>
      <tr>
        <th>Impact category</th><th>Unit</th><th>Mean</th><th>SD</th><th>Min</th><th>Max</th>{percentile_headers}
      </tr>
    </thead>
    <tbody>{summary_rows}</tbody>
  </table>
  <h2>Warnings</h2>
  <ul>{warning_list or '<li>None</li>'}</ul>
  <p><strong>Statement:</strong> Uncertainty distributions were supplied by the user or source document. The framework did not infer uncertainty distributions automatically.</p>
</body>
</html>
"""
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(html_doc)


def _write_uncertainty_report_pdf(
    path: str,
    request: dict[str, Any],
    impact_summaries: list[dict[str, Any]],
    n_successful: int,
    n_failed: int,
    warnings: list[str],
) -> bool:
    if not REPORTLAB_AVAILABLE:
        return False
    styles = getSampleStyleSheet()
    story = [
        Paragraph("EarlyLCA Uncertainty Propagation Report", styles["Title"]),
        Spacer(1, 12),
        Paragraph(
            f"Generated {time.strftime('%Y-%m-%d %H:%M:%S')}",
            styles["Normal"],
        ),
        Spacer(1, 12),
        Paragraph("User Prompt", styles["Heading2"]),
        Paragraph(html.escape(request.get("user_prompt") or "Not supplied"), styles["BodyText"]),
        Spacer(1, 12),
        Paragraph("Run Context", styles["Heading2"]),
    ]
    context_rows = [
        ["Product system", request["product_system"]],
        ["Impact method", request["impact_method"]],
        ["Sampling method", request["sampling"]["method"]],
        [
            "Requested / successful / failed",
            f'{request["sampling"]["n_samples"]} / {n_successful} / {n_failed}',
        ],
    ]
    context_table = Table(context_rows, colWidths=[150, 360])
    context_table.setStyle(
        TableStyle(
            [
                ("GRID", (0, 0), (-1, -1), 0.5, colors.lightgrey),
                ("BACKGROUND", (0, 0), (0, -1), colors.whitesmoke),
                ("VALIGN", (0, 0), (-1, -1), "TOP"),
            ]
        )
    )
    story.extend([context_table, Spacer(1, 12), Paragraph("Parameter Uncertainty", styles["Heading2"])])
    parameter_rows = [["Scope", "Parameter", "Distribution", "Specification"]]
    for parameter in request["parameters"]:
        parameter_rows.append(
            [
                parameter["scope"],
                _parameter_report_label(parameter),
                parameter["uncertainty"]["distributionType"],
                _distribution_report_summary(parameter["uncertainty"]),
            ]
        )
    parameter_table = Table(parameter_rows, repeatRows=1)
    parameter_table.setStyle(
        TableStyle(
            [
                ("GRID", (0, 0), (-1, -1), 0.5, colors.lightgrey),
                ("BACKGROUND", (0, 0), (-1, 0), colors.whitesmoke),
                ("VALIGN", (0, 0), (-1, -1), "TOP"),
                ("FONTSIZE", (0, 0), (-1, -1), 8),
            ]
        )
    )
    story.extend([parameter_table, Spacer(1, 12), Paragraph("Percentile Summary", styles["Heading2"])])
    percentile_keys = list(impact_summaries[0].get("percentiles", {}).keys()) if impact_summaries else []
    summary_rows = [["Impact category", "Unit", "Mean", "SD", "Min", "Max", *percentile_keys]]
    for summary in impact_summaries:
        summary_rows.append(
            [
                summary["impact_category"],
                summary.get("unit", ""),
                _fmt_float(summary.get("mean")),
                _fmt_float(summary.get("sd")),
                _fmt_float(summary.get("min")),
                _fmt_float(summary.get("max")),
                *[_fmt_float(summary.get(key)) for key in percentile_keys],
            ]
        )
    summary_table = Table(summary_rows, repeatRows=1)
    summary_table.setStyle(
        TableStyle(
            [
                ("GRID", (0, 0), (-1, -1), 0.5, colors.lightgrey),
                ("BACKGROUND", (0, 0), (-1, 0), colors.whitesmoke),
                ("VALIGN", (0, 0), (-1, -1), "TOP"),
                ("FONTSIZE", (0, 0), (-1, -1), 8),
            ]
        )
    )
    story.extend([summary_table, Spacer(1, 12), Paragraph("Warnings", styles["Heading2"])])
    if warnings:
        for warning in warnings:
            story.append(Paragraph(html.escape(warning), styles["BodyText"]))
    else:
        story.append(Paragraph("None", styles["BodyText"]))
    story.extend(
        [
            Spacer(1, 12),
            Paragraph(
                "Uncertainty distributions were supplied by the user or source document. "
                "The framework did not infer uncertainty distributions automatically.",
                styles["BodyText"],
            ),
        ]
    )
    document = SimpleDocTemplate(path, pagesize=A4)
    document.build(story)
    return True


def _fmt_float(value: Any) -> str:
    if not isinstance(value, (int, float)):
        return "n/a"
    number = float(value)
    if not math.isfinite(number):
        return "n/a"
    if number == 0:
        return "0"
    abs_value = abs(number)
    if abs_value >= 1000 or abs_value < 0.001:
        return f"{number:.3e}"
    return f"{number:.6g}"


def _distribution_report_summary(uncertainty: dict[str, Any]) -> str:
    parts = []
    for key in (
        "minimum",
        "mode",
        "maximum",
        "mean",
        "sd",
        "geomMean",
        "geomSd",
        "lower_bound",
        "upper_bound",
    ):
        if key in uncertainty:
            parts.append(f"{key}={uncertainty[key]}")
    return ", ".join(parts)


def _parameter_report_label(parameter: dict[str, Any]) -> str:
    if parameter["scope"] == "global":
        return parameter["name"]
    context = parameter.get("context") or {}
    process_name = str(context.get("process_name") or "").strip()
    process_id = str(context.get("process_id") or "").strip()
    process_label = process_name or process_id
    return f"{process_label}: {parameter['name']}"


def _parameter_column_label(parameter: dict[str, Any]) -> str:
    if parameter["scope"] == "global":
        return parameter["name"]
    context = parameter.get("context") or {}
    process_name = str(context.get("process_name") or "").strip()
    process_id = str(context.get("process_id") or "").strip()
    label = process_name or process_id
    return f"{label} / {parameter['name']}"


def _required_float(raw: dict[str, Any], key: str) -> float:
    value = _to_float(raw.get(key))
    if value is None:
        raise HTTPException(
            status_code=400,
            detail=f'Uncertainty definition is missing required numeric field "{key}".',
        )
    return value


def _to_float(value: Any) -> float | None:
    if isinstance(value, bool):
        return None
    if isinstance(value, (int, float)):
        number = float(value)
        return number if math.isfinite(number) else None
    if isinstance(value, str):
        text = value.strip()
        if not text:
            return None
        try:
            number = float(text)
        except ValueError:
            return None
        return number if math.isfinite(number) else None
    return None


def _to_int(value: Any) -> int | None:
    if isinstance(value, bool):
        return None
    if isinstance(value, int):
        return value
    if isinstance(value, float):
        return int(value) if math.isfinite(value) else None
    if isinstance(value, str):
        text = value.strip()
        if not text:
            return None
        try:
            return int(text)
        except ValueError:
            return None
    return None


def _normalize_text(value: str) -> str:
    return " ".join(
        "".join(ch.lower() if ch.isalnum() else " " for ch in value).split()
    )


def _extract_unit_like_name(raw: Any) -> str:
    if raw is None:
        return ""
    if isinstance(raw, str):
        return raw.strip()
    return str(getattr(raw, "name", None) or getattr(raw, "id", None) or "").strip()
