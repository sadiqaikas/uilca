from __future__ import annotations

import importlib.util
import pathlib
import sys
import types
import unittest

from fastapi import HTTPException


MODULE_DIR = pathlib.Path(__file__).resolve().parent
if str(MODULE_DIR) not in sys.path:
    sys.path.insert(0, str(MODULE_DIR))

MODULE_PATH = MODULE_DIR / "uncertainty_backend.py"
SPEC = importlib.util.spec_from_file_location("uncertainty_backend_under_test", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
uncertainty_backend = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = uncertainty_backend
SPEC.loader.exec_module(uncertainty_backend)


class _FakeClient:
    def __init__(self, product_system_ref, product_system_entity, impact_method_entity):
        self._product_system_ref = product_system_ref
        self._product_system_entity = product_system_entity
        self._impact_method_entity = impact_method_entity

    def get_descriptor(self, model_type, uid):
        if uid == self._product_system_ref.id:
            return self._product_system_ref
        return None

    def get_descriptors(self, model_type):
        return [self._product_system_ref]

    def get(self, model_type, uid):
        if uid == self._product_system_ref.id:
            return self._product_system_entity
        if uid == "method-1":
            return self._impact_method_entity
        return None


class UncertaintyBackendTests(unittest.TestCase):
    def _make_schema(self):
        return types.SimpleNamespace(
            ProductSystem=object(),
            ImpactMethod=object(),
            RefType=types.SimpleNamespace(
                ProductSystem="ProductSystem",
                ImpactMethod="ImpactMethod",
            ),
        )

    def _make_request(self, **overrides):
        payload = {
            "tool": "uncertainty_propagation",
            "product_system_id": "ps-1",
            "target_type": "process",
            "process_id": "proc-1",
            "functional_unit": {
                "amount": 2.0,
                "unit": "kWh",
                "flow_property": "Energy",
            },
            "impact_method_id": "method-1",
            "impact_categories": [
                {
                    "impact_category_id": "cat-1",
                    "indicator": "Climate Change",
                    "impact_method_id": "method-1",
                }
            ],
            "sampling": {"method": "latin_hypercube", "n_samples": 25},
            "parameters": [
                {
                    "scope": "global",
                    "name": "capture_rate_frxn",
                    "uncertainty": {
                        "distributionType": "UNIFORM_DISTRIBUTION",
                        "minimum": 0.85,
                        "maximum": 0.95,
                    },
                }
            ],
            "outputs": {},
            "ipc_url": "http://localhost:8080",
        }
        payload.update(overrides)
        return uncertainty_backend.OpenLcaUncertaintyStartRequest(**payload)

    def _make_client(self):
        product_system_ref = types.SimpleNamespace(
            id="ps-1",
            name="Plant Output",
            ref_type=None,
        )
        product_system_entity = types.SimpleNamespace(id="ps-1", name="Plant Output")
        impact_method_entity = types.SimpleNamespace(
            id="method-1",
            name="Method 1",
            impact_categories=[
                types.SimpleNamespace(
                    id="cat-1",
                    name="Climate Change",
                    reference_unit="kg CO2 eq",
                )
            ],
        )
        return _FakeClient(
            product_system_ref=product_system_ref,
            product_system_entity=product_system_entity,
            impact_method_entity=impact_method_entity,
        )

    def _make_deps(self, *, resolve_target, normalize_fu):
        return {
            "olca_schema": self._make_schema(),
            "build_parameter_catalog": lambda client, product_system_entity: {
                "global_details": {
                    "capture_rate_frxn": {
                        "name": "capture_rate_frxn",
                        "editable": True,
                        "baseline_value": 0.9,
                        "unit": "",
                    }
                },
                "process_param_details": {},
                "process_name_ids_map": {},
                "process_ids": set(),
            },
            "resolve_calculation_target": resolve_target,
            "normalize_functional_unit_for_target": normalize_fu,
            "public_calculation_target": lambda target: {
                "target_type": target["target_type"],
                "process_id": target.get("process_id"),
                "label": target.get("label"),
            },
            "pick_impact_method": lambda client, impact_method_id, impact_method_name: types.SimpleNamespace(
                id="method-1",
                name="Method 1",
                ref_type=None,
            ),
            "default_impact_method_name": "Method 1",
            "default_ipc_url": "http://localhost:8080",
        }

    def test_validate_uncertainty_request_resolves_process_target_and_normalizes_functional_unit(self):
        request = self._make_request()
        client = self._make_client()
        seen = {}

        def resolve_target(*, client, product_system_ref, product_system_entity, target_type, process_id):
            seen["target_type"] = target_type
            seen["process_id"] = process_id
            return {
                "target_type": "process",
                "process_id": process_id,
                "label": "Boiler (Electricity)",
            }

        def normalize_fu(functional_unit, target):
            seen["functional_unit"] = dict(functional_unit)
            seen["target"] = dict(target)
            return {
                "amount": 2.0,
                "unit": "kWh",
                "unit_id": "unit-1",
                "flow_property": "Energy",
                "flow_property_id": "fp-1",
            }

        validated = uncertainty_backend._validate_uncertainty_request(
            request,
            client,
            self._make_deps(resolve_target=resolve_target, normalize_fu=normalize_fu),
        )

        self.assertEqual(seen["target_type"], "process")
        self.assertEqual(seen["process_id"], "proc-1")
        self.assertEqual(seen["functional_unit"]["unit"], "kWh")
        self.assertEqual(validated["target_type"], "process")
        self.assertEqual(validated["process_id"], "proc-1")
        self.assertEqual(validated["calculation_target"]["process_id"], "proc-1")
        self.assertEqual(validated["functional_unit"]["unit"], "kWh")
        self.assertEqual(validated["functional_unit"]["flow_property"], "Energy")

    def test_validate_uncertainty_request_rejects_functional_unit_mismatch(self):
        request = self._make_request(
            functional_unit={
                "amount": 2.0,
                "unit": "kg",
                "flow_property": "Mass",
            }
        )
        client = self._make_client()

        def resolve_target(*, client, product_system_ref, product_system_entity, target_type, process_id):
            return {
                "target_type": "process",
                "process_id": process_id,
                "label": "Boiler (Electricity)",
            }

        def normalize_fu(functional_unit, target):
            raise RuntimeError(
                "Functional unit unit 'kg' does not match the selected calculation target unit 'kWh'."
            )

        with self.assertRaises(HTTPException) as caught:
            uncertainty_backend._validate_uncertainty_request(
                request,
                client,
                self._make_deps(resolve_target=resolve_target, normalize_fu=normalize_fu),
            )

        self.assertEqual(caught.exception.status_code, 400)
        self.assertIn("does not match", str(caught.exception.detail))


if __name__ == "__main__":  # pragma: no cover
    unittest.main()
