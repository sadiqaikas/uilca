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
    from scipy.spatial import QhullError
except Exception as exc:  # pragma: no cover - env dependent
    NonlinearConstraint = None  # type: ignore[assignment]
    shgo = None  # type: ignore[assignment]
    QhullError = RuntimeError  # type: ignore[assignment]
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
    mode: str | None = Field(
        default=None,
        pattern=r"^(parameter_threshold|constrained_optimization|indicator_optimization)$",
    )
    product_system_id: str = Field(..., min_length=1)
    target_type: str = Field(default="product_system", pattern=r"^(product_system|process)$")
    process_id: str | None = None
    variables: list[GoalSeekVariable] = Field(..., min_length=1)
    constraints: list[GoalSeekConstraint] = Field(default_factory=list)
    objective: GoalSeekObjective | None = None
    prompt: str | None = None
    ipc_url: str | None = None
    impact_method_id: str | None = None
    impact_method_name: str | None = None
    n: int = Field(default=256, ge=1, le=512)
    iters: int = Field(default=4, ge=1, le=8)
    sampling_method: str = "sobol"


_GOAL_SEEK_JOBS: dict[str, dict[str, Any]] = {}
_GOAL_SEEK_LOCK = threading.Lock()
_MAX_GOAL_SEEK_EVENTS = 120


def _goal_seek_mode(request: OpenLcaGoalSeekStartRequest) -> str:
    if request.mode:
        return request.mode
    objective = request.objective
    if objective is not None and _is_true_threshold_problem(request, objective):
        return "parameter_threshold"
    return "constrained_optimization"


def _goal_seek_objective(request: OpenLcaGoalSeekStartRequest) -> GoalSeekObjective:
    objective = request.objective
    if objective is None:
        raise RuntimeError("Goal-seek requests must specify an explicit objective.")

    if objective.type == "parameter":
        index = objective.variable_index if objective.variable_index is not None else 0
        if index < 0 or index >= len(request.variables):
            raise RuntimeError(f"Parameter objective variable_index {index} is out of range.")
    elif not (objective.indicator or "").strip() and not (objective.impact_category_id or "").strip():
        raise RuntimeError("Indicator objectives must specify indicator or impact_category_id.")

    return objective


def _validate_goal_seek_request(request: OpenLcaGoalSeekStartRequest) -> None:
    objective = _goal_seek_objective(request)
    if request.target_type == "process" and not (request.process_id or "").strip():
        raise RuntimeError("process_id is required when target_type='process'.")

    if request.mode == "parameter_threshold":
        if not _is_true_threshold_problem(request, objective):
            raise RuntimeError(
                "Parameter-threshold optimization is only valid for a single-variable "
                "parameter minimization with one inequality constraint."
            )
    elif request.mode in {"indicator_optimization", "constrained_optimization"}:
        if objective.type not in {"indicator", "parameter"}:
            raise RuntimeError("Optimization objective must use an indicator or parameter objective.")


def _evaluation_objective_sort_key(evaluation: dict[str, Any]) -> tuple[float, float]:
    objective_value = evaluation.get("objective_value")
    try:
        objective_sort_value = float(objective_value)
    except (TypeError, ValueError):
        objective_sort_value = math.inf
    if not math.isfinite(objective_sort_value):
        objective_sort_value = math.inf

    index = evaluation.get("index")
    try:
        index_sort_value = float(index)
    except (TypeError, ValueError):
        index_sort_value = math.inf
    if not math.isfinite(index_sort_value):
        index_sort_value = math.inf
    return objective_sort_value, index_sort_value


def _is_feasible_evaluation(evaluation: dict[str, Any] | None) -> bool:
    return isinstance(evaluation, dict) and bool(evaluation.get("feasible"))


def _best_feasible_evaluation(
    *evaluations: dict[str, Any] | None,
) -> dict[str, Any] | None:
    candidates = [evaluation for evaluation in evaluations if _is_feasible_evaluation(evaluation)]
    if not candidates:
        return None
    return min(candidates, key=_evaluation_objective_sort_key)


