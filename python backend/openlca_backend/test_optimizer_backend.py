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
