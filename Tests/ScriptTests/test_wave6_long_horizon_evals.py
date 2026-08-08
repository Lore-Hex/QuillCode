import importlib.util
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts" / "wave6-long-horizon-evals.py"
SPEC = importlib.util.spec_from_file_location("wave6_long_horizon_evals", SCRIPT)
WAVE6 = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = WAVE6
SPEC.loader.exec_module(WAVE6)


class Wave6LongHorizonEvalTests(unittest.TestCase):
    def test_catalog_contains_exact_wave6_range(self):
        rows = WAVE6.load_rows()

        self.assertEqual(tuple(rows), WAVE6.TASK_IDS)
        self.assertEqual(WAVE6.TASK_IDS, tuple(range(311, 321)))

    def test_prepare_writes_isolated_inputs_and_exact_ui_prompts(self):
        with tempfile.TemporaryDirectory() as temporary:
            run_root = Path(temporary)
            WAVE6.prepare(run_root)

            self.assertTrue((run_root / "workspace/inputs/README.md").is_file())
            self.assertEqual(
                sorted(path.stem for path in (run_root / "prompts").glob("*.txt")),
                [str(task_id) for task_id in WAVE6.TASK_IDS],
            )
            prompt = (run_root / "prompts/311.txt").read_text(encoding="utf-8")
            self.assertIn("outputs/311/progress.md", prompt)
            self.assertIn("outputs/311/people-shortlist.csv", prompt)
            self.assertIn("signed-in linkedin session in read-only mode", prompt.lower())
            self.assertIn("Do not declare completion", prompt)

    def test_empty_workspace_fails_required_artifacts_and_minima(self):
        with tempfile.TemporaryDirectory() as temporary:
            result = WAVE6.grade_task(Path(temporary), 311)

        self.assertFalse(result["ok"])
        failed_names = {check["name"] for check in result["checks"] if not check["ok"]}
        self.assertIn("progress checkpoint", failed_names)
        self.assertIn("people-shortlist.csv row minimum", failed_names)
        self.assertIn("research-log.csv source metadata", failed_names)

    def test_complete_task_311_fixture_passes_structural_grade(self):
        with tempfile.TemporaryDirectory() as temporary:
            workspace = Path(temporary)
            output = workspace / "outputs/311"
            output.mkdir(parents=True)
            (output / "progress.md").write_text("# Progress\n\n" + "Completed phase.\n" * 8)

            spec = WAVE6.SPECS[311]
            for relative in spec.required_files:
                path = output / relative
                if path.suffix == ".csv":
                    continue
                path.write_text("# Complete\n\n" + "Evidence-backed content.\n" * 4)

            for relative in {"people-shortlist.csv", "research-log.csv"}:
                minimum = spec.csv_minima[relative]
                rows = "\n".join(
                    f"item-{index},https://example.com/{index},2026-08-08,high"
                    for index in range(minimum)
                )
                (output / relative).write_text(
                    "name,source_url,access_date,confidence\n" + rows + "\n"
                )
            (output / "signal-taxonomy.csv").write_text(
                "signal,source_url,access_date,confidence\n"
                "manual close,https://example.com/signal,2026-08-08,high\n"
            )
            (output / "segment-scorecard.csv").write_text(
                "segment,score,rationale\n"
                "Series A SaaS,5,Strong evidence of manual close workflows\n"
            )

            result = WAVE6.grade_task(workspace, 311)

        self.assertTrue(result["ok"], result["checks"])

    def test_task_selection_rejects_out_of_wave_ids(self):
        with self.assertRaises(WAVE6.EvalError):
            WAVE6.parse_task_ids("311,999")


if __name__ == "__main__":
    unittest.main()