def _goal_seek_request_summary(request: OpenLcaGoalSeekStartRequest) -> dict[str, Any]:
    objective = _goal_seek_objective(request)
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
        "target_type": request.target_type,
        "process_id": (request.process_id or "").strip() or None,
        "impact_method_id": request.impact_method_id,
        "impact_method_name": request.impact_method_name,
        "impact_method_count": len(
            {key for key in method_keys if key != "|"}
        )
        or (1 if request.impact_method_id or request.impact_method_name else 0),
        "mode": _goal_seek_mode(request),
        "objective": objective.model_dump(),
        "variable_count": len(request.variables),
        "constraint_count": len(request.constraints),
        "n": request.n,
        "iters": request.iters,
        "sampling_method": request.sampling_method,
        "prompt": (request.prompt or "").strip(),
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


def _optimizer_stop_reason(*, success: bool, message: str) -> str:
    text = (message or "").strip().lower()
    if success:
        return "normal_completion"
    if "max" in text and ("iter" in text or "eval" in text or "fev" in text):
        return "budget_limit"
    if "early" in text or "stopp" in text:
        return "early_stopping"
    return "solver_terminated_without_convergence_proof"


def _sampling_method_retry_order(preferred: str) -> list[str]:
    normalized = (preferred or "").strip().lower() or "sobol"
    order: list[str] = []
    for candidate in (normalized, "halton", "simplicial"):
        if candidate not in order:
            order.append(candidate)
    return order


def _build_shgo_options(
    request: OpenLcaGoalSeekStartRequest,
) -> dict[str, Any]:
    dimension = max(1, len(request.variables))
    sampling_budget = max(1, int(request.n) * int(request.iters))
    local_iter = min(24, max(8, dimension * 4))
    time_budget_seconds = min(420.0, max(120.0, float(sampling_budget) * 0.75))
    return {
        "maxev": max(
            sampling_budget,
            sampling_budget + local_iter * dimension * 4,
        ),
        "maxtime": time_budget_seconds,
        "minimize_every_iter": False,
        "local_iter": local_iter,
        "infty_constraints": False,
        "disp": False,
    }


def _run_shgo_with_qhull_retry(
    *,
    job_id: str,
    objective_fun: Callable[[Any], float],
    bounds: list[tuple[float, float]],
    constraints: Any,
    minimizer_kwargs: dict[str, Any],
    request: OpenLcaGoalSeekStartRequest,
) -> tuple[Any, str]:
    attempts = _sampling_method_retry_order(request.sampling_method)
    shgo_options = _build_shgo_options(request)
    last_error: Exception | None = None
    for attempt_index, sampling_method in enumerate(attempts, start=1):
        if attempt_index == 1:
            _append_goal_seek_event(
                job_id,
                "optimizer_started",
                "Starting SHGO optimization.",
                details={
                    "method": "scipy.optimize.shgo",
                    "bounds": bounds,
                    "constraint_count": len(request.constraints),
                    "local_minimizer": "SLSQP",
                    "n": request.n,
                    "iters": request.iters,
                    "sampling_method": sampling_method,
                    "options": shgo_options,
                    "attempt": attempt_index,
                },
            )
        else:
            _append_goal_seek_event(
                job_id,
                "optimizer_retry",
                "Retrying SHGO after a Qhull triangulation failure.",
                details={
                    "method": "scipy.optimize.shgo",
                    "n": request.n,
                    "iters": request.iters,
                    "sampling_method": sampling_method,
                    "options": shgo_options,
                    "attempt": attempt_index,
                    "previous_error": str(last_error) if last_error is not None else None,
                },
            )
        try:
            return (
                shgo(
                    objective_fun,
                    bounds,
                    constraints=constraints,
                    minimizer_kwargs=minimizer_kwargs,
                    n=request.n,
                    iters=request.iters,
                    options=shgo_options,
                    sampling_method=sampling_method,
                ),
                sampling_method,
            )
        except QhullError as exc:
            last_error = exc
            _append_goal_seek_event(
                job_id,
                "optimizer_qhull_retry",
                "SHGO sampling failed with a Qhull triangulation error.",
                details={
                    "sampling_method": sampling_method,
                    "attempt": attempt_index,
                    "error": str(exc),
                },
            )
            if attempt_index >= len(attempts):
                raise RuntimeError(
                    "SHGO failed because Qhull could not construct a stable triangulation "
                    "for the sampled points, even after retrying alternative sampling methods."
                ) from exc
    raise RuntimeError("SHGO failed before producing an optimization result.")


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

    objective = _goal_seek_objective(request)
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
    functional_unit = None
    calculation_target = None
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
        if functional_unit is None:
            functional_unit = result.get("functional_unit")
        if calculation_target is None:
            calculation_target = result.get("calculation_target")

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
    if functional_unit is not None:
        payload["functional_unit"] = functional_unit
    if calculation_target is not None:
        payload["calculation_target"] = calculation_target
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
        try:
            _validate_goal_seek_request(request)
        except RuntimeError as exc:
            raise HTTPException(status_code=400, detail=str(exc)) from exc

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
            "solver_initial": None,
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
        next_best = _best_feasible_evaluation(best, evaluation)
        if next_best is not None:
            job["best"] = next_best
        job["updated_at"] = time.time()


