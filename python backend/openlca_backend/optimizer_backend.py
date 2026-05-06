"""Goal-seeking optimizer routes for the openLCA IPC backend."""

from __future__ import annotations

import math
import os
import re
import threading
import time
import uuid
from typing import Any, Callable

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field

try:
    from scipy.optimize import NonlinearConstraint, shgo
except Exception as exc:  # pragma: no cover - env dependent
    NonlinearConstraint = None  # type: ignore[assignment]
    shgo = None  # type: ignore[assignment]
    SCIPY_IMPORT_ERROR = str(exc)
else:
    SCIPY_IMPORT_ERROR = None


class GoalSeekVariable(BaseModel):
    field: str = Field(..., min_length=1)
    lower: float
    upper: float
    initial: float | None = None
    process_id: str | None = None


class GoalSeekConstraint(BaseModel):
    indicator: str = Field(..., min_length=1)
    impact_method_id: str | None = None
    impact_method_name: str | None = None
    impact_category_id: str | None = None
    operator: str = Field(..., pattern=r"^(<=|>=|==)$")
    target: float


class GoalSeekObjective(BaseModel):
    type: str = Field(default="indicator", pattern=r"^(indicator|parameter)$")
    indicator: str | None = None
    impact_method_id: str | None = None
    impact_method_name: str | None = None
    impact_category_id: str | None = None
    variable_index: int | None = None
    direction: str = Field(default="minimize", pattern=r"^(minimize|maximize)$")


class OpenLcaGoalSeekStartRequest(BaseModel):
    product_system_id: str = Field(..., min_length=1)
    variables: list[GoalSeekVariable] = Field(..., min_length=1)
    constraints: list[GoalSeekConstraint] = Field(default_factory=list)
    objective: GoalSeekObjective | None = None
    ipc_url: str | None = None
    impact_method_id: str | None = None
    impact_method_name: str | None = None
    n: int = Field(default=32, ge=1, le=512)
    iters: int = Field(default=1, ge=1, le=8)
    sampling_method: str = "simplicial"


_GOAL_SEEK_JOBS: dict[str, dict[str, Any]] = {}
_GOAL_SEEK_LOCK = threading.Lock()
_MAX_GOAL_SEEK_EVENTS = 120


def _goal_seek_request_summary(request: OpenLcaGoalSeekStartRequest) -> dict[str, Any]:
    objective = request.objective or GoalSeekObjective()
    method_keys = {
        f"{(constraint.impact_method_id or request.impact_method_id or '').strip()}|"
        f"{(constraint.impact_method_name or request.impact_method_name or '').strip()}"
        for constraint in request.constraints
    }
    if objective.type == "indicator":
        method_keys.add(
            f"{(objective.impact_method_id or request.impact_method_id or '').strip()}|"
            f"{(objective.impact_method_name or request.impact_method_name or '').strip()}"
        )
    return {
        "product_system_id": request.product_system_id,
        "impact_method_id": request.impact_method_id,
        "impact_method_name": request.impact_method_name,
        "impact_method_count": len(
            {key for key in method_keys if key != "|"}
        )
        or (1 if request.impact_method_id or request.impact_method_name else 0),
        "mode": objective.type,
        "objective": objective.model_dump(),
        "variable_count": len(request.variables),
        "constraint_count": len(request.constraints),
        "n": request.n,
        "iters": request.iters,
        "sampling_method": request.sampling_method,
    }


