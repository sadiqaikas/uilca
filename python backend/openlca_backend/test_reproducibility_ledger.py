from __future__ import annotations

import importlib.util
import pathlib
import sys
import tempfile
import unittest


MODULE_PATH = pathlib.Path(__file__).with_name("reproducibility_ledger.py")
SPEC = importlib.util.spec_from_file_location(
    "reproducibility_ledger_under_test",
    MODULE_PATH,
)
assert SPEC is not None and SPEC.loader is not None
reproducibility_ledger = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = reproducibility_ledger
SPEC.loader.exec_module(reproducibility_ledger)


class ReproducibilityLedgerTests(unittest.TestCase):
    def test_register_run_assigns_sequential_index_per_series(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            db_path = pathlib.Path(tmpdir) / "ledger.sqlite"
            request_one = reproducibility_ledger.ReproducibilityRunRequest(
                bundle_name="normal",
                model_name="gpt-5",
                prompt_hash="hash-a",
                status="success",
                run_uid="run-1",
            )
            request_two = reproducibility_ledger.ReproducibilityRunRequest(
                bundle_name="normal",
                model_name="gpt-5",
                prompt_hash="hash-a",
                status="failure",
                run_uid="run-2",
            )
            request_other_series = reproducibility_ledger.ReproducibilityRunRequest(
                bundle_name="normal",
                model_name="glm-5.1",
                prompt_hash="hash-a",
                status="success",
                run_uid="run-3",
            )

            row_one, inserted_one = reproducibility_ledger.register_run_in_ledger(
                request_one,
                db_path=db_path,
            )
            row_two, inserted_two = reproducibility_ledger.register_run_in_ledger(
                request_two,
                db_path=db_path,
            )
            row_three, inserted_three = reproducibility_ledger.register_run_in_ledger(
                request_other_series,
                db_path=db_path,
            )

            self.assertTrue(inserted_one)
            self.assertTrue(inserted_two)
            self.assertTrue(inserted_three)
            self.assertEqual(row_one["run_index"], 1)
            self.assertEqual(row_two["run_index"], 2)
            self.assertEqual(row_three["run_index"], 1)

    def test_register_run_is_idempotent_for_same_run_uid(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            db_path = pathlib.Path(tmpdir) / "ledger.sqlite"
            request = reproducibility_ledger.ReproducibilityRunRequest(
                bundle_name="optimization",
                model_name="gpt-5",
                prompt_hash="hash-b",
                status="completed",
                run_uid="goal-job-1",
            )

            first_row, first_inserted = reproducibility_ledger.register_run_in_ledger(
                request,
                db_path=db_path,
            )
            second_row, second_inserted = reproducibility_ledger.register_run_in_ledger(
                request,
                db_path=db_path,
            )

            self.assertTrue(first_inserted)
            self.assertFalse(second_inserted)
            self.assertEqual(first_row["ledger_id"], second_row["ledger_id"])
            self.assertEqual(first_row["run_index"], 1)
            self.assertEqual(second_row["run_index"], 1)
            self.assertEqual(second_row["bundle_name"], "optimisation")

    def test_snapshot_csv_contains_all_runs_for_bundle(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            db_path = pathlib.Path(tmpdir) / "ledger.sqlite"
            requests = [
                reproducibility_ledger.ReproducibilityRunRequest(
                    bundle_name="uncertainty",
                    model_name="manual",
                    prompt_hash="hash-c",
                    status="completed",
                    run_uid="unc-1",
                ),
                reproducibility_ledger.ReproducibilityRunRequest(
                    bundle_name="uncertainty",
                    model_name="manual",
                    prompt_hash="hash-c",
                    status="failed",
                    run_uid="unc-2",
                ),
                reproducibility_ledger.ReproducibilityRunRequest(
                    bundle_name="normal",
                    model_name="gpt-5",
                    prompt_hash="hash-c",
                    status="success",
                    run_uid="normal-1",
                ),
            ]
            for request in requests:
                reproducibility_ledger.register_run_in_ledger(request, db_path=db_path)

            csv_text = reproducibility_ledger.build_bundle_snapshot_csv(
                bundle_name="uncertainty",
                db_path=db_path,
            )

            self.assertIn("bundle_name,model_name,prompt_hash,run_index,status", csv_text)
            self.assertIn("uncertainty,manual,hash-c,1,completed", csv_text)
            self.assertIn("uncertainty,manual,hash-c,2,failed", csv_text)
            self.assertNotIn("normal,gpt-5,hash-c,1,success", csv_text)

    def test_snapshot_csv_can_be_cut_off_at_anchor_ledger_id(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            db_path = pathlib.Path(tmpdir) / "ledger.sqlite"
            first_row, _ = reproducibility_ledger.register_run_in_ledger(
                reproducibility_ledger.ReproducibilityRunRequest(
                    bundle_name="normal",
                    model_name="gpt-5",
                    prompt_hash="hash-d",
                    status="success",
                    run_uid="normal-1",
                ),
                db_path=db_path,
            )
            reproducibility_ledger.register_run_in_ledger(
                reproducibility_ledger.ReproducibilityRunRequest(
                    bundle_name="normal",
                    model_name="gpt-5",
                    prompt_hash="hash-d",
                    status="failure",
                    run_uid="normal-2",
                ),
                db_path=db_path,
            )

            csv_text = reproducibility_ledger.build_bundle_snapshot_csv(
                bundle_name="normal",
                up_to_ledger_id=first_row["ledger_id"],
                db_path=db_path,
            )

            self.assertIn("normal,gpt-5,hash-d,1,success", csv_text)
            self.assertNotIn("normal,gpt-5,hash-d,2,failure", csv_text)


if __name__ == "__main__":
    unittest.main()