def _parameter_objective_index(objective: GoalSeekObjective) -> int:
    return objective.variable_index if objective.variable_index is not None else 0


def _is_true_threshold_problem(
    request: OpenLcaGoalSeekStartRequest,
    objective: GoalSeekObjective | None = None,
) -> bool:
    objective = objective or _goal_seek_objective(request)
    if objective.type != "parameter" or _parameter_objective_index(objective) != 0:
        return False
    if objective.direction != "minimize":
        return False
    if len(request.variables) != 1 or len(request.constraints) != 1:
        return False
    return request.constraints[0].operator in {"<=", ">="}


def _threshold_solver_supported(request: OpenLcaGoalSeekStartRequest) -> bool:
    if _goal_seek_mode(request) != "parameter_threshold":
        return False
    return _is_true_threshold_problem(request)


def _evaluation_primary_x(evaluation: dict[str, Any]) -> float:
    x_raw = evaluation.get("x")
    if isinstance(x_raw, (list, tuple)) and x_raw:
        return float(x_raw[0])
    objective_value = evaluation.get("objective_value")
    return float(objective_value)


def _constraint_signed_violation(constraint_value: dict[str, Any]) -> float:
    value = constraint_value.get("value")
    try:
        numeric_value = float(value)
        target = float(constraint_value.get("target"))
    except (TypeError, ValueError):
        return math.inf

    operator = str(constraint_value.get("operator") or "")
    if operator == "<=":
        return numeric_value - target
    if operator == ">=":
        return target - numeric_value
    return abs(numeric_value - target)


def _threshold_proof_point(evaluation: dict[str, Any] | None) -> dict[str, Any] | None:
    if not isinstance(evaluation, dict):
        return None
    point = _evaluation_summary(evaluation)
    point["x"] = _evaluation_primary_x(evaluation)
    constraints = evaluation.get("constraints")
    if isinstance(constraints, list) and constraints:
        point["constraint_violation"] = _constraint_signed_violation(constraints[0])
    return point


def _threshold_scan_points(lower: float, upper: float, sample_count: int) -> list[float]:
    count = max(2, int(sample_count))
    if count == 2:
        return [lower, upper]
    step = (upper - lower) / float(count - 1)
    return [lower + (step * index) for index in range(count)]


