import importlib.util
import json
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts" / "wave5-cowork-evals.py"
SPEC = importlib.util.spec_from_file_location("wave5_cowork_evals", SCRIPT)
WAVE5 = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(WAVE5)


def tool(name, input_payload=None, output_payload=None, status="done"):
    return {
        "name": name,
        "status": status,
        "inputJSON": json.dumps(input_payload or {}),
        "outputJSON": json.dumps(output_payload or {}),
    }


class Wave5CoworkEvalTests(unittest.TestCase):
    def test_shell_prompt_requires_safe_schema_aware_validation(self):
        prompt = WAVE5.build_prompt({
            "ID": 261,
            "Task (what the person types)": "Build a runway plan.",
            "Capability needed": "Files/Shell",
        })

        self.assertIn("file read tool separately", prompt)
        self.assertIn("temporary script and output inside the workspace", prompt)
        self.assertIn("inspect the source schema first", prompt)
        self.assertIn("only fields known to be numeric", prompt)
        self.assertIn("Do not execute a source path as a command", prompt)
        self.assertIn("do not leave bracketed fill-in fields", prompt.lower())

    def test_non_shell_prompts_prohibit_unnecessary_shell_and_directory_listing(self):
        for capability in ("Browser pane", "Multi-file artifacts"):
            with self.subTest(capability=capability):
                prompt = WAVE5.build_prompt({
                    "ID": 211,
                    "Task (what the person types)": "Synthesize the sources.",
                    "Capability needed": capability,
                })
                self.assertIn("Do not use the shell tool", prompt)
                self.assertIn("list the output directory", prompt)

    def test_every_capability_requires_dedicated_source_reads(self):
        for capability in ("Browser pane", "Files/Shell", "Multi-file artifacts"):
            with self.subTest(capability=capability):
                prompt = WAVE5.build_prompt({
                    "ID": 211,
                    "Task (what the person types)": "Synthesize the sources.",
                    "Capability needed": capability,
                })
                self.assertIn("file read tool separately", prompt)

    def test_required_concepts_never_exceed_detected_concepts(self):
        self.assertEqual(WAVE5.required_concept_matches(0), 0)
        self.assertEqual(WAVE5.required_concept_matches(1), 1)
        self.assertEqual(WAVE5.required_concept_matches(2), 2)
        self.assertEqual(WAVE5.required_concept_matches(3), 2)
        self.assertEqual(WAVE5.required_concept_matches(10), 4)

    def test_concept_aliases_accept_equivalent_founder_language(self):
        output = WAVE5.normalize("Account prioritization by trigger, with Var vs Plan reporting.")

        self.assertTrue(WAVE5.concept_matches("target account", output))
        self.assertTrue(WAVE5.concept_matches("event", output))
        self.assertTrue(WAVE5.concept_matches("variance", output))
        self.assertFalse(WAVE5.concept_matches("runway", output))

    def test_normalize_ignores_numeric_thousands_separators(self):
        self.assertIn("820000", WAVE5.normalize("Cash: $820,000"))
        self.assertIn("98000", WAVE5.normalize("Burn: 98_000"))

    def test_substantive_accepts_compact_structured_prose(self):
        compact = "# Plan\n\n" + ("Specific source-grounded recommendation. " * 12) + "\n\n" + (
            "Decision, owner, timing, and evidence. " * 8
        )
        self.assertTrue(WAVE5.is_substantive(compact))
        self.assertFalse(WAVE5.is_substantive("# Thin\n\nNot enough detail."))

    def test_refusal_detection_requires_task_level_first_person_refusal(self):
        self.assertTrue(WAVE5.contains_task_refusal("I cannot complete this task with the supplied data."))
        self.assertTrue(WAVE5.contains_task_refusal("Unable to deliver the requested artifact."))
        self.assertFalse(WAVE5.contains_task_refusal("I cannot support a recovery date from this evidence."))
        self.assertFalse(WAVE5.contains_task_refusal("The vendor cannot complete the review by Friday."))

    def test_tool_success_rejects_semantic_failures_and_denials(self):
        self.assertTrue(WAVE5.tool_succeeded(tool("host.file.read", output_payload={"ok": True})))
        self.assertFalse(WAVE5.tool_succeeded(tool("host.file.read", output_payload={"ok": False})))
        self.assertFalse(WAVE5.tool_succeeded(tool(
            "host.shell.run",
            output_payload={"verdict": "deny", "reviewOutcome": "denied"},
        )))
        self.assertFalse(WAVE5.tool_succeeded(tool("host.file.read", status="failed")))

    def test_artifact_readback_must_follow_last_successful_write(self):
        output = "outputs/wave5-211.md"
        write = tool("host.file.write", {"path": output}, {"ok": True})
        read = tool("host.file.read", {"path": output}, {"ok": True})
        self.assertTrue(WAVE5.has_artifact_readback([write, read], output))
        self.assertFalse(WAVE5.has_artifact_readback([read, write], output))
        self.assertFalse(WAVE5.has_artifact_readback([write], output))

    def test_denied_read_does_not_verify_artifact(self):
        output = "outputs/wave5-211.md"
        tools = [
            tool("host.file.write", {"path": output}, {"ok": True}),
            tool(
                "host.file.read",
                {"path": output},
                {"verdict": "deny", "reviewOutcome": "denied"},
            ),
        ]
        self.assertFalse(WAVE5.has_artifact_readback(tools, output))


if __name__ == "__main__":
    unittest.main()
