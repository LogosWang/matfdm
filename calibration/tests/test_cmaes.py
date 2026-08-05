#!/usr/bin/env python3
import csv
import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

import numpy as np


class CMAESTest(unittest.TestCase):
    def write_metrics(self, metrics: Path, cases: list[dict], batch_shift: float) -> None:
        for number, case in enumerate(cases):
            x = np.log(np.asarray(case["mult"], dtype=float))
            fronts = [40 + 2.0 * x.sum() - batch_shift,
                      65 + 1.5 * (x[::2].sum() - x[1::2].sum()),
                      100 + 2.5 * (x[:5].sum() - x[5:].sum()) + batch_shift]
            inventories = [100.0, 90.0 - 0.2 * number, 80.0 - 0.3 * number]
            cr = [50.0, 49.0, 48.0]
            fe = [42.0, 42.0, 42.0]
            si = [8.0, 9.0, 10.0]
            path = metrics / f"{case['case_tag']}.csv"
            with path.open("w", newline="") as stream:
                writer = csv.writer(stream)
                writer.writerow(["dose", "front_nm", "residual_nm",
                                 "Cr_atom_inventory", "Cr_atom_pct",
                                 "Fe_atom_pct", "Si_atom_pct"])
                for dose, target, front, inventory, cp, fp, sp in zip(
                        (0, 0.5, 3), (40, 60, 100), fronts, inventories, cr, fe, si):
                    writer.writerow([dose, front, front - target, inventory, cp, fp, sp])

    def run_optimizer(self, optimizer: Path, state: Path, run: Path,
                      output: Path, batch: int) -> None:
        environment = os.environ.copy()
        environment.update({"CALIB_STATE_PATH": str(state),
                            "CALIB_REPO_DIR": str(run),
                            "CALIB_OUT_DIR": str(output),
                            "CALIB_BATCH_NO": str(batch)})
        subprocess.run(["python3", str(optimizer)], env=environment,
                       check=True, stdout=subprocess.DEVNULL)

    def test_direct_generation_one_idempotency_and_second_tell(self):
        root = Path(__file__).resolve().parents[2]
        optimizer = root / "calibration" / "optimizer" / "propose_cmaes.py"
        source = json.loads((root / "calibration" / "state.json").read_text())
        with tempfile.TemporaryDirectory() as temporary:
            temporary = Path(temporary)
            run = temporary / "run"
            metrics = run / "calibration" / "metrics"
            output = temporary / "optimizer"
            metrics.mkdir(parents=True)
            state_path = temporary / "state.json"
            state_path.write_text(json.dumps(source))

            self.run_optimizer(optimizer, state_path, run, output, 1)
            first = json.loads(state_path.read_text())
            batch01 = first["batch01_cases"]
            self.assertEqual(10, len(batch01))
            self.assertEqual(10, len({tuple(case["mult"]) for case in batch01}))
            self.assertTrue(all(case["coupling_model"] == "full_covariance_10d"
                                for case in batch01))
            generation = json.loads((output / "cma_generation.json").read_text())
            self.assertEqual(0, generation["generation_told"])
            self.assertEqual(1, generation["pending_batch"])

            # Retrying generation one must return the same pending population.
            self.run_optimizer(optimizer, state_path, run, output, 1)
            repeated = json.loads(state_path.read_text())
            self.assertEqual(batch01, repeated["batch01_cases"])
            generation = json.loads((output / "cma_generation.json").read_text())
            self.assertEqual(0, generation["generation_told"])

            self.write_metrics(metrics, batch01, 0.0)
            self.run_optimizer(optimizer, state_path, run, output, 2)
            second = json.loads(state_path.read_text())
            batch02 = second["batch02_cases"]
            self.assertEqual(10, len(batch02))
            self.assertNotEqual(batch01, batch02)
            generation = json.loads((output / "cma_generation.json").read_text())
            self.assertEqual(1, generation["generation_told"])
            self.assertEqual(2, generation["pending_batch"])

            self.write_metrics(metrics, batch02, 0.25)
            self.run_optimizer(optimizer, state_path, run, output, 3)
            third = json.loads(state_path.read_text())
            self.assertEqual(10, len(third["batch03_cases"]))
            self.assertNotEqual(batch02, third["batch03_cases"])
            generation = json.loads((output / "cma_generation.json").read_text())
            self.assertEqual(2, generation["generation_told"])
            self.assertEqual(3, generation["pending_batch"])
            self.assertEqual("constrained_active_cmaes_ask_tell", generation["strategy"])
            for name in ("cma_state.pkl", "cma_generation.json", "covariance.csv",
                         "mean_log_multipliers.csv", "fitness_history.csv",
                         "proposed_steps.json"):
                self.assertTrue((output / name).exists(), name)


if __name__ == "__main__":
    unittest.main()