def _append_goal_seek_event(
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
    with _GOAL_SEEK_LOCK:
        job = _GOAL_SEEK_JOBS[job_id]
        job.setdefault("events", []).append(event)
        if len(job["events"]) > _MAX_GOAL_SEEK_EVENTS:
            job["events"] = job["events"][-_MAX_GOAL_SEEK_EVENTS:]
        job["updated_at"] = time.time()


def _evaluation_summary(evaluation: dict[str, Any]) -> dict[str, Any]:
    return {
        "index": evaluation.get("index"),
        "objective_label": evaluation.get("objective_label"),
        "objective_value": evaluation.get("display_objective_value"),
        "feasible": evaluation.get("feasible"),
        "parameters": evaluation.get("parameters"),
        "constraints": evaluation.get("constraints"),
    }


def _goal_seek_indicator_method_hint(
    item: GoalSeekConstraint | GoalSeekObjective,
    request: OpenLcaGoalSeekStartRequest,
) -> tuple[str, str]:
    method_id = (getattr(item, "impact_method_id", None) or request.impact_method_id or "").strip()
    method_name = (getattr(item, "impact_method_name", None) or request.impact_method_name or "").strip()
    return method_id, method_name


def _resolve_goal_seek_method_ref(
    client: Any,
    deps: dict[str, Any],
    *,
    impact_method_id: str,
    impact_method_name: str,
):
    return deps["pick_impact_method"](
        client,
        impact_method_id=impact_method_id or deps["default_impact_method_id"],
        impact_method_name=impact_method_name or deps["default_impact_method_name"],
    )


def _collect_goal_seek_method_refs(
    request: OpenLcaGoalSeekStartRequest,
    client: Any,
    deps: dict[str, Any],
) -> dict[str, Any]:
    refs_by_id: dict[str, Any] = {}

    def ensure_ref(method_id: str, method_name: str):
        ref = _resolve_goal_seek_method_ref(
            client,
            deps,
            impact_method_id=method_id,
            impact_method_name=method_name,
        )
        if ref is None:
            raise RuntimeError(
                "No impact method available for goal seek."
                if not method_id and not method_name
                else f"Impact method could not be resolved for id='{method_id}' name='{method_name}'."
            )
        ref_id = (getattr(ref, "id", None) or method_id or method_name).strip()
        refs_by_id.setdefault(ref_id, ref)
        return ref

    for constraint in request.constraints:
        method_id, method_name = _goal_seek_indicator_method_hint(constraint, request)
        ensure_ref(method_id, method_name)

    objective = request.objective or GoalSeekObjective()
    if objective.type == "indicator":
        method_id, method_name = _goal_seek_indicator_method_hint(objective, request)
        ensure_ref(method_id, method_name)

    if not refs_by_id:
        ensure_ref(
            (request.impact_method_id or "").strip(),
            (request.impact_method_name or "").strip(),
        )

    return refs_by_id


def _qualified_score_label(method_name: str, indicator: str, index: int) -> str:
    base = indicator.strip() or f"impact_{index}"
    method = method_name.strip()
    if not method:
        return base
    return f"{method} / {base}"


def _normalize_score_text(value: str | None) -> str:
    return re.sub(r"\s+", " ", re.sub(r"[^a-z0-9]+", " ", (value or "").lower())).strip()


def _merge_goal_seek_method_results(
    method_results: list[tuple[Any, dict[str, Any]]],
    coerce_float: Callable[[Any], float | None],
) -> dict[str, Any]:
    combined_scores: dict[str, float] = {}
    combined_score_units: dict[str, str] = {}
    combined_score_items: list[dict[str, Any]] = []
    warnings: list[str] = []
    parameter_redefinitions_applied = None
    parameter_names = None
    functional_units = None
    multi_method = len(method_results) > 1
    label_counts: dict[str, int] = {}

    for ref, result in method_results:
        method_id = (getattr(ref, "id", None) or "").strip()
        method_name = (getattr(ref, "name", None) or method_id).strip()
        if parameter_redefinitions_applied is None:
            parameter_redefinitions_applied = result.get("parameter_redefinitions_applied")
        if parameter_names is None:
            parameter_names = result.get("parameter_names")
        if functional_units is None:
            functional_units = result.get("functional_units")

        for warning in result.get("warnings", []) or []:
            text = str(warning).strip()
            if text:
                warnings.append(f"{method_name or method_id}: {text}" if multi_method else text)

        score_items = result.get("score_items")
        if isinstance(score_items, list) and score_items:
            for index, raw_item in enumerate(score_items, start=1):
                if not isinstance(raw_item, dict):
                    continue
                item = dict(raw_item)
                item["impact_method_id"] = method_id
                if method_name:
                    item["impact_method_name"] = method_name
                combined_score_items.append(item)
                indicator = str(item.get("indicator") or item.get("impact_category_id") or "").strip()
                label = (
                    _qualified_score_label(method_name, indicator, index)
                    if multi_method
                    else (indicator or f"impact_{index}")
                )
                count = label_counts.get(label, 0) + 1
                label_counts[label] = count
                if count > 1:
                    label = f"{label} ({count})"
                value = coerce_float(item.get("value"))
                combined_scores[label] = 0.0 if value is None else float(value)
                unit = str(item.get("unit") or "").strip()
                if unit:
                    combined_score_units[label] = unit
            continue

        raw_scores = result.get("scores")
        if isinstance(raw_scores, dict):
            for index, (raw_label, raw_value) in enumerate(raw_scores.items(), start=1):
                label = str(raw_label).strip() or f"impact_{index}"
                if multi_method:
                    label = _qualified_score_label(method_name, label, index)
                count = label_counts.get(label, 0) + 1
                label_counts[label] = count
                if count > 1:
                    label = f"{label} ({count})"
                value = coerce_float(raw_value)
                combined_scores[label] = 0.0 if value is None else float(value)

    payload: dict[str, Any] = {
        "runner": "openlca_ipc",
        "scores": combined_scores,
    }
    if parameter_redefinitions_applied is not None:
        payload["parameter_redefinitions_applied"] = parameter_redefinitions_applied
    if parameter_names is not None:
        payload["parameter_names"] = parameter_names
    if combined_score_units:
        payload["score_units"] = combined_score_units
    if combined_score_items:
        payload["score_items"] = combined_score_items
    if functional_units is not None:
        payload["functional_units"] = functional_units
    if warnings:
        payload["warnings"] = warnings
    return payload


def register_goal_seek_routes(app: FastAPI, deps: dict[str, Any]) -> None:
    """Register async black-box optimization routes on the main FastAPI app."""

    @app.post("/openlca/goal-seek/start")
    def start_goal_seek(request: OpenLcaGoalSeekStartRequest) -> dict[str, Any]:
        """Start a constrained black-box optimization job over openLCA parameters."""
        deps["ensure_openlca_available"]()
        if SCIPY_IMPORT_ERROR is not None or shgo is None or NonlinearConstraint is None:
            raise HTTPException(
                status_code=500,
                detail=f"SciPy optimization dependencies are unavailable: {SCIPY_IMPORT_ERROR}",
            )

        job_id = str(uuid.uuid4())
        job = {
            "job_id": job_id,
            "status": "queued",
            "created_at": time.time(),
            "updated_at": time.time(),
            "request": request.model_dump(),
            "events": [],
            "evaluations": [],
            "best": None,
            "baseline": None,
            "error": None,
            "cancel_requested": False,
        }
        with _GOAL_SEEK_LOCK:
            _GOAL_SEEK_JOBS[job_id] = job
        _append_goal_seek_event(
            job_id,
            "queued",
            "Optimizer job queued.",
            details=_goal_seek_request_summary(request),
        )

        thread = threading.Thread(
            target=_run_goal_seek_job,
            args=(job_id, request, deps),
            daemon=True,
        )
        thread.start()
        return {"success": True, "job_id": job_id, "status": "queued"}

    @app.get("/openlca/goal-seek/{job_id}")
    def get_goal_seek_job(job_id: str) -> dict[str, Any]:
        with _GOAL_SEEK_LOCK:
            job = _GOAL_SEEK_JOBS.get(job_id)
            if job is None:
                raise HTTPException(status_code=404, detail=f"Goal-seek job '{job_id}' not found.")
            return dict(job)

    @app.post("/openlca/goal-seek/{job_id}/cancel")
    def cancel_goal_seek_job(job_id: str) -> dict[str, Any]:
        with _GOAL_SEEK_LOCK:
            job = _GOAL_SEEK_JOBS.get(job_id)
            if job is None:
                raise HTTPException(status_code=404, detail=f"Goal-seek job '{job_id}' not found.")
            job["cancel_requested"] = True
            job["updated_at"] = time.time()
            current_status = job.get("status")
        _append_goal_seek_event(
            job_id,
            "cancel_requested",
            "Cancellation requested by the client.",
            details={"status": current_status},
        )
        return {"success": True, "job_id": job_id, "status": current_status}


def _update_goal_seek_job(job_id: str, **updates: Any) -> dict[str, Any]:
    with _GOAL_SEEK_LOCK:
        job = _GOAL_SEEK_JOBS[job_id]
        job.update(updates)
        job["updated_at"] = time.time()
        return dict(job)


def _goal_seek_cancelled(job_id: str) -> bool:
    with _GOAL_SEEK_LOCK:
        job = _GOAL_SEEK_JOBS.get(job_id)
        return bool(job and job.get("cancel_requested"))


def _append_goal_seek_evaluation(job_id: str, evaluation: dict[str, Any]) -> None:
    with _GOAL_SEEK_LOCK:
        job = _GOAL_SEEK_JOBS[job_id]
        job["evaluations"].append(evaluation)
        best = job.get("best")
        if evaluation.get("feasible") and (
            best is None or evaluation.get("objective_value", math.inf) < best.get("objective_value", math.inf)
        ):
            job["best"] = evaluation
        job["updated_at"] = time.time()


def _run_goal_seek_job(
    job_id: str,
    request: OpenLcaGoalSeekStartRequest,
    deps: dict[str, Any],
) -> None:
    start = time.time()
    try:
        _update_goal_seek_job(job_id, status="running", started_at=start)
        _append_goal_seek_event(
            job_id,
            "started",
            "Optimizer worker started.",
            details={"started_at": start},
        )
        client = deps["new_ipc_client"](request.ipc_url or deps["default_ipc_url"])
        o = deps["olca_schema"]

        product_system_ref = client.get_descriptor(o.ProductSystem, uid=request.product_system_id)
        if product_system_ref is None:
            raise RuntimeError(f"Product system '{request.product_system_id}' not found.")
        if product_system_ref.ref_type is None:
            product_system_ref.ref_type = o.RefType.ProductSystem

        product_system_entity = client.get(o.ProductSystem, uid=request.product_system_id)
        if product_system_entity is None:
            raise RuntimeError(f"Product system '{request.product_system_id}' could not be loaded.")

        parameter_catalog = deps["build_parameter_catalog"](client, product_system_entity)
        impact_method_refs = _collect_goal_seek_method_refs(request, client, deps)
        _append_goal_seek_event(
            job_id,
            "resolved_inputs",
            "Resolved product system, parameter catalog, and LCIA methods.",
            details={
                "product_system_id": request.product_system_id,
                "product_system_name": getattr(product_system_entity, "name", None),
                "impact_methods": [
                    {
                        "impact_method_id": getattr(ref, "id", None),
                        "impact_method_name": getattr(ref, "name", None),
                    }
                    for ref in impact_method_refs.values()
                ],
                "parameter_count": len(parameter_catalog),
            },
        )

        bounds = [(float(v.lower), float(v.upper)) for v in request.variables]
        for index, (low, high) in enumerate(bounds):
            if not math.isfinite(low) or not math.isfinite(high) or low >= high:
                raise RuntimeError(
                    f"Variable {index + 1} has invalid bounds: lower={low}, upper={high}."
                )

        objective = request.objective or GoalSeekObjective()
        objective_label = _objective_label(objective, request.variables)
        objective_method_id = ""
        objective_method_name = ""
        if objective.type == "indicator":
            objective_method_id, objective_method_name = _goal_seek_indicator_method_hint(
                objective,
                request,
            )
        objective_score_indicator = (
            objective.indicator
            if objective.type == "indicator" and objective.indicator
            else (request.constraints[0].indicator if request.constraints else None)
        )
        objective_score_category_id = (
            objective.impact_category_id
            if objective.type == "indicator" and objective.impact_category_id
            else (
                request.constraints[0].impact_category_id
                if request.constraints and request.constraints[0].impact_category_id
                else None
            )
        )
        fallback_method_id = ""
        fallback_method_name = ""
        if request.constraints:
            fallback_method_id, fallback_method_name = _goal_seek_indicator_method_hint(
                request.constraints[0],
                request,
        )

        cache: dict[tuple[float, ...], dict[str, Any]] = {}
        rejected_probe_cache: set[tuple[float, ...]] = set()

        def evaluate_vector(x_raw: Any) -> dict[str, Any]:
            if _goal_seek_cancelled(job_id):
                raise RuntimeError("Goal-seek job was cancelled.")

            x = tuple(float(v) for v in list(x_raw))
            _validate_vector_within_bounds(
                x,
                bounds,
                context="Internal error: attempted to evaluate openLCA outside variable bounds",
            )
            cache_key = tuple(round(v, 12) for v in x)
            cached = cache.get(cache_key)
            if cached is not None:
                return cached

            evaluation_index = len(cache) + 1
            changes = [
                _goal_seek_variable_to_change(var, value)
                for var, value in zip(request.variables, x)
            ]
            _append_goal_seek_event(
                job_id,
                "evaluation_started",
                f"Starting evaluation {evaluation_index}.",
                details={
                    "index": evaluation_index,
                    "parameters": [
                        {
                            "field": var.field,
                            "process_id": var.process_id,
                            "value": float(value),
                        }
                        for var, value in zip(request.variables, x)
                    ],
                },
            )
            method_results = [
                (
                    impact_method_ref,
                    deps["run_single_scenario"](
                        client=client,
                        scenario_model={"changes": changes},
                        product_system_ref=product_system_ref,
                        impact_method_ref=impact_method_ref,
                        parameter_catalog=parameter_catalog,
                    ),
                )
                for impact_method_ref in impact_method_refs.values()
            ]
            result = _merge_goal_seek_method_results(
                method_results,
                deps["coerce_float"],
            )
            scores = result.get("scores", {})
            score_items = result.get("score_items")
            raw_objective_value = _raw_objective_value(
                objective=objective,
                x=x,
                scores=scores,
                score_items=score_items,
                impact_method_id=objective_method_id,
                impact_method_name=objective_method_name,
                fallback_impact_category_id=objective_score_category_id,
                fallback_indicator=objective_score_indicator,
                fallback_impact_method_id=fallback_method_id,
                fallback_impact_method_name=fallback_method_name,
                coerce_float=deps["coerce_float"],
            )
            if objective.direction == "maximize":
                objective_value = -raw_objective_value
            else:
                objective_value = raw_objective_value

            constraint_values = _goal_seek_constraint_values(
                scores=scores,
                score_items=score_items,
                constraints=request.constraints,
                coerce_float=deps["coerce_float"],
                request=request,
            )
            feasible = all(item["satisfied"] for item in constraint_values)
            evaluation = {
                "index": evaluation_index,
                "mode": objective.type,
                "x": list(x),
                "parameters": [
                    {
                        "field": var.field,
                        "process_id": var.process_id,
                        "value": float(value),
                    }
                    for var, value in zip(request.variables, x)
                ],
                "scores": scores,
                "score_items": score_items,
                "objective_label": objective_label,
                "objective_indicator": objective.indicator if objective.type == "indicator" else None,
                "objective_impact_method_id": objective_method_id if objective.type == "indicator" else None,
                "objective_impact_method_name": objective_method_name if objective.type == "indicator" else None,
                "objective_impact_category_id": objective.impact_category_id
                if objective.type == "indicator"
                else None,
                "objective_value": objective_value,
                "display_objective_value": raw_objective_value,
                "constraints": constraint_values,
                "feasible": feasible,
            }
            cache[cache_key] = evaluation
            _append_goal_seek_evaluation(job_id, evaluation)
            evaluation_details = _evaluation_summary(evaluation)
            warnings = result.get("warnings")
            if warnings:
                evaluation_details["warnings"] = warnings
            _append_goal_seek_event(
                job_id,
                "evaluation_completed",
                f"Completed evaluation {evaluation_index}.",
                details=evaluation_details,
            )
            return evaluation

        def _reject_probe_if_needed(
            x_raw: Any,
            *,
            reason: str,
            constraint_count: int,
        ) -> list[float] | None:
            values = _parse_solver_vector(x_raw)
            if values is None:
                _optimizer_probe_rejected_event(
                    job_id=job_id,
                    x=None,
                    reason=reason,
                    details={
                        "status": "non_numeric",
                        "constraint_count": constraint_count,
                    },
                )
                return _infeasible_constraint_values(request.constraints) if constraint_count else []
            if not _trial_point_within_bounds(values, bounds):
                probe_key = tuple(values)
                if probe_key not in rejected_probe_cache:
                    rejected_probe_cache.add(probe_key)
                    _optimizer_probe_rejected_event(
                        job_id=job_id,
                        x=values,
                        reason=reason,
                        details={
                            "status": "out_of_bounds",
                            "constraint_count": constraint_count,
                        },
                    )
                return _infeasible_constraint_values(request.constraints) if constraint_count else []
            return None

        baseline_x = []
        for index, variable in enumerate(request.variables, start=1):
            if variable.initial is not None and math.isfinite(float(variable.initial)):
                value = float(variable.initial)
                lower = float(variable.lower)
                upper = float(variable.upper)
                if value < lower or value > upper:
                    raise RuntimeError(
                        f"Variable {index} initial value {value} is outside bounds [{lower}, {upper}]."
                    )
            else:
                value = (float(variable.lower) + float(variable.upper)) / 2.0
            baseline_x.append(value)
        baseline_x = tuple(baseline_x)
        _append_goal_seek_event(
            job_id,
            "baseline_started",
            "Running baseline evaluation from initial values or bound midpoints.",
            details={"x": list(baseline_x)},
        )
        baseline = evaluate_vector(baseline_x)
        _update_goal_seek_job(job_id, baseline=baseline, mode=objective.type)
        _append_goal_seek_event(
            job_id,
            "baseline_completed",
            "Baseline evaluation completed.",
            details=_evaluation_summary(baseline),
        )

        def objective_fun(x: Any) -> float:
            rejected = _reject_probe_if_needed(
                x,
                reason="objective",
                constraint_count=len(request.constraints),
            )
            if rejected is not None:
                return _objective_penalty()
            return float(evaluate_vector(x)["objective_value"])

        constraints = ()
        if request.constraints:
            lower, upper = _constraint_bounds(request.constraints)

            def constraint_fun(x: Any) -> list[float]:
                rejected = _reject_probe_if_needed(
                    x,
                    reason="constraint",
                    constraint_count=len(request.constraints),
                )
                if rejected is not None:
                    return rejected
                evaluation = evaluate_vector(x)
                scores = evaluation["scores"]
                score_items = evaluation.get("score_items")
                values = []
                for constraint in request.constraints:
                    constraint_method_id, constraint_method_name = _goal_seek_indicator_method_hint(
                        constraint,
                        request,
                    )
                    resolution = _resolve_score_for_impact(
                        scores=scores,
                        score_items=score_items,
                        impact_method_id=constraint_method_id,
                        impact_method_name=constraint_method_name,
                        impact_category_id=constraint.impact_category_id,
                        indicator=constraint.indicator,
                        coerce_float=deps["coerce_float"],
                    )
                    value = deps["coerce_float"](resolution.get("value"))
                    if not resolution["matched"] or value is None:
                        raise RuntimeError(
                            "Constraint indicator could not be matched in openLCA results: "
                            f"{resolution}"
                        )
                    values.append(math.nan if value is None else float(value))
                return values

            constraints = (NonlinearConstraint(constraint_fun, lower, upper),)

        bounds_tuple = tuple(bounds)
        minimizer_kwargs = {
            "method": "SLSQP",
            "bounds": bounds_tuple,
        }

        _append_goal_seek_event(
            job_id,
            "optimizer_started",
            "Starting SHGO optimization.",
            details={
                "method": "scipy.optimize.shgo",
                "bounds": bounds,
                "impact_method_count": len(impact_method_refs),
                "constraint_count": len(request.constraints),
                "local_minimizer": "SLSQP",
                "n": request.n,
                "iters": request.iters,
                "sampling_method": request.sampling_method,
            },
        )
        result = shgo(
            objective_fun,
            bounds,
            constraints=constraints,
            minimizer_kwargs=minimizer_kwargs,
            n=request.n,
            iters=request.iters,
            sampling_method=request.sampling_method,
        )

        best = None
        if getattr(result, "x", None) is not None:
            best = evaluate_vector(result.x)
        elif getattr(result, "success", False):
            raise RuntimeError("SHGO reported success but did not return an optimum point.")

        _update_goal_seek_job(
            job_id,
            status="completed",
            completed_at=time.time(),
            optimizer={
                "method": "scipy.optimize.shgo",
                "success": bool(getattr(result, "success", False)),
                "message": str(getattr(result, "message", "")),
                "fun": deps["coerce_float"](getattr(result, "fun", None)),
                "nfev": getattr(result, "nfev", None),
            },
            best=best or _GOAL_SEEK_JOBS[job_id].get("best"),
        )
        completion_details = {
            "optimizer": {
                "method": "scipy.optimize.shgo",
                "success": bool(getattr(result, "success", False)),
                "message": str(getattr(result, "message", "")),
                "fun": deps["coerce_float"](getattr(result, "fun", None)),
                "nfev": getattr(result, "nfev", None),
            }
        }
        best_evaluation = best or _GOAL_SEEK_JOBS[job_id].get("best")
        if best_evaluation is not None:
            completion_details["best"] = _evaluation_summary(best_evaluation)
        _append_goal_seek_event(
            job_id,
            "completed",
            "Optimization completed.",
            details=completion_details,
        )
    except Exception as exc:
        status = "cancelled" if _goal_seek_cancelled(job_id) else "failed"
        _update_goal_seek_job(
            job_id,
            status=status,
            completed_at=time.time(),
            error=str(exc),
        )
        _append_goal_seek_event(
            job_id,
            status,
            "Optimization did not finish successfully.",
            details={"error": str(exc)},
        )


def _goal_seek_variable_to_change(var: GoalSeekVariable, value: float) -> dict[str, Any]:
    field = var.field.strip()
    change = {"field": field, "new_value": float(value)}
    if field.startswith("parameters.process."):
        process_id = (var.process_id or "").strip()
        if not process_id:
            raise RuntimeError(f"Process parameter variable '{field}' is missing process_id.")
        change["process_id"] = process_id
    return change


def _objective_label(objective: GoalSeekObjective, variables: list[GoalSeekVariable]) -> str:
    if objective.type == "parameter":
        index = objective.variable_index if objective.variable_index is not None else 0
        if index < 0 or index >= len(variables):
            raise RuntimeError(f"Parameter objective variable_index {index} is out of range.")
        return variables[index].field
    label = objective.indicator or objective.impact_category_id or "impact score"
    method_name = (objective.impact_method_name or objective.impact_method_id or "").strip()
    if method_name and method_name.lower() not in label.lower():
        return f"{method_name} / {label}"
    return label


def _raw_objective_value(
    objective: GoalSeekObjective,
    x: tuple[float, ...],
    scores: dict[str, Any],
    score_items: Any,
    impact_method_id: str | None,
    impact_method_name: str | None,
    fallback_impact_category_id: str | None,
    fallback_indicator: str | None,
    fallback_impact_method_id: str | None,
    fallback_impact_method_name: str | None,
    coerce_float: Callable[[Any], float | None],
) -> float:
    if objective.type == "parameter":
        index = objective.variable_index if objective.variable_index is not None else 0
        if index < 0 or index >= len(x):
            raise RuntimeError(f"Parameter objective variable_index {index} is out of range.")
        return float(x[index])

    objective_resolution = _resolve_score_for_impact(
        scores=scores,
        score_items=score_items,
        impact_method_id=impact_method_id,
        impact_method_name=impact_method_name,
        impact_category_id=objective.impact_category_id,
        indicator=objective.indicator,
        coerce_float=coerce_float,
    )
    if not objective_resolution["matched"]:
        objective_resolution = _resolve_score_for_impact(
            scores=scores,
            score_items=score_items,
            impact_method_id=fallback_impact_method_id,
            impact_method_name=fallback_impact_method_name,
            impact_category_id=fallback_impact_category_id,
            indicator=fallback_indicator,
            coerce_float=coerce_float,
        )
    if not objective_resolution["matched"]:
        raise RuntimeError(
            "Objective indicator could not be matched in openLCA results: "
            f"{objective_resolution}"
        )
    objective_score = coerce_float(objective_resolution.get("value"))
    if objective_score is None:
        raise RuntimeError(
            "Objective indicator matched but returned a non-numeric value: "
            f"{objective_resolution}"
        )
    return float(objective_score)


def _score_for_impact(
    scores: dict[str, Any],
    score_items: Any,
    impact_method_id: str | None,
    impact_method_name: str | None,
    impact_category_id: str | None,
    indicator: str | None,
    coerce_float: Callable[[Any], float | None],
) -> float | None:
    resolution = _resolve_score_for_impact(
        scores=scores,
        score_items=score_items,
        impact_method_id=impact_method_id,
        impact_method_name=impact_method_name,
        impact_category_id=impact_category_id,
        indicator=indicator,
        coerce_float=coerce_float,
    )
    return coerce_float(resolution.get("value")) if resolution["matched"] else None


def _resolve_score_for_impact(
    scores: dict[str, Any],
    score_items: Any,
    impact_method_id: str | None,
    impact_method_name: str | None,
    impact_category_id: str | None,
    indicator: str | None,
    coerce_float: Callable[[Any], float | None],
) -> dict[str, Any]:
    method_id_needle = _normalize_score_text(impact_method_id)
    method_name_needle = _normalize_score_text(impact_method_name)
    category_id_needle = (impact_category_id or "").strip().lower()
    indicator_needle = _normalize_score_text(indicator)

    items = [item for item in score_items if isinstance(item, dict)] if isinstance(score_items, list) else []

    def method_matches(item: dict[str, Any]) -> bool:
        if not method_id_needle and not method_name_needle:
            return True
        item_method_id = _normalize_score_text(str(item.get("impact_method_id") or ""))
        item_method_name = _normalize_score_text(str(item.get("impact_method_name") or ""))
        if method_id_needle and (
            item_method_id == method_id_needle or item_method_name == method_id_needle
        ):
            return True
        if method_name_needle and (
            item_method_name == method_name_needle or item_method_id == method_name_needle
        ):
            return True
        return False

    def describe_item(item: dict[str, Any]) -> dict[str, Any]:
        return {
            "impact_method_id": item.get("impact_method_id"),
            "impact_method_name": item.get("impact_method_name"),
            "impact_category_id": item.get("impact_category_id"),
            "indicator": item.get("indicator"),
            "unit": item.get("unit"),
            "value": item.get("value"),
        }

    def available_items(pool: list[dict[str, Any]]) -> list[dict[str, Any]]:
        return [describe_item(item) for item in pool[:12]]

    method_items = [item for item in items if method_matches(item)]
    all_items = items

    if category_id_needle:
        category_method_items = [
            item
            for item in method_items
            if str(item.get("impact_category_id") or "").strip().lower() == category_id_needle
        ]
        if category_method_items:
            return {
                "matched": True,
                "value": coerce_float(category_method_items[0].get("value")),
                "match_strategy": "impact_category_id+method",
                "matched_item": describe_item(category_method_items[0]),
            }

        category_items = [
            item
            for item in all_items
            if str(item.get("impact_category_id") or "").strip().lower() == category_id_needle
        ]
        if len(category_items) == 1:
            return {
                "matched": True,
                "value": coerce_float(category_items[0].get("value")),
                "match_strategy": "impact_category_id_without_method",
                "matched_item": describe_item(category_items[0]),
            }

    if indicator_needle:
        exact_method_items = []
        partial_method_items = []
        for item in method_items:
            item_name = _normalize_score_text(str(item.get("indicator") or ""))
            if not item_name:
                continue
            if item_name == indicator_needle:
                exact_method_items.append(item)
            elif indicator_needle in item_name or item_name in indicator_needle:
                partial_method_items.append(item)
        if exact_method_items:
            return {
                "matched": True,
                "value": coerce_float(exact_method_items[0].get("value")),
                "match_strategy": "indicator+method_exact",
                "matched_item": describe_item(exact_method_items[0]),
            }
        if len(partial_method_items) == 1:
            return {
                "matched": True,
                "value": coerce_float(partial_method_items[0].get("value")),
                "match_strategy": "indicator+method_partial",
                "matched_item": describe_item(partial_method_items[0]),
            }

        exact_items = []
        partial_items = []
        for item in all_items:
            item_name = _normalize_score_text(str(item.get("indicator") or ""))
            if not item_name:
                continue
            if item_name == indicator_needle:
                exact_items.append(item)
            elif indicator_needle in item_name or item_name in indicator_needle:
                partial_items.append(item)
        if len(exact_items) == 1:
            return {
                "matched": True,
                "value": coerce_float(exact_items[0].get("value")),
                "match_strategy": "indicator_without_method_exact",
                "matched_item": describe_item(exact_items[0]),
            }
        if len(partial_items) == 1:
            return {
                "matched": True,
                "value": coerce_float(partial_items[0].get("value")),
                "match_strategy": "indicator_without_method_partial",
                "matched_item": describe_item(partial_items[0]),
            }

    filtered_score_names = []
    for name, value in scores.items():
        normalized_name = _normalize_score_text(name)
        if method_name_needle and method_name_needle not in normalized_name:
            continue
        if method_id_needle and method_id_needle not in normalized_name:
            continue
        filtered_score_names.append(
            {
                "indicator": name,
                "value": value,
            }
        )

    if indicator_needle:
        exact_scores = [
            item
            for item in filtered_score_names
            if _normalize_score_text(str(item["indicator"])) == indicator_needle
        ]
        if exact_scores:
            return {
                "matched": True,
                "value": coerce_float(exact_scores[0]["value"]),
                "match_strategy": "score_label_exact",
                "matched_item": exact_scores[0],
            }
        partial_scores = [
            item
            for item in filtered_score_names
            if indicator_needle in _normalize_score_text(str(item["indicator"]))
            or _normalize_score_text(str(item["indicator"])) in indicator_needle
        ]
        if len(partial_scores) == 1:
            return {
                "matched": True,
                "value": coerce_float(partial_scores[0]["value"]),
                "match_strategy": "score_label_partial",
                "matched_item": partial_scores[0],
            }

    return {
        "matched": False,
        "value": None,
        "match_strategy": "unresolved",
        "reason": "Requested LCIA result was not uniquely matched in the openLCA response.",
        "requested": {
            "impact_method_id": impact_method_id,
            "impact_method_name": impact_method_name,
            "impact_category_id": impact_category_id,
            "indicator": indicator,
        },
        "available_method_items": available_items(method_items),
        "available_all_items": available_items(all_items),
    }


def _first_score(
    scores: dict[str, Any],
    coerce_float: Callable[[Any], float | None],
) -> float | None:
    for value in scores.values():
        parsed = coerce_float(value)
        if parsed is not None:
            return parsed
    return None


def _goal_seek_constraint_values(
    scores: dict[str, Any],
    score_items: Any,
    constraints: list[GoalSeekConstraint],
    coerce_float: Callable[[Any], float | None],
    request: OpenLcaGoalSeekStartRequest | None = None,
) -> list[dict[str, Any]]:
    rel_tol = float(os.environ.get("GOAL_SEEK_REL_TOL", "1e-9"))
    abs_tol = float(os.environ.get("GOAL_SEEK_ABS_TOL", "1e-12"))

    def _tol(target: float) -> float:
        # Use a combined tolerance so near-zero targets still get a meaningful band.
        return max(abs_tol, rel_tol * abs(float(target)))

    out = []
    for constraint in constraints:
        method_id = (constraint.impact_method_id or "").strip()
        method_name = (constraint.impact_method_name or "").strip()
        if request is not None and not method_id and not method_name:
            method_id, method_name = _goal_seek_indicator_method_hint(
                constraint,
                request,
            )
        resolution = _resolve_score_for_impact(
            scores=scores,
            score_items=score_items,
            impact_method_id=method_id,
            impact_method_name=method_name,
            impact_category_id=constraint.impact_category_id,
            indicator=constraint.indicator,
            coerce_float=coerce_float,
        )
        value = coerce_float(resolution.get("value"))
        if not resolution["matched"]:
            raise RuntimeError(
                "Constraint indicator could not be matched in openLCA results: "
                f"{resolution}"
            )
        if value is None:
            satisfied = False
        elif constraint.operator == "<=":
            satisfied = value <= (constraint.target + _tol(constraint.target))
        elif constraint.operator == ">=":
            satisfied = value >= (constraint.target - _tol(constraint.target))
        else:
            satisfied = math.isclose(
                value,
                constraint.target,
                rel_tol=rel_tol,
                abs_tol=abs_tol,
            )
        out.append(
            {
                "indicator": constraint.indicator,
                "impact_method_id": method_id or None,
                "impact_method_name": method_name or None,
                "impact_category_id": constraint.impact_category_id,
                "operator": constraint.operator,
                "target": constraint.target,
                "value": value,
                "satisfied": satisfied,
                "match_strategy": resolution.get("match_strategy"),
                "matched_item": resolution.get("matched_item"),
            }
        )
    return out


def _constraint_bounds(
    constraints: list[GoalSeekConstraint],
) -> tuple[list[float], list[float]]:
    lower = []
    upper = []
    for constraint in constraints:
        if constraint.operator == "<=":
            lower.append(-math.inf)
            upper.append(float(constraint.target))
        elif constraint.operator == ">=":
            lower.append(float(constraint.target))
            upper.append(math.inf)
        else:
            lower.append(float(constraint.target))
            upper.append(float(constraint.target))
    return lower, upper


def _validate_vector_within_bounds(
    values: tuple[float, ...],
    bounds: list[tuple[float, float]],
    *,
    context: str,
    tolerance: float = 1e-10,
) -> None:
    for index, (value, (lower, upper)) in enumerate(zip(values, bounds), start=1):
        if not math.isfinite(value):
            raise RuntimeError(f"{context}: variable {index} is non-finite: {value}.")
        if value < lower - tolerance or value > upper + tolerance:
            raise RuntimeError(
                f"{context}: variable {index}={value} is outside bounds [{lower}, {upper}]."
            )


def _parse_solver_vector(x_raw: Any) -> tuple[float, ...] | None:
    try:
        return tuple(float(v) for v in list(x_raw))
    except Exception:
        return None


def _trial_point_within_bounds(
    values: tuple[float, ...],
    bounds: list[tuple[float, float]],
) -> bool:
    if len(values) != len(bounds):
        return False
    for value, (lower, upper) in zip(values, bounds):
        if not math.isfinite(value) or value < lower or value > upper:
            return False
    return True


def _objective_penalty() -> float:
    return 1e30


def _infeasible_constraint_values(
    constraints: list[GoalSeekConstraint],
) -> list[float]:
    values: list[float] = []
    for constraint in constraints:
        target = float(constraint.target)
        margin = max(1.0, abs(target) * 0.1)
        if constraint.operator == "<=":
            values.append(target + margin)
        elif constraint.operator == ">=":
            values.append(target - margin)
        else:
            values.append(target + margin)
    return values


def _optimizer_probe_rejected_event(
    *,
    job_id: str,
    x: tuple[float, ...] | None,
    reason: str,
    details: dict[str, Any],
) -> None:
    payload = dict(details)
    payload["reason"] = reason
    if x is not None:
        payload["x"] = list(x)
    _append_goal_seek_event(
        job_id,
        "optimizer_probe_rejected",
        "Optimizer attempted an out-of-bounds trial point; skipped openLCA evaluation and returned a penalty.",
        details=payload,
    )
