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
    def test_required_concepts_never_exceed_detected_concepts(self):
        self.assertEqual(WAVE5.required_concept_matches(0), 0)
        self.assertEqual(WAVE5.required_concept_matches(1), 1)
        self.assertEqual(WAVE5.required_concept_matches(2), 2)
        self.assertEqual(WAVE5.required_concept_matches(3), 2)
        self.assertEqual(WAVE5.required_concept_matches(10), 4)

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
