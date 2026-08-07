import importlib.util
import json
import tempfile
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

    def test_reusable_templates_use_non_placeholder_form_fields(self):
        prompt = WAVE5.build_prompt({
            "ID": 212,
            "Task (what the person types)": "Create an interview guide with a note-taking template.",
            "Capability needed": "Multi-file artifacts",
        })

        self.assertIn("blank lines, empty cells, or checkboxes", prompt)
        self.assertIn("instead of bracketed prompts", prompt)
        self.assertIn("Never use `[their words]`", prompt)

    def test_placeholder_detection_distinguishes_markdown_controls_and_citations(self):
        self.assertTrue(WAVE5.contains_placeholder("Ask about [their words]."))
        self.assertTrue(WAVE5.contains_placeholder("Owner: [TBD]"))
        self.assertTrue(WAVE5.contains_placeholder("Lorem ipsum"))
        self.assertFalse(WAVE5.contains_placeholder("- [ ] Pending\n- [x] Complete"))
        self.assertFalse(WAVE5.contains_placeholder("See [source](https://example.test) and [1]."))
        self.assertFalse(WAVE5.contains_placeholder("See the note[^source-1]."))

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

    def test_investor_outreach_requires_all_fifteen_targets(self):
        complete = "\n".join(f"## Fund {index:02d}" for index in range(1, 16))
        required, matched = WAVE5.required_output_term_matches(256, complete)
        self.assertEqual(len(required), 15)
        self.assertEqual(matched, list(required))

        incomplete = "## Fund 01\n\n## Fund 02\n\nFunds 03-15 summarized together"
        required, matched = WAVE5.required_output_term_matches(256, incomplete)
        self.assertEqual(len(matched), 2)
        self.assertNotEqual(matched, list(required))

    def test_case_fixture_coverage_requires_every_planned_hire(self):
        complete = "\n".join(f"H{index:02d}" for index in range(1, 13))
        required, matched = WAVE5.required_output_term_matches(278, complete)

        self.assertEqual(len(required), 12)
        self.assertEqual(matched, list(required))
        self.assertIn("H12", WAVE5.fixture_context({"ID": 278, "Category": "Hiring & Team"}))

    def test_rescue_plan_requires_each_stale_open_account(self):
        complete = "\n".join(
            f"## Account {index:02d}\n\nHello finance team,"
            for index in (1, 2, 3, 4, 5, 29, 30, 31, 32, 33)
        )
        required, matched = WAVE5.required_output_term_matches(228, complete)

        self.assertEqual(len(required), 10)
        self.assertEqual(matched, list(required))
        context = WAVE5.fixture_context({"ID": 228, "Category": "Founder Sales"})
        self.assertIn("2026-05-06", context)
        self.assertIn("do not use templates", context)

        incomplete = "Close: 02, 04, 32. Nurture: 01, 05, 29, 31. Re-engage: 03, 30, 33."
        _, matched = WAVE5.required_output_term_matches(228, incomplete)
        self.assertEqual(matched, [])

    def test_seo_topic_map_includes_supplied_competitor_pages(self):
        context = WAVE5.fixture_context({"ID": 248, "Category": "Launch & Growth"})
        self.assertIn("CloseFlow pricing page captured 2026-07-15", context)
        self.assertIn("MonthEnd Pro pricing page captured 2026-07-20", context)

        required, matched = WAVE5.required_output_term_matches(
            248,
            "CloseFlow supplies no outcome evidence. MonthEnd Pro supplies no adoption data.",
        )
        self.assertEqual(required, ("CloseFlow", "MonthEnd Pro"))
        self.assertEqual(matched, list(required))

    def test_explicit_primary_filename_is_preserved(self):
        row = {
            "ID": 211,
            "Category": "Customer Discovery",
            "Task (what the person types)": "Save customer-discovery-synthesis.md.",
            "Capability needed": "Multi-file artifacts",
        }

        self.assertEqual(WAVE5.primary_output_path(row), "outputs/customer-discovery-synthesis.md")
        self.assertIn("`outputs/customer-discovery-synthesis.md`", WAVE5.build_prompt(row))

    def test_multi_file_case_requires_supporting_artifact(self):
        row = {
            "ID": 213,
            "Category": "Customer Discovery",
            "Task (what the person types)": "Produce lost-demo-patterns.csv and a summary.",
            "Capability needed": "Multi-file artifacts",
        }
        artifact = WAVE5.additional_artifacts(row)[0]
        self.assertIn("`outputs/lost-demo-patterns.csv`", WAVE5.build_prompt(row))

        with tempfile.TemporaryDirectory() as temporary:
            workspace = Path(temporary)
            passed, _ = WAVE5.check_additional_artifact(workspace, artifact)
            self.assertFalse(passed)
            output = workspace / artifact["path"]
            output.parent.mkdir(parents=True)
            output.write_text("header\n" + "\n".join(f"row-{index}" for index in range(8)))
            passed, detail = WAVE5.check_additional_artifact(workspace, artifact)
            self.assertTrue(passed, detail)

    def test_repeated_item_coverage_includes_required_supporting_artifacts(self):
        row = {
            "ID": 213,
            "Category": "Customer Discovery",
            "Task (what the person types)": "Produce lost-demo-patterns.csv and a summary.",
            "Capability needed": "Multi-file artifacts",
        }

        with tempfile.TemporaryDirectory() as temporary:
            workspace = Path(temporary)
            artifact = WAVE5.additional_artifacts(row)[0]
            output = workspace / artifact["path"]
            output.parent.mkdir(parents=True)
            output.write_text(
                "id,pattern\n" + "\n".join(f"LD{index:02d},pattern" for index in range(1, 9))
            )
            coverage = WAVE5.artifact_coverage_text(
                "# Summary\n\nLost demos cluster around four recurring patterns.",
                workspace,
                WAVE5.additional_artifacts(row),
            )
            required, matched = WAVE5.required_output_term_matches(213, coverage)

        self.assertEqual(matched, list(required))

    def test_case_fixture_catalog_is_valid(self):
        WAVE5.validate_case_fixtures()

    def test_concept_aliases_accept_equivalent_founder_language(self):
        output = WAVE5.normalize(
            "Account prioritization by trigger, with Var vs Plan reporting and headline, subhead, CTA copy."
        )

        self.assertTrue(WAVE5.concept_matches("target account", output))
        self.assertTrue(WAVE5.concept_matches("event", output))
        self.assertTrue(WAVE5.concept_matches("variance", output))
        self.assertTrue(WAVE5.concept_matches("landing page", output))
        self.assertFalse(WAVE5.concept_matches("runway", output))

        jtbd_output = WAVE5.normalize("JTBD map with four functional jobs and source citations.")
        self.assertTrue(WAVE5.concept_matches("jobs to be done", jtbd_output))

        commitments_output = WAVE5.normalize(
            "Sales commitments and customer-facing commitments compared with the roadmap."
        )
        self.assertTrue(WAVE5.concept_matches("customer commitment", commitments_output))

        outreach_output = WAVE5.normalize("Five personalized cold outreach drafts with follow-ups.")
        self.assertTrue(WAVE5.concept_matches("cold email", outreach_output))

        competitive_output = WAVE5.normalize("SEO map of customer questions and competitive pages.")
        self.assertTrue(WAVE5.concept_matches("competitor", competitive_output))

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

    def test_tool_failure_recovery_accepts_a_later_changed_strategy(self):
        recovered = [
            tool("host.shell.run", status="failed"),
            tool("host.shell.run", output_payload={"ok": True}),
        ]
        changed_strategy = [
            tool("host.file.write", status="failed"),
            tool("host.shell.run", output_payload={"ok": True}),
        ]
        final_failure = [
            tool("host.shell.run", output_payload={"ok": True}),
            tool("host.shell.run", status="failed"),
        ]

        self.assertEqual(WAVE5.unrecovered_tool_failures(recovered), [])
        self.assertEqual(WAVE5.unrecovered_tool_failures(changed_strategy), [])
        self.assertEqual(WAVE5.unrecovered_tool_failures(final_failure), [final_failure[1]])

    def test_product_grounding_accepts_customer_commitment_source_facts(self):
        anchors = WAVE5.CATEGORY_FIXTURES["Product & Roadmap"]["anchors"]
        output = WAVE5.normalize(
            "Timezone-safe reminders remain targeted for Q3, with a rollback owner required."
        )
        matched = [anchor for anchor in anchors if WAVE5.normalize(anchor) in output]

        self.assertGreaterEqual(len(matched), 2)

    def test_grounding_uses_case_specific_required_source_facts(self):
        row = {"ID": 230, "Category": "Founder Sales"}
        anchors = WAVE5.grounding_anchors(row)
        output = WAVE5.normalize("Win-loss review covers D01 through D12 and the observed SSO losses.")
        matched = [anchor for anchor in anchors if WAVE5.normalize(anchor) in output]

        self.assertIn("D01", matched)
        self.assertIn("D12", matched)
        self.assertGreaterEqual(len(matched), 2)

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
