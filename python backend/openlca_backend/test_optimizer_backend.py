from __future__ import annotations

import importlib.util
import pathlib
import sys
import unittest
from types import SimpleNamespace


MODULE_PATH = pathlib.Path(__file__).with_name("optimizer_backend.py")
SPEC = importlib.util.spec_from_file_location("optimizer_backend_under_test", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
optimizer_backend = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = optimizer_backend
SPEC.loader.exec_module(optimizer_backend)


def _coerce_float(value):
    if value is None:
        return None
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


class GoalSeekOptimizerBackendTests(unittest.TestCase):
    def setUp(self) -> None:
        optimizer_backend._GOAL_SEEK_JOBS.clear()

    def _make_threshold_request(self) -> object:
        return optimizer_backend.OpenLcaGoalSeekStartRequest(
            mode="parameter_threshold",
            product_system_id="ps-1",
            variables=[
                optimizer_backend.GoalSeekVariable(
                    field="parameters.global.capture_rate_frxn",
                    lower=0.8,
                    upper=0.99,
                )
            ],
            constraints=[
                optimizer_backend.GoalSeekConstraint(
                    indicator="Climate Change",
                    impact_method_id="method-1",
                    impact_category_id="climate-change",
                    operator="<=",
                    target=0.0,
                )
            ],
            objective=optimizer_backend.GoalSeekObjective(
                type="parameter",
                variable_index=0,
                direction="minimize",
            ),
            n=16,
        )

    def test_best_feasible_evaluation_ignores_infeasible_optimizer_candidate(self) -> None:
        feasible = {
            "index": 3,
            "objective_value": 0.89,
            "display_objective_value": 0.89,
            "feasible": True,
        }
        infeasible = {
            "index": 4,
            "objective_value": 0.869406,
            "display_objective_value": 0.869406,
            "feasible": False,
        }

        best = optimizer_backend._best_feasible_evaluation(infeasible, feasible)

        self.assertIs(best, feasible)

    def test_append_goal_seek_evaluation_keeps_best_feasible_point(self) -> None:
        job_id = "job-1"
        optimizer_backend._GOAL_SEEK_JOBS[job_id] = {
            "job_id": job_id,
            "evaluations": [],
            "events": [],
            "best": None,
            "updated_at": 0.0,
        }
        feasible = {
            "index": 1,
            "objective_value": 0.89,
            "display_objective_value": 0.89,
            "feasible": True,
        }
        infeasible = {
            "index": 2,
            "objective_value": 0.869406,
            "display_objective_value": 0.869406,
            "feasible": False,
        }

        optimizer_backend._append_goal_seek_evaluation(job_id, feasible)
        optimizer_backend._append_goal_seek_evaluation(job_id, infeasible)

        self.assertEqual(len(optimizer_backend._GOAL_SEEK_JOBS[job_id]["evaluations"]), 2)
        self.assertIs(optimizer_backend._GOAL_SEEK_JOBS[job_id]["best"], feasible)

    def test_parameter_threshold_mode_rejects_indicator_objective(self) -> None:
        request = self._make_threshold_request()
        request.objective = optimizer_backend.GoalSeekObjective(
            type="indicator",
            indicator="Climate Change",
            impact_method_id="method-1",
            impact_category_id="category-1",
            direction="minimize",
        )

        with self.assertRaisesRegex(RuntimeError, "single-variable parameter minimization"):
            optimizer_backend._validate_goal_seek_request(request)

    def test_parameter_threshold_mode_rejects_maximize_direction(self) -> None:
        request = self._make_threshold_request()
        request.objective = optimizer_backend.GoalSeekObjective(
            type="parameter",
            variable_index=0,
            direction="maximize",
        )

        with self.assertRaisesRegex(RuntimeError, "single-variable parameter minimization"):
            optimizer_backend._validate_goal_seek_request(request)

    def test_indicator_objective_requires_explicit_identifier(self) -> None:
        request = optimizer_backend.OpenLcaGoalSeekStartRequest(
            mode="indicator_optimization",
            product_system_id="ps-1",
            variables=[
                optimizer_backend.GoalSeekVariable(
                    field="parameters.global.capture_rate_frxn",
                    lower=0.8,
                    upper=0.99,
                )
            ],
            objective=optimizer_backend.GoalSeekObjective(
                type="indicator",
                direction="minimize",
            ),
        )

        with self.assertRaisesRegex(RuntimeError, "must specify indicator or impact_category_id"):
            optimizer_backend._validate_goal_seek_request(request)

    def test_indicator_optimization_mode_allows_parameter_maximize_objective(self) -> None:
        request = optimizer_backend.OpenLcaGoalSeekStartRequest(
            mode="indicator_optimization",
            product_system_id="ps-1",
            variables=[
                optimizer_backend.GoalSeekVariable(
                    field="parameters.global.capture_rate_frxn",
                    lower=0.8,
                    upper=0.99,
                )
            ],
            objective=optimizer_backend.GoalSeekObjective(
                type="parameter",
                variable_index=0,
                direction="maximize",
            ),
        )

        optimizer_backend._validate_goal_seek_request(request)

    def test_goal_seek_mode_defaults_to_constrained_for_parameter_maximize(self) -> None:
        request = optimizer_backend.OpenLcaGoalSeekStartRequest(
            product_system_id="ps-1",
            variables=[
                optimizer_backend.GoalSeekVariable(
                    field="parameters.global.Bio_Transport_Truck_mi",
                    lower=25.0,
                    upper=1000.0,
                ),
                optimizer_backend.GoalSeekVariable(
                    field="parameters.global.capture_rate_frxn",
                    lower=0.8,
                    upper=0.95,
                ),
            ],
            constraints=[
                optimizer_backend.GoalSeekConstraint(
                    indicator="Climate Change",
                    impact_method_id="method-1",
                    impact_category_id="climate-change",
                    operator="<=",
                    target=-0.05,
                )
            ],
            objective=optimizer_backend.GoalSeekObjective(
                type="parameter",
                variable_index=0,
                direction="maximize",
            ),
        )

        self.assertEqual(
            optimizer_backend._goal_seek_mode(request),
            "constrained_optimization",
        )

    def test_goal_seek_request_summary_includes_prompt(self) -> None:
        request = self._make_threshold_request()
        request.prompt = "Find the minimum capture rate that keeps the system carbon-negative."

        summary = optimizer_backend._goal_seek_request_summary(request)

        self.assertEqual(
            summary["prompt"],
            "Find the minimum capture rate that keeps the system carbon-negative.",
        )

    def test_parameter_threshold_default_solver_budget_is_small(self) -> None:
        request = self._make_threshold_request()
        request.n = 256
        request.iters = 4

        self.assertEqual(
            optimizer_backend._goal_seek_solver_settings(request),
            (32, 1),
        )
        summary = optimizer_backend._goal_seek_request_summary(request)
        self.assertEqual(summary["n"], 32)
        self.assertEqual(summary["iters"], 1)

    def test_parameter_threshold_ignores_explicit_solver_budget(self) -> None:
        request = self._make_threshold_request()
        request.n = 100
        request.iters = 8

        self.assertEqual(
            optimizer_backend._goal_seek_solver_settings(request),
            (32, 1),
        )
        summary = optimizer_backend._goal_seek_request_summary(request)
        self.assertEqual(summary["n"], 32)
        self.assertEqual(summary["iters"], 1)

    def test_constrained_optimization_uses_backend_owned_shgo_budget(self) -> None:
        request = optimizer_backend.OpenLcaGoalSeekStartRequest(
            product_system_id="ps-1",
            variables=[
                optimizer_backend.GoalSeekVariable(field="a", lower=0.0, upper=1.0),
                optimizer_backend.GoalSeekVariable(field="b", lower=0.0, upper=1.0),
            ],
            constraints=[
                optimizer_backend.GoalSeekConstraint(
                    indicator="Climate Change",
                    impact_method_id="method-1",
                    impact_category_id="category-1",
                    operator="<=",
                    target=0.0,
                )
            ],
            objective=optimizer_backend.GoalSeekObjective(
                type="indicator",
                indicator="Climate Change",
                impact_method_id="method-1",
                impact_category_id="category-1",
                direction="minimize",
            ),
            n=64,
            iters=8,
            sampling_method="simplicial",
        )

        self.assertEqual(
            optimizer_backend._goal_seek_solver_settings(request),
            (256, 4),
        )
        self.assertEqual(
            optimizer_backend._goal_seek_sampling_method(request),
            "sobol",
        )
        summary = optimizer_backend._goal_seek_request_summary(request)
        self.assertEqual(summary["n"], 256)
        self.assertEqual(summary["iters"], 4)
        self.assertEqual(summary["sampling_method"], "sobol")

    def test_prune_goal_seek_jobs_removes_old_inactive_jobs_only(self) -> None:
        now = 10000.0
        optimizer_backend._GOAL_SEEK_JOBS.update(
            {
                "old-completed": {
                    "job_id": "old-completed",
                    "status": "completed",
                    "updated_at": now - optimizer_backend._GOAL_SEEK_JOB_TTL_SECONDS - 1,
                },
                "old-running": {
                    "job_id": "old-running",
                    "status": "running",
                    "updated_at": now - optimizer_backend._GOAL_SEEK_JOB_TTL_SECONDS - 1,
                },
                "recent-completed": {
                    "job_id": "recent-completed",
                    "status": "completed",
                    "updated_at": now,
                },
            }
        )

        optimizer_backend._prune_goal_seek_jobs(now)

        self.assertNotIn("old-completed", optimizer_backend._GOAL_SEEK_JOBS)
        self.assertIn("old-running", optimizer_backend._GOAL_SEEK_JOBS)
        self.assertIn("recent-completed", optimizer_backend._GOAL_SEEK_JOBS)

    def test_build_shgo_options_sets_explicit_termination_controls(self) -> None:
        request = optimizer_backend.OpenLcaGoalSeekStartRequest(
            product_system_id="ps-1",
            variables=[
                optimizer_backend.GoalSeekVariable(field="a", lower=0.0, upper=1.0),
                optimizer_backend.GoalSeekVariable(field="b", lower=0.0, upper=1.0),
                optimizer_backend.GoalSeekVariable(field="c", lower=0.0, upper=1.0),
                optimizer_backend.GoalSeekVariable(field="d", lower=0.0, upper=1.0),
            ],
            objective=optimizer_backend.GoalSeekObjective(
                type="parameter",
                variable_index=0,
                direction="maximize",
            ),
            n=256,
            iters=4,
            sampling_method="sobol",
        )

        options = optimizer_backend._build_shgo_options(request)

        self.assertNotIn("maxiter", options)
        self.assertEqual(options["maxev"], 1280)
        self.assertFalse(options["minimize_every_iter"])
        self.assertEqual(options["local_iter"], 16)
        self.assertFalse(options["infty_constraints"])
        self.assertGreaterEqual(options["maxtime"], 120.0)

    def test_shgo_qhull_error_retries_with_alternative_sampling_method(self) -> None:
        request = optimizer_backend.OpenLcaGoalSeekStartRequest(
            product_system_id="ps-1",
            variables=[
                optimizer_backend.GoalSeekVariable(
                    field="parameters.global.Bio_Transport_Truck_mi",
                    lower=25.0,
                    upper=1000.0,
                ),
                optimizer_backend.GoalSeekVariable(
                    field="parameters.global.capture_rate_frxn",
                    lower=0.8,
                    upper=0.95,
                ),
            ],
            objective=optimizer_backend.GoalSeekObjective(
                type="parameter",
                variable_index=0,
                direction="maximize",
            ),
            sampling_method="sobol",
            n=256,
            iters=4,
        )
        job_id = "job-qhull-retry"
        optimizer_backend._GOAL_SEEK_JOBS[job_id] = {
            "job_id": job_id,
            "events": [],
            "updated_at": 0.0,
        }

        calls: list[str] = []
        original_shgo = optimizer_backend.shgo

        def fake_shgo(*args, **kwargs):
            sampling_method = kwargs["sampling_method"]
            calls.append(sampling_method)
            self.assertIn("options", kwargs)
            self.assertNotIn("maxiter", kwargs["options"])
            self.assertEqual(kwargs["options"]["maxev"], 1088)
            if sampling_method == "sobol":
                raise optimizer_backend.QhullError("QH6361 simulated topology failure")
            return SimpleNamespace(
                x=[100.0, 0.9],
                success=True,
                message="Optimization terminated successfully.",
                fun=-100.0,
                nfev=42,
            )

        optimizer_backend.shgo = fake_shgo
        try:
            result, actual_sampling_method = optimizer_backend._run_shgo_with_qhull_retry(
                job_id=job_id,
                objective_fun=lambda x: float(x[0]),
                bounds=[(25.0, 1000.0), (0.8, 0.95)],
                constraints=(),
                minimizer_kwargs={"method": "SLSQP", "bounds": ((25.0, 1000.0), (0.8, 0.95))},
                request=request,
            )
        finally:
            optimizer_backend.shgo = original_shgo

        self.assertEqual(calls, ["sobol", "halton"])
        self.assertEqual(actual_sampling_method, "halton")
        self.assertTrue(result.success)
        stages = [event["stage"] for event in optimizer_backend._GOAL_SEEK_JOBS[job_id]["events"]]
        self.assertIn("optimizer_qhull_retry", stages)
        self.assertIn("optimizer_retry", stages)

    def test_goal_seek_job_passes_old_style_constraints_to_shgo(self) -> None:
        request = optimizer_backend.OpenLcaGoalSeekStartRequest(
            product_system_id="ps-1",
            variables=[
                optimizer_backend.GoalSeekVariable(
                    field="parameters.global.transport",
                    lower=0.0,
                    upper=100.0,
                    initial=10.0,
                )
            ],
            constraints=[
                optimizer_backend.GoalSeekConstraint(
                    indicator="Climate Change",
                    impact_method_id="method-1",
                    impact_category_id="climate-change",
                    operator="<=",
                    target=0.0,
                )
            ],
            objective=optimizer_backend.GoalSeekObjective(
                type="parameter",
                variable_index=0,
                direction="maximize",
            ),
        )
        job_id = "job-old-style-constraints"
        optimizer_backend._GOAL_SEEK_JOBS[job_id] = {
            "job_id": job_id,
            "status": "queued",
            "events": [],
            "evaluations": [],
            "best": None,
            "updated_at": 0.0,
            "cancel_requested": False,
        }

        class Ref:
            id = "ps-1"
            name = "Product system"
            ref_type = None

        class Schema:
            ProductSystem = object

            class RefType:
                ProductSystem = "ProductSystem"

        def run_single_scenario(**kwargs):
            changes = kwargs["scenario_model"]["changes"]
            x = float(changes[0]["new_value"])
            return {
                "scores": {"Climate Change": x - 100.0},
                "score_items": [
                    {
                        "impact_method_id": "method-1",
                        "impact_method_name": "Method 1",
                        "impact_category_id": "climate-change",
                        "indicator": "Climate Change",
                        "value": x - 100.0,
                    }
                ],
                "parameter_redefinitions_applied": len(changes),
                "parameter_names": ["transport"],
            }

        def fake_shgo(func, bounds, **kwargs):
            constraints = kwargs["constraints"]
            self.assertIn("constraints", kwargs["minimizer_kwargs"])
            self.assertIsInstance(constraints, tuple)
            self.assertEqual(len(constraints), 1)
            self.assertIsInstance(constraints[0], dict)
            self.assertEqual(constraints[0]["type"], "ineq")
            residuals = constraints[0]["fun"]([25.0])
            self.assertEqual(len(residuals), 1)
            self.assertGreaterEqual(residuals[0], 0.0)
            fun = func([50.0])
            return SimpleNamespace(
                x=[50.0],
                success=True,
                message="Optimization terminated successfully.",
                fun=fun,
                nfev=2,
            )

        original_shgo = optimizer_backend.shgo
        original_minimize = optimizer_backend.minimize
        optimizer_backend.shgo = fake_shgo
        optimizer_backend.minimize = lambda fun, x0, **kwargs: SimpleNamespace(
            x=x0,
            success=True,
            message="local polish no-op",
            fun=fun(x0),
            nfev=1,
        )
        try:
            optimizer_backend._run_goal_seek_job(
                job_id,
                request,
                {
                    "new_ipc_client": lambda url: SimpleNamespace(
                        get_descriptor=lambda *args, **kwargs: Ref(),
                        get=lambda *args, **kwargs: Ref(),
                    ),
                    "olca_schema": Schema,
                    "resolve_calculation_target": lambda **kwargs: {},
                    "build_parameter_catalog": lambda client, product_system: {},
                    "pick_impact_method": lambda *args, **kwargs: SimpleNamespace(
                        id="method-1",
                        name="Method 1",
                    ),
                    "public_calculation_target": lambda target: {},
                    "run_single_scenario": run_single_scenario,
                    "coerce_float": _coerce_float,
                    "default_ipc_url": "ipc://test",
                    "default_impact_method_id": "method-1",
                    "default_impact_method_name": "Method 1",
                },
            )
        finally:
            optimizer_backend.shgo = original_shgo
            optimizer_backend.minimize = original_minimize

        job = optimizer_backend._GOAL_SEEK_JOBS[job_id]
        self.assertEqual(job["status"], "completed")
        self.assertEqual(job["best"]["x"], [50.0])

    def test_goal_seek_job_runs_explicit_local_polish_when_shgo_stops_after_sampling(self) -> None:
        request = optimizer_backend.OpenLcaGoalSeekStartRequest(
            mode="constrained_optimization",
            product_system_id="ps-1",
            variables=[
                optimizer_backend.GoalSeekVariable(
                    field="parameters.global.transport",
                    lower=0.0,
                    upper=100.0,
                    initial=10.0,
                ),
                optimizer_backend.GoalSeekVariable(
                    field="parameters.global.capture",
                    lower=0.0,
                    upper=1.0,
                    initial=0.5,
                ),
            ],
            constraints=[
                optimizer_backend.GoalSeekConstraint(
                    indicator="Climate Change",
                    impact_method_id="method-1",
                    impact_category_id="climate-change",
                    operator="<=",
                    target=0.0,
                )
            ],
            objective=optimizer_backend.GoalSeekObjective(
                type="parameter",
                variable_index=0,
                direction="maximize",
            ),
        )
        job_id = "job-local-polish"
        optimizer_backend._GOAL_SEEK_JOBS[job_id] = {
            "job_id": job_id,
            "status": "queued",
            "events": [],
            "evaluations": [],
            "best": None,
            "updated_at": 0.0,
            "cancel_requested": False,
        }

        class Ref:
            id = "ps-1"
            name = "Product system"
            ref_type = None

        class Schema:
            ProductSystem = object

            class RefType:
                ProductSystem = "ProductSystem"

        def run_single_scenario(**kwargs):
            changes = kwargs["scenario_model"]["changes"]
            x = float(changes[0]["new_value"])
            return {
                "scores": {"Climate Change": x - 100.0},
                "score_items": [
                    {
                        "impact_method_id": "method-1",
                        "impact_method_name": "Method 1",
                        "impact_category_id": "climate-change",
                        "indicator": "Climate Change",
                        "value": x - 100.0,
                    }
                ],
                "parameter_redefinitions_applied": len(changes),
                "parameter_names": ["transport", "capture"],
            }

        def fake_shgo(*args, **kwargs):
            return SimpleNamespace(
                x=None,
                success=False,
                message="Failed to find a feasible minimizer point.",
                fun=None,
                nfev=0,
            )

        def fake_minimize(fun, x0, **kwargs):
            x = [80.0, 0.5]
            return SimpleNamespace(
                x=x,
                success=True,
                message="local polish converged",
                fun=fun(x),
                nfev=2,
            )

        original_shgo = optimizer_backend.shgo
        original_minimize = optimizer_backend.minimize
        optimizer_backend.shgo = fake_shgo
        optimizer_backend.minimize = fake_minimize
        try:
            optimizer_backend._run_goal_seek_job(
                job_id,
                request,
                {
                    "new_ipc_client": lambda url: SimpleNamespace(
                        get_descriptor=lambda *args, **kwargs: Ref(),
                        get=lambda *args, **kwargs: Ref(),
                    ),
                    "olca_schema": Schema,
                    "resolve_calculation_target": lambda **kwargs: {},
                    "build_parameter_catalog": lambda client, product_system: {},
                    "pick_impact_method": lambda *args, **kwargs: SimpleNamespace(
                        id="method-1",
                        name="Method 1",
                    ),
                    "public_calculation_target": lambda target: {},
                    "run_single_scenario": run_single_scenario,
                    "coerce_float": _coerce_float,
                    "default_ipc_url": "ipc://test",
                    "default_impact_method_id": "method-1",
                    "default_impact_method_name": "Method 1",
                },
            )
        finally:
            optimizer_backend.shgo = original_shgo
            optimizer_backend.minimize = original_minimize

        job = optimizer_backend._GOAL_SEEK_JOBS[job_id]
        self.assertEqual(job["status"], "completed")
        self.assertEqual(job["best"]["x"], [80.0, 0.5])
        self.assertTrue(job["optimizer"]["success"])
        self.assertEqual(job["optimizer"]["stop_reason"], "normal_completion")
        self.assertGreater(job["optimizer"]["local_polish"]["attempted_starts"], 0)

    def test_goal_seek_job_caps_explicit_local_polish_total_evaluations(self) -> None:
        request = optimizer_backend.OpenLcaGoalSeekStartRequest(
            mode="constrained_optimization",
            product_system_id="ps-1",
            variables=[
                optimizer_backend.GoalSeekVariable(
                    field="parameters.global.transport",
                    lower=0.0,
                    upper=1000.0,
                    initial=10.0,
                ),
                optimizer_backend.GoalSeekVariable(
                    field="parameters.global.capture",
                    lower=0.0,
                    upper=1.0,
                    initial=0.5,
                ),
            ],
            constraints=[
                optimizer_backend.GoalSeekConstraint(
                    indicator="Climate Change",
                    impact_method_id="method-1",
                    impact_category_id="climate-change",
                    operator="<=",
                    target=0.0,
                )
            ],
            objective=optimizer_backend.GoalSeekObjective(
                type="parameter",
                variable_index=0,
                direction="maximize",
            ),
        )
        job_id = "job-local-polish-cap"
        optimizer_backend._GOAL_SEEK_JOBS[job_id] = {
            "job_id": job_id,
            "status": "queued",
            "events": [],
            "evaluations": [],
            "best": None,
            "updated_at": 0.0,
            "cancel_requested": False,
        }

        class Ref:
            id = "ps-1"
            name = "Product system"
            ref_type = None

        class Schema:
            ProductSystem = object

            class RefType:
                ProductSystem = "ProductSystem"

        def run_single_scenario(**kwargs):
            changes = kwargs["scenario_model"]["changes"]
            x = float(changes[0]["new_value"])
            return {
                "scores": {"Climate Change": x - 1000.0},
                "score_items": [
                    {
                        "impact_method_id": "method-1",
                        "impact_method_name": "Method 1",
                        "impact_category_id": "climate-change",
                        "indicator": "Climate Change",
                        "value": x - 1000.0,
                    }
                ],
                "parameter_redefinitions_applied": len(changes),
                "parameter_names": ["transport", "capture"],
            }

        def fake_shgo(*args, **kwargs):
            return SimpleNamespace(
                x=None,
                success=False,
                message="Failed to find a feasible minimizer point.",
                fun=None,
                nfev=0,
            )

        def fake_minimize(fun, x0, **kwargs):
            for offset in range(1000):
                try:
                    fun([float(offset), 0.5])
                except RuntimeError:
                    break
            return SimpleNamespace(
                x=x0,
                success=False,
                message="hit evaluation cap",
                fun=None,
                nfev=1000,
            )

        original_shgo = optimizer_backend.shgo
        original_minimize = optimizer_backend.minimize
        optimizer_backend.shgo = fake_shgo
        optimizer_backend.minimize = fake_minimize
        try:
            optimizer_backend._run_goal_seek_job(
                job_id,
                request,
                {
                    "new_ipc_client": lambda url: SimpleNamespace(
                        get_descriptor=lambda *args, **kwargs: Ref(),
                        get=lambda *args, **kwargs: Ref(),
                    ),
                    "olca_schema": Schema,
                    "resolve_calculation_target": lambda **kwargs: {},
                    "build_parameter_catalog": lambda client, product_system: {},
                    "pick_impact_method": lambda *args, **kwargs: SimpleNamespace(
                        id="method-1",
                        name="Method 1",
                    ),
                    "public_calculation_target": lambda target: {},
                    "run_single_scenario": run_single_scenario,
                    "coerce_float": _coerce_float,
                    "default_ipc_url": "ipc://test",
                    "default_impact_method_id": "method-1",
                    "default_impact_method_name": "Method 1",
                },
            )
        finally:
            optimizer_backend.shgo = original_shgo
            optimizer_backend.minimize = original_minimize

        job = optimizer_backend._GOAL_SEEK_JOBS[job_id]
        self.assertEqual(
            job["optimizer"]["recorded_evaluations"],
            optimizer_backend._DEFAULT_GOAL_SEEK_TOTAL_EVALUATION_LIMIT,
        )
        self.assertNotIn(
            "total_evaluation_limit",
            job["optimizer"]["solver_settings"],
        )
        self.assertNotIn("limit_reached", job["optimizer"]["local_polish"])

    def test_impact_category_id_does_not_fall_back_to_partial_indicator_match(self) -> None:
        resolution = optimizer_backend._resolve_score_for_impact(
            scores={},
            score_items=[
                {
                    "impact_method_id": "method-1",
                    "impact_method_name": "Method 1",
                    "impact_category_id": "climate-change",
                    "indicator": "Climate Change",
                    "unit": "kg CO2 eq",
                    "value": -0.00327873,
                },
                {
                    "impact_method_id": "method-1",
                    "impact_method_name": "Method 1",
                    "impact_category_id": "other-category",
                    "indicator": "Climate",
                    "unit": "kg CO2 eq",
                    "value": 10.0,
                },
            ],
            impact_method_id="method-1",
            impact_method_name="Method 1",
            impact_category_id="missing-category",
            indicator="Climate",
            coerce_float=_coerce_float,
        )

        self.assertFalse(resolution["matched"])
        self.assertEqual(resolution["match_strategy"], "impact_category_id_unresolved")

    def test_impact_category_id_match_takes_precedence_when_available(self) -> None:
        resolution = optimizer_backend._resolve_score_for_impact(
            scores={},
            score_items=[
                {
                    "impact_method_id": "method-1",
                    "impact_method_name": "Method 1",
                    "impact_category_id": "climate-change",
                    "indicator": "Climate Change",
                    "unit": "kg CO2 eq",
                    "value": -0.00327873,
                },
                {
                    "impact_method_id": "method-1",
                    "impact_method_name": "Method 1",
                    "impact_category_id": "other-category",
                    "indicator": "Climate",
                    "unit": "kg CO2 eq",
                    "value": 10.0,
                },
            ],
            impact_method_id="method-1",
            impact_method_name="Method 1",
            impact_category_id="climate-change",
            indicator="Climate",
            coerce_float=_coerce_float,
        )

        self.assertTrue(resolution["matched"])
        self.assertEqual(resolution["match_strategy"], "impact_category_id+method")
        self.assertAlmostEqual(resolution["value"], -0.00327873)

    def test_constraint_tolerance_is_strict_but_allows_near_zero_noise(self) -> None:
        request = self._make_threshold_request()

        near_zero = optimizer_backend._goal_seek_constraint_values(
            scores={},
            score_items=[
                {
                    "impact_method_id": "method-1",
                    "impact_method_name": "Method 1",
                    "impact_category_id": "climate-change",
                    "indicator": "Climate Change",
                    "value": 1e-13,
                }
            ],
            constraints=request.constraints,
            coerce_float=_coerce_float,
            request=request,
        )
        clearly_positive = optimizer_backend._goal_seek_constraint_values(
            scores={},
            score_items=[
                {
                    "impact_method_id": "method-1",
                    "impact_method_name": "Method 1",
                    "impact_category_id": "climate-change",
                    "indicator": "Climate Change",
                    "value": 1e-10,
                }
            ],
            constraints=request.constraints,
            coerce_float=_coerce_float,
            request=request,
        )

        self.assertTrue(near_zero[0]["satisfied"])
        self.assertFalse(clearly_positive[0]["satisfied"])

    def test_validate_parameter_redefinitions_applied_rejects_missing_overrides(self) -> None:
        with self.assertRaisesRegex(RuntimeError, "did not apply every requested parameter redefinition"):
            optimizer_backend._validate_parameter_redefinitions_applied(
                {"parameter_redefinitions_applied": 0},
                expected_count=1,
            )

    def test_bracketed_threshold_solver_returns_first_feasible_boundary(self) -> None:
        request = self._make_threshold_request()
        job_id = "job-threshold"
        optimizer_backend._GOAL_SEEK_JOBS[job_id] = {
            "job_id": job_id,
            "evaluations": [],
            "events": [],
            "best": None,
            "updated_at": 0.0,
        }
        threshold = 0.8873

        def evaluate_vector(x_raw):
            x = float(list(x_raw)[0])
            constraint_value = threshold - x
            feasible = constraint_value <= 0.0
            return {
                "index": 1,
                "x": [x],
                "objective_label": "parameters.global.capture_rate_frxn",
                "objective_value": x,
                "display_objective_value": x,
                "parameters": [
                    {
                        "field": "parameters.global.capture_rate_frxn",
                        "value": x,
                    }
                ],
                "constraints": [
                    {
                        "indicator": "Climate Change",
                        "operator": "<=",
                        "target": 0.0,
                        "value": constraint_value,
                        "satisfied": feasible,
                    }
                ],
                "feasible": feasible,
            }

        result = optimizer_backend._run_bracketed_threshold_solver(
            job_id=job_id,
            request=request,
            evaluate_vector=evaluate_vector,
            lower=0.8,
            upper=0.99,
        )

        self.assertTrue(result["optimizer"]["success"])
        self.assertEqual(result["optimizer"]["method"], "parameter_threshold_scan_bisect")
        best = result["best"]
        self.assertIsNotNone(best)
        best_x = optimizer_backend._evaluation_primary_x(best)
        self.assertGreaterEqual(best_x, threshold)
        self.assertLess(best_x - threshold, 2e-6)
        proof = result["proof_bracket"]
        self.assertLess(proof["lower_point"]["x"], threshold)
        self.assertGreaterEqual(proof["upper_point"]["x"], threshold)

    def test_bracketed_threshold_solver_rejects_non_monotone_feasibility(self) -> None:
        request = self._make_threshold_request()
        request.n = 32
        job_id = "job-non-monotone"
        optimizer_backend._GOAL_SEEK_JOBS[job_id] = {
            "job_id": job_id,
            "evaluations": [],
            "events": [],
            "best": None,
            "updated_at": 0.0,
        }

        def evaluate_vector(x_raw):
            x = float(list(x_raw)[0])
            feasible = 0.86 <= x <= 0.88 or x >= 0.92
            constraint_value = -1.0 if feasible else 1.0
            return {
                "index": 1,
                "x": [x],
                "objective_label": "parameters.global.capture_rate_frxn",
                "objective_value": x,
                "display_objective_value": x,
                "parameters": [
                    {
                        "field": "parameters.global.capture_rate_frxn",
                        "value": x,
                    }
                ],
                "constraints": [
                    {
                        "indicator": "Climate Change",
                        "operator": "<=",
                        "target": 0.0,
                        "value": constraint_value,
                        "satisfied": feasible,
                    }
                ],
                "feasible": feasible,
            }

        with self.assertRaisesRegex(RuntimeError, "Refusing to report an uncertified threshold"):
            optimizer_backend._run_bracketed_threshold_solver(
                job_id=job_id,
                request=request,
                evaluate_vector=evaluate_vector,
                lower=0.8,
                upper=0.99,
            )


if __name__ == "__main__":
    unittest.main()
