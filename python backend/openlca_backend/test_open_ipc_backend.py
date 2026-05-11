from __future__ import annotations

import importlib.util
import pathlib
import sys
import types
import unittest


MODULE_DIR = pathlib.Path(__file__).resolve().parent
if str(MODULE_DIR) not in sys.path:
    sys.path.insert(0, str(MODULE_DIR))

MODULE_PATH = MODULE_DIR / "open_ipc_backend.py"
SPEC = importlib.util.spec_from_file_location("open_ipc_backend_under_test", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
open_ipc_backend = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = open_ipc_backend
SPEC.loader.exec_module(open_ipc_backend)


class _FakeCalcResult:
    def __init__(self, impacts):
        self._impacts = impacts

    def wait_until_ready(self):
        return types.SimpleNamespace(error=None)

    def get_total_impacts(self):
        return list(self._impacts)

    def dispose(self):
        return None


class _FakeClient:
    def __init__(self, impacts):
        self._impacts = impacts
        self.last_setup = None

    def calculate(self, setup):
        self.last_setup = setup
        return _FakeCalcResult(self._impacts)


class OpenLcaIpcBackendTests(unittest.TestCase):
    def test_find_unsupported_structural_content_reports_path(self) -> None:
        payload = {"model": {"processes": [{"id": "p-1"}]}}
        path = open_ipc_backend._find_unsupported_structural_content(payload)
        self.assertEqual(path, "$.model.processes")

    def test_run_single_scenario_rejects_structural_payload(self) -> None:
        with self.assertRaisesRegex(RuntimeError, "Structural model edits are unsupported"):
            open_ipc_backend._run_single_scenario(
                client=_FakeClient([]),
                scenario_model={"processes": [{"id": "p-1"}]},
                product_system_ref=None,
                impact_method_ref=None,
                parameter_catalog={},
            )

    def test_run_single_scenario_rejects_unknown_top_level_payload_keys(self) -> None:
        with self.assertRaisesRegex(RuntimeError, "unsupported top-level content"):
            open_ipc_backend._run_single_scenario(
                client=_FakeClient([]),
                scenario_model={"merge_warnings": ["not supported by IPC"]},
                product_system_ref=None,
                impact_method_ref=None,
                parameter_catalog={},
            )

    def test_run_single_scenario_rejects_skipped_parameter_override(self) -> None:
        with self.assertRaisesRegex(RuntimeError, "could not be translated into exact openLCA parameter overrides"):
            open_ipc_backend._run_single_scenario(
                client=_FakeClient([]),
                scenario_model={
                    "changes": [
                        {
                            "field": "parameters.global.unknown_parameter",
                            "new_value": 0.88,
                        }
                    ]
                },
                product_system_ref=None,
                impact_method_ref=None,
                parameter_catalog={"global_name_map": {"capture_rate_frxn": "capture_rate_frxn"}},
            )

    def test_run_single_scenario_rejects_empty_impact_results(self) -> None:
        with self.assertRaisesRegex(RuntimeError, "returned no LCIA impact values"):
            open_ipc_backend._run_single_scenario(
                client=_FakeClient([]),
                scenario_model={
                    "changes": [
                        {
                            "field": "parameters.global.capture_rate_frxn",
                            "new_value": 0.88,
                        }
                    ]
                },
                product_system_ref=open_ipc_backend.o.Ref(
                    id="ps-1",
                    ref_type=open_ipc_backend.o.RefType.ProductSystem,
                ),
                impact_method_ref=open_ipc_backend.o.Ref(
                    id="method-1",
                    ref_type=open_ipc_backend.o.RefType.ImpactMethod,
                ),
                parameter_catalog={"global_name_map": {"capture_rate_frxn": "capture_rate_frxn"}},
            )

    def test_run_single_scenario_reports_requested_and_applied_redefinitions(self) -> None:
        impact = types.SimpleNamespace(
            amount=1.23,
            unit="kg CO2 eq",
            impact_category=types.SimpleNamespace(
                id="cat-1",
                name="Climate Change",
            ),
        )
        result = open_ipc_backend._run_single_scenario(
            client=_FakeClient([impact]),
            scenario_model={
                "changes": [
                    {
                        "field": "parameters.global.capture_rate_frxn",
                        "new_value": 0.88,
                    }
                ]
            },
            product_system_ref=open_ipc_backend.o.Ref(
                id="ps-1",
                ref_type=open_ipc_backend.o.RefType.ProductSystem,
            ),
            impact_method_ref=open_ipc_backend.o.Ref(
                id="method-1",
                ref_type=open_ipc_backend.o.RefType.ImpactMethod,
            ),
            parameter_catalog={"global_name_map": {"capture_rate_frxn": "capture_rate_frxn"}},
        )

        self.assertEqual(result["parameter_redefinitions_applied"], 1)
        self.assertEqual(result["parameter_redefinitions_requested"], 1)
        self.assertEqual(result["parameter_redefinitions_requested_entries"], 1)
        self.assertEqual(result["parameter_names"], ["capture_rate_frxn"])
        self.assertEqual(result["score_items"][0]["impact_category_id"], "cat-1")
        self.assertAlmostEqual(result["score_items"][0]["value"], 1.23)

    def test_run_single_scenario_uses_explicit_process_target_and_functional_unit(self) -> None:
        impact = types.SimpleNamespace(
            amount=0.42,
            unit="kg CO2 eq",
            impact_category=types.SimpleNamespace(
                id="cat-1",
                name="Climate Change",
            ),
        )
        client = _FakeClient([impact])
        result = open_ipc_backend._run_single_scenario(
            client=client,
            scenario_model={},
            product_system_ref=open_ipc_backend.o.Ref(
                id="ps-1",
                ref_type=open_ipc_backend.o.RefType.ProductSystem,
            ),
            impact_method_ref=open_ipc_backend.o.Ref(
                id="method-1",
                ref_type=open_ipc_backend.o.RefType.ImpactMethod,
            ),
            parameter_catalog={},
            calculation_target={
                "target_type": "process",
                "target_id": "proc-1",
                "product_system_id": "ps-1",
                "process_id": "proc-1",
                "process_name": "Boiler",
                "label": "Boiler (Electricity)",
                "target_ref": open_ipc_backend.o.Ref(
                    id="proc-1",
                    name="Boiler",
                    ref_type=open_ipc_backend.o.RefType.Process,
                ),
                "default_amount": 2.5,
                "unit_ref": open_ipc_backend.o.Ref(id="unit-1", name="kWh"),
                "flow_property_ref": open_ipc_backend.o.Ref(
                    id="fp-1",
                    name="Energy",
                ),
                "flow_ref": open_ipc_backend.o.Ref(
                    id="flow-1",
                    name="Electricity",
                ),
            },
        )

        self.assertIsNotNone(client.last_setup)
        self.assertEqual(
            client.last_setup.allocation,
            open_ipc_backend.o.AllocationType.USE_DEFAULT_ALLOCATION,
        )
        self.assertEqual(client.last_setup.target.id, "proc-1")
        self.assertEqual(client.last_setup.unit.id, "unit-1")
        self.assertEqual(client.last_setup.flow_property.id, "fp-1")
        self.assertAlmostEqual(client.last_setup.amount, 2.5)
        self.assertEqual(result["functional_units"], 2.5)
        self.assertEqual(result["functional_unit"]["unit"], "kWh")
        self.assertEqual(result["calculation_target"]["target_type"], "process")
        self.assertEqual(result["calculation_target"]["process_id"], "proc-1")

    def test_resolve_process_calculation_target_requires_membership_and_reference_unit(self) -> None:
        process_entity = types.SimpleNamespace(
            id="proc-1",
            name="Boiler",
            exchanges=[
                types.SimpleNamespace(
                    amount=1.0,
                    is_input=False,
                    is_quantitative_reference=True,
                    flow=open_ipc_backend.o.Ref(id="flow-1", name="Electricity"),
                    unit=open_ipc_backend.o.Ref(id="unit-1", name="kWh"),
                    flow_property=open_ipc_backend.o.Ref(id="fp-1", name="Energy"),
                )
            ],
        )
        product_system_entity = types.SimpleNamespace(
            processes=[types.SimpleNamespace(id="proc-1", name="Boiler")],
        )
        product_system_ref = open_ipc_backend.o.Ref(
            id="ps-1",
            name="Plant Output",
            ref_type=open_ipc_backend.o.RefType.ProductSystem,
        )

        class _TargetClient:
            def get(self, model_type, uid):
                if uid == "proc-1":
                    return process_entity
                return None

        target = open_ipc_backend._resolve_calculation_target(
            client=_TargetClient(),
            product_system_ref=product_system_ref,
            product_system_entity=product_system_entity,
            target_type="process",
            process_id="proc-1",
        )

        self.assertEqual(target["target_type"], "process")
        self.assertEqual(target["process_id"], "proc-1")
        self.assertEqual(target["process_name"], "Boiler")
        self.assertAlmostEqual(target["default_amount"], 1.0)
        self.assertEqual(target["unit_ref"].id, "unit-1")
        self.assertEqual(target["flow_property_ref"].id, "fp-1")

    def test_normalize_functional_unit_for_target_rejects_mismatched_unit(self) -> None:
        target = {
            "default_amount": 1.0,
            "unit_ref": open_ipc_backend.o.Ref(id="unit-1", name="kWh"),
            "flow_property_ref": open_ipc_backend.o.Ref(id="fp-1", name="Energy"),
            "flow_ref": open_ipc_backend.o.Ref(id="flow-1", name="Electricity"),
        }
        with self.assertRaisesRegex(RuntimeError, "does not match"):
            open_ipc_backend._normalize_functional_unit_for_target(
                {"amount": 2.0, "unit": "kg"},
                target,
            )


if __name__ == "__main__":
    unittest.main()