def _validate_parameter_redefinitions_applied(
    result: dict[str, Any],
    *,
    expected_count: int,
) -> None:
    applied = result.get("parameter_redefinitions_applied")
    try:
        applied_count = int(applied)
    except (TypeError, ValueError):
        applied_count = -1
    if applied_count != expected_count:
        raise RuntimeError(
            "openLCA IPC did not apply every requested parameter redefinition: "
            f"expected {expected_count}, applied {applied_count}. "
            "Aborting optimization because the evaluation would be invalid."
        )


def _run_bracketed_threshold_solver(
    *,
    job_id: str,
    request: OpenLcaGoalSeekStartRequest,
    evaluate_vector: Callable[[Any], dict[str, Any]],
    lower: float,
    upper: float,
) -> dict[str, Any]:
    scan_points = min(257, max(9, int(request.n) + 1))
    xs = _threshold_scan_points(lower, upper, scan_points)
    _append_goal_seek_event(
        job_id,
        "threshold_scan_started",
        "Scanning the parameter interval to find the first feasible point.",
        details={
            "method": "parameter_threshold_scan_bisect",
            "scan_points": scan_points,
            "lower": lower,
            "upper": upper,
        },
    )
    scan_evaluations = [evaluate_vector([x]) for x in xs]
    feasibility = [bool(evaluation.get("feasible")) for evaluation in scan_evaluations]
    transition_count = sum(
        1 for left, right in zip(feasibility, feasibility[1:]) if left != right
    )
    first_feasible_index = next(
        (index for index, is_feasible in enumerate(feasibility) if is_feasible),
        None,
    )
    reverted_to_infeasible = (
        first_feasible_index is not None
        and any(not state for state in feasibility[first_feasible_index + 1 :])
    )
    _append_goal_seek_event(
        job_id,
        "threshold_scan_completed",
        "Completed the parameter interval scan.",
        details={
            "method": "parameter_threshold_scan_bisect",
            "scan_points": scan_points,
            "transition_count": transition_count,
            "first_feasible_index": first_feasible_index,
            "lower_point": _threshold_proof_point(scan_evaluations[0]),
            "upper_point": _threshold_proof_point(scan_evaluations[-1]),
        },
    )

    if reverted_to_infeasible:
        raise RuntimeError(
            "Parameter-threshold feasibility changed from satisfied back to violated "
            "across the scan interval. Refusing to report an uncertified threshold."
        )

    if first_feasible_index is None:
        proof = {
            "method": "parameter_threshold_scan_bisect",
            "scan_points": scan_points,
            "transition_count": transition_count,
            "lower_point": _threshold_proof_point(scan_evaluations[0]),
            "upper_point": _threshold_proof_point(scan_evaluations[-1]),
        }
        return {
            "optimizer": {
                "method": "parameter_threshold_scan_bisect",
                "success": False,
                "message": "No feasible point found within the parameter bounds.",
                "scan_points": scan_points,
                "transition_count": transition_count,
                "iterations": 0,
            },
            "best": None,
            "proof_bracket": proof,
            "completion_message": "Optimization completed without a feasible point.",
            "completion_details": {
                "warning": "No feasible evaluated point satisfied all constraints.",
                "proof_bracket": proof,
            },
        }

    if first_feasible_index == 0:
        best = scan_evaluations[0]
        proof = {
            "method": "parameter_threshold_scan_bisect",
            "scan_points": scan_points,
            "transition_count": transition_count,
            "lower_point": _threshold_proof_point(best),
            "upper_point": _threshold_proof_point(best),
            "bracket_width": 0.0,
            "iterations": 0,
        }
        return {
            "optimizer": {
                "method": "parameter_threshold_scan_bisect",
                "success": True,
                "message": "Lower bound is already feasible.",
                "scan_points": scan_points,
                "transition_count": transition_count,
                "iterations": 0,
                "bracket_width": 0.0,
                "threshold_value": _evaluation_primary_x(best),
            },
            "best": best,
            "proof_bracket": proof,
            "completion_message": "Optimization completed.",
            "completion_details": {
                "proof_bracket": proof,
            },
        }

    lower_eval = scan_evaluations[first_feasible_index - 1]
    upper_eval = scan_evaluations[first_feasible_index]
    _append_goal_seek_event(
        job_id,
        "threshold_bracketed",
        "Found an infeasible/feasible bracket around the threshold.",
        details={
            "method": "parameter_threshold_scan_bisect",
            "lower_point": _threshold_proof_point(lower_eval),
            "upper_point": _threshold_proof_point(upper_eval),
            "transition_count": transition_count,
        },
    )

    abs_tol = float(os.environ.get("GOAL_SEEK_THRESHOLD_ABS_TOL", "1e-8"))
    rel_tol = float(os.environ.get("GOAL_SEEK_THRESHOLD_REL_TOL", "1e-10"))
    max_iter = max(1, int(os.environ.get("GOAL_SEEK_THRESHOLD_MAX_ITER", "80")))
    iterations = 0
    while iterations < max_iter:
        lower_x = _evaluation_primary_x(lower_eval)
        upper_x = _evaluation_primary_x(upper_eval)
        bracket_width = upper_x - lower_x
        tolerance = max(abs_tol, rel_tol * max(abs(lower_x), abs(upper_x), 1.0))
        if bracket_width <= tolerance:
            break
        midpoint = (lower_x + upper_x) / 2.0
        if midpoint <= lower_x or midpoint >= upper_x:
            break
        midpoint_eval = evaluate_vector([midpoint])
        if midpoint_eval.get("feasible"):
            upper_eval = midpoint_eval
        else:
            lower_eval = midpoint_eval
        iterations += 1

    if not bool(upper_eval.get("feasible")):
        raise RuntimeError("Internal error: threshold solver finished without a feasible upper bound.")
    if bool(lower_eval.get("feasible")):
        raise RuntimeError("Internal error: threshold solver finished with a feasible lower bound.")

    final_lower_x = _evaluation_primary_x(lower_eval)
    final_upper_x = _evaluation_primary_x(upper_eval)
    proof = {
        "method": "parameter_threshold_scan_bisect",
        "scan_points": scan_points,
        "transition_count": transition_count,
        "iterations": iterations,
        "bracket_width": final_upper_x - final_lower_x,
        "parameter_abs_tolerance": abs_tol,
        "parameter_rel_tolerance": rel_tol,
        "lower_point": _threshold_proof_point(lower_eval),
        "upper_point": _threshold_proof_point(upper_eval),
    }
    _append_goal_seek_event(
        job_id,
        "threshold_refined",
        "Refined the threshold bracket with bisection on real openLCA evaluations.",
        details=proof,
    )
    return {
        "optimizer": {
            "method": "parameter_threshold_scan_bisect",
            "success": True,
            "message": "Bracketed threshold solved with scan plus bisection.",
            "scan_points": scan_points,
            "transition_count": transition_count,
            "iterations": iterations,
            "bracket_width": final_upper_x - final_lower_x,
            "threshold_value": final_upper_x,
        },
        "best": upper_eval,
        "proof_bracket": proof,
        "completion_message": "Optimization completed.",
        "completion_details": {
            "proof_bracket": proof,
        },
    }


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

        calculation_target = deps["resolve_calculation_target"](
            client=client,
            product_system_ref=product_system_ref,
            product_system_entity=product_system_entity,
            target_type=request.target_type,
            process_id=request.process_id,
        )
        parameter_catalog = deps["build_parameter_catalog"](client, product_system_entity)
        impact_method_refs = _collect_goal_seek_method_refs(request, client, deps)
        _append_goal_seek_event(
            job_id,
            "resolved_inputs",
            "Resolved product system, parameter catalog, and LCIA methods.",
            details={
                "product_system_id": request.product_system_id,
                "target_type": request.target_type,
                "process_id": (request.process_id or "").strip() or None,
                "calculation_target": deps["public_calculation_target"](calculation_target),
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

        objective = _goal_seek_objective(request)
        objective_label = _objective_label(objective, request.variables)
        objective_method_id = ""
        objective_method_name = ""
        if objective.type == "indicator":
            objective_method_id, objective_method_name = _goal_seek_indicator_method_hint(
                objective,
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
                    calculation_target=calculation_target,
                ),
            )
                for impact_method_ref in impact_method_refs.values()
            ]
            result = _merge_goal_seek_method_results(
                method_results,
                deps["coerce_float"],
            )
            _validate_parameter_redefinitions_applied(
                result,
                expected_count=len(changes),
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
                "parameter_redefinitions_applied": result.get("parameter_redefinitions_applied"),
                "parameter_names": result.get("parameter_names"),
                "constraints": constraint_values,
                "feasible": feasible,
            }
            cache[cache_key] = evaluation
            _append_goal_seek_evaluation(job_id, evaluation)
            evaluation_details = _evaluation_summary(evaluation)
            evaluation_details["parameter_redefinitions_applied"] = result.get(
                "parameter_redefinitions_applied"
            )
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

        baseline_x: list[float] = []
        has_complete_initial = True
        for index, variable in enumerate(request.variables, start=1):
            if variable.initial is not None and math.isfinite(float(variable.initial)):
                value = float(variable.initial)
                lower = float(variable.lower)
                upper = float(variable.upper)
                if value < lower or value > upper:
                    raise RuntimeError(
                        f"Variable {index} initial value {value} is outside bounds [{lower}, {upper}]."
                    )
                baseline_x.append(value)
            else:
                has_complete_initial = False
                baseline_x.append((float(variable.lower) + float(variable.upper)) / 2.0)
        baseline_x_tuple = tuple(baseline_x)
        if has_complete_initial:
            _append_goal_seek_event(
                job_id,
                "baseline_started",
                "Running baseline evaluation from the provided initial parameter values.",
                details={"x": list(baseline_x_tuple)},
            )
            baseline = evaluate_vector(baseline_x_tuple)
            _update_goal_seek_job(job_id, baseline=baseline, mode=_goal_seek_mode(request))
            _append_goal_seek_event(
                job_id,
                "baseline_completed",
                "Baseline evaluation completed.",
                details=_evaluation_summary(baseline),
            )
        else:
            _append_goal_seek_event(
                job_id,
                "solver_initial_started",
                "Running solver initial-point evaluation from bound midpoints because not all variables provided initial values.",
                details={"x": list(baseline_x_tuple)},
            )
            solver_initial = evaluate_vector(baseline_x_tuple)
            _update_goal_seek_job(
                job_id,
                solver_initial=solver_initial,
                mode=_goal_seek_mode(request),
            )
            _append_goal_seek_event(
                job_id,
                "solver_initial_completed",
                "Solver initial-point evaluation completed.",
                details=_evaluation_summary(solver_initial),
            )

        if _threshold_solver_supported(request):
            threshold_result = _run_bracketed_threshold_solver(
                job_id=job_id,
                request=request,
                evaluate_vector=evaluate_vector,
                lower=bounds[0][0],
                upper=bounds[0][1],
            )
            final_best = threshold_result["best"]
            if final_best is not None and not final_best.get("feasible"):
                raise RuntimeError("Internal error: final goal-seek best point is infeasible.")
            _update_goal_seek_job(
                job_id,
                status="completed",
                completed_at=time.time(),
                optimizer={
                    **threshold_result["optimizer"],
                    "stop_reason": "normal_completion",
                    "recorded_evaluations": len(cache),
                    "feasible_evaluations": len(
                        [item for item in cache.values() if item.get("feasible")]
                    ),
                    "solver_settings": {
                        "n": request.n,
                        "iters": request.iters,
                        "sampling_method": request.sampling_method,
                    },
                },
                best=final_best,
                proof_bracket=threshold_result.get("proof_bracket"),
            )
            completion_details = {
                "optimizer": {
                    **threshold_result["optimizer"],
                    "stop_reason": "normal_completion",
                    "recorded_evaluations": len(cache),
                    "feasible_evaluations": len(
                        [item for item in cache.values() if item.get("feasible")]
                    ),
                    "solver_settings": {
                        "n": request.n,
                        "iters": request.iters,
                        "sampling_method": request.sampling_method,
                    },
                },
            }
            proof_bracket = threshold_result.get("proof_bracket")
            if proof_bracket is not None:
                completion_details["proof_bracket"] = proof_bracket
            if final_best is not None:
                completion_details["best"] = _evaluation_summary(final_best)
            else:
                completion_details["warning"] = "No feasible evaluated point satisfied all constraints."
            _append_goal_seek_event(
                job_id,
                "completed",
                "Best feasible solution found." if final_best is not None else "Optimization completed without a feasible solution.",
                details=completion_details,
            )
            return

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
            "options": {
                "maxiter": max(60, min(200, 25 * len(request.variables))),
                "ftol": 1e-9,
            },
        }

        if _goal_seek_mode(request) == "parameter_threshold":
            _append_goal_seek_event(
                job_id,
                "optimizer_fallback",
                "Falling back to SHGO because this threshold request is not a single-variable inequality problem.",
                details={
                    "method": "scipy.optimize.shgo",
                    "variable_count": len(request.variables),
                    "constraint_count": len(request.constraints),
                },
            )

        result, actual_sampling_method = _run_shgo_with_qhull_retry(
            job_id=job_id,
            objective_fun=objective_fun,
            bounds=bounds,
            constraints=constraints,
            minimizer_kwargs=minimizer_kwargs,
            request=request,
        )

        optimizer_candidate = None
        if getattr(result, "x", None) is not None:
            evaluated_candidate = evaluate_vector(result.x)
            if _is_feasible_evaluation(evaluated_candidate):
                optimizer_candidate = evaluated_candidate
            else:
                _append_goal_seek_event(
                    job_id,
                    "optimizer_candidate_rejected",
                    "SHGO returned an infeasible optimum candidate; keeping the best feasible evaluated point instead.",
                    details=_evaluation_summary(evaluated_candidate),
                )
        elif getattr(result, "success", False):
            raise RuntimeError("SHGO reported success but did not return an optimum point.")

        with _GOAL_SEEK_LOCK:
            stored_best = _GOAL_SEEK_JOBS[job_id].get("best")
        final_best = _best_feasible_evaluation(optimizer_candidate, stored_best)
        if final_best is not None and not final_best.get("feasible"):
            raise RuntimeError("Internal error: final goal-seek best point is infeasible.")

        stop_reason = _optimizer_stop_reason(
            success=bool(getattr(result, "success", False)),
            message=str(getattr(result, "message", "")),
        )
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
                "stop_reason": stop_reason,
                "recorded_evaluations": len(cache),
                "feasible_evaluations": len(
                    [item for item in cache.values() if item.get("feasible")]
                ),
                "solver_settings": {
                    "n": request.n,
                    "iters": request.iters,
                    "sampling_method": actual_sampling_method,
                    "requested_sampling_method": request.sampling_method,
                    "local_minimizer": "SLSQP",
                    "local_minimizer_options": minimizer_kwargs["options"],
                    "global_options": _build_shgo_options(request),
                },
            },
            best=final_best,
        )
        completion_details = {
            "optimizer": {
                "method": "scipy.optimize.shgo",
                "success": bool(getattr(result, "success", False)),
                "message": str(getattr(result, "message", "")),
                "fun": deps["coerce_float"](getattr(result, "fun", None)),
                "nfev": getattr(result, "nfev", None),
                "stop_reason": stop_reason,
                "recorded_evaluations": len(cache),
                "feasible_evaluations": len(
                    [item for item in cache.values() if item.get("feasible")]
                ),
                "solver_settings": {
                    "n": request.n,
                    "iters": request.iters,
                    "sampling_method": actual_sampling_method,
                    "requested_sampling_method": request.sampling_method,
                    "local_minimizer": "SLSQP",
                    "local_minimizer_options": minimizer_kwargs["options"],
                    "global_options": _build_shgo_options(request),
                },
            }
        }
        completion_message = "Best feasible solution found."
        if final_best is not None:
            completion_details["best"] = _evaluation_summary(final_best)
        else:
            completion_message = "Optimization completed without a feasible solution."
            completion_details["warning"] = "No feasible evaluated point satisfied all constraints."
        _append_goal_seek_event(
            job_id,
            "completed",
            completion_message,
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
        index = _parameter_objective_index(objective)
        if index < 0 or index >= len(variables):
            raise RuntimeError(f"Parameter objective variable_index {index} is out of range.")
        direction = "Maximise" if objective.direction == "maximize" else "Minimise"
        return f"{direction} {variables[index].field}"
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
    coerce_float: Callable[[Any], float | None],
) -> float:
    if objective.type == "parameter":
        index = _parameter_objective_index(objective)
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

    def unresolved(reason: str, *, match_strategy: str = "unresolved") -> dict[str, Any]:
        return {
            "matched": False,
            "value": None,
            "match_strategy": match_strategy,
            "reason": reason,
            "requested": {
                "impact_method_id": impact_method_id,
                "impact_method_name": impact_method_name,
                "impact_category_id": impact_category_id,
                "indicator": indicator,
            },
            "available_method_items": available_items(method_items),
            "available_all_items": available_items(all_items),
        }

    method_items = [item for item in items if method_matches(item)]
    all_items = items

    if category_id_needle:
        category_method_items = [
            item
            for item in method_items
            if str(item.get("impact_category_id") or "").strip().lower() == category_id_needle
        ]
        if len(category_method_items) == 1:
            return {
                "matched": True,
                "value": coerce_float(category_method_items[0].get("value")),
                "match_strategy": "impact_category_id+method",
                "matched_item": describe_item(category_method_items[0]),
            }
        if len(category_method_items) > 1:
            return unresolved(
                "Requested impact_category_id matched multiple LCIA results within the selected method.",
                match_strategy="impact_category_id+method_ambiguous",
            )

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
        if len(category_items) > 1:
            return unresolved(
                "Requested impact_category_id matched multiple LCIA results.",
                match_strategy="impact_category_id_ambiguous",
            )
        return unresolved(
            "Requested impact_category_id was not found in the openLCA response.",
            match_strategy="impact_category_id_unresolved",
        )

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
        if len(exact_method_items) == 1:
            return {
                "matched": True,
                "value": coerce_float(exact_method_items[0].get("value")),
                "match_strategy": "indicator+method_exact",
                "matched_item": describe_item(exact_method_items[0]),
            }
        if len(exact_method_items) > 1:
            return unresolved(
                "Requested indicator matched multiple LCIA results within the selected method.",
                match_strategy="indicator+method_exact_ambiguous",
            )
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
        if len(exact_items) > 1:
            return unresolved(
                "Requested indicator matched multiple LCIA results.",
                match_strategy="indicator_without_method_exact_ambiguous",
            )
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
        if len(exact_scores) == 1:
            return {
                "matched": True,
                "value": coerce_float(exact_scores[0]["value"]),
                "match_strategy": "score_label_exact",
                "matched_item": exact_scores[0],
            }
        if len(exact_scores) > 1:
            return unresolved(
                "Requested indicator matched multiple score labels.",
                match_strategy="score_label_exact_ambiguous",
            )
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

    return unresolved("Requested LCIA result was not uniquely matched in the openLCA response.")


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
