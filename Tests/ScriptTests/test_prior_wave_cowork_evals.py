import importlib.util
import csv
import json
import tempfile
import unittest
import xml.etree.ElementTree as ET
import zipfile
from datetime import datetime, timezone
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts" / "prior-wave-cowork-evals.py"
SPEC = importlib.util.spec_from_file_location("prior_wave_cowork_evals", SCRIPT)
PRIOR = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PRIOR)


def tool(name, path=None):
    payload = {"path": path} if path else {}
    return {
        "name": name,
        "status": "done",
        "inputJSON": json.dumps(payload),
        "outputJSON": json.dumps({"ok": True}),
    }


class PriorWaveCoworkEvalTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.rows = PRIOR.validate_catalog(PRIOR.read_json(PRIOR.CATALOG))

    def test_catalog_covers_every_prior_wave_task_once(self):
        self.assertEqual([row["id"] for row in self.rows], list(range(1, 211)))

    def test_prompts_preserve_original_task_and_require_native_evidence(self):
        for task_id in (1, 69, 111, 143, 148, 192, 207):
            row = self.rows[task_id - 1]
            prompt = PRIOR.build_prompt(row)
            self.assertTrue(prompt.startswith(row["task"]))
            if row["capabilityNeeded"] == "Scheduling":
                self.assertIn("Create and persist", prompt)
                self.assertNotIn("task-148-deliverable.md", prompt)
            else:
                self.assertIn("inputs/evaluation-context.md", prompt)
                self.assertIn(PRIOR.output_path(row), prompt)

    def test_requested_artifact_formats_are_not_collapsed_to_markdown(self):
        expected = {
            1: "csv",
            5: "pdf",
            19: "xlsx",
            20: "png",
            28: "mmd",
            40: "html",
            64: "docx",
            82: "html",
            143: "md",
        }
        for task_id, extension in expected.items():
            row = self.rows[task_id - 1]
            self.assertEqual(PRIOR.output_format(row), extension)
            self.assertTrue(PRIOR.output_path(row).endswith(f".{extension}"))
            self.assertIn(PRIOR.FORMAT_INSTRUCTIONS[extension], PRIOR.build_prompt(row))

    def test_browser_and_web_cases_have_distinct_evidence_classes(self):
        browser = self.rows[191]
        research = self.rows[110]
        self.assertEqual(
            PRIOR.evidence_class(browser),
            "native-app-synthetic-authenticated-browser",
        )
        self.assertEqual(
            PRIOR.evidence_class(research),
            "native-app-live-public-web",
        )

    def test_web_research_uses_live_native_tools_not_browser_fixture(self):
        row = self.rows[110]
        with tempfile.TemporaryDirectory() as temporary:
            browser_path = PRIOR.write_fixture(row, Path(temporary))
        self.assertIsNone(browser_path)
        prompt = PRIOR.build_prompt(row)
        self.assertIn("native web search and fetch tools", prompt)
        self.assertIn("live public sources", prompt)

    def test_fixture_materializes_referenced_rich_documents_and_source_map(self):
        row = self.rows[142]
        with tempfile.TemporaryDirectory() as temporary:
            workspace = Path(temporary)
            PRIOR.write_fixture(row, workspace)
            workbook = workspace / "inputs" / "kpi-dashboard.xlsx"
            source_map = workspace / "inputs" / "source-map.md"

            self.assertTrue(workbook.is_file())
            self.assertIn(
                "`kpi-dashboard.xlsx` -> `inputs/kpi-dashboard.xlsx`",
                source_map.read_text(encoding="utf-8"),
            )
            self.assertIn(
                "inputs/last-quarter-board-memo.md",
                source_map.read_text(encoding="utf-8"),
            )
            with zipfile.ZipFile(workbook) as archive:
                required = {
                    "[Content_Types].xml",
                    "_rels/.rels",
                    "xl/workbook.xml",
                    "xl/_rels/workbook.xml.rels",
                    "xl/worksheets/sheet1.xml",
                }
                self.assertTrue(required.issubset(archive.namelist()))
                ET.fromstring(archive.read("[Content_Types].xml"))
                sheet = archive.read("xl/worksheets/sheet1.xml").decode("utf-8")
                self.assertIn("Northstar open days", sheet)

    def test_contact_fixture_contains_real_cleanup_cases(self):
        with tempfile.TemporaryDirectory() as temporary:
            workspace = Path(temporary)
            PRIOR.write_fixture(self.rows[1], workspace)
            with (workspace / "inputs" / "contacts_export.csv").open(
                encoding="utf-8", newline=""
            ) as source:
                rows = list(csv.DictReader(source))

        self.assertEqual(len(rows), 12)
        self.assertEqual(
            set(rows[0]),
            {
                "contact_id", "name", "email", "phone", "opt_out", "job_title",
                "company", "last_activity", "next_step",
            },
        )
        self.assertLess(len({row["email"] for row in rows}), len(rows))
        self.assertTrue(any(row["name"].isupper() for row in rows))
        self.assertTrue(any(not row["phone"] for row in rows))
        self.assertTrue(any(row["opt_out"] == "yes" for row in rows))

    def test_budget_fixture_has_approved_annual_plan_and_exact_seasonality(self):
        table = PRIOR.task_table(self.rows[18])
        headers = table[0]
        budget_index = headers.index("annual_budget_usd")
        month_indexes = [headers.index(f"{month}_pct") for month in (
            "jan", "feb", "mar", "apr", "may", "jun",
            "jul", "aug", "sep", "oct", "nov", "dec",
        )]
        approval_index = headers.index("approval_status")

        self.assertEqual(sum(row[budget_index] for row in table[1:]), 120000)
        self.assertEqual(len(table) - 1, 6)
        for row in table[1:]:
            self.assertAlmostEqual(sum(row[index] for index in month_indexes), 1.0)
            self.assertEqual(row[approval_index], "approved by Rafael Ortiz")

    def test_task_tables_differentiate_source_roles(self):
        row = self.rows[93]
        plan_v3 = PRIOR.task_table(row, "plan-v3.csv")
        plan_v5 = PRIOR.task_table(row, "plan-v5.csv")
        self.assertEqual(plan_v3[0], plan_v5[0])
        self.assertNotEqual(plan_v3[1:], plan_v5[1:])
        self.assertIn("Slipped", {str(value) for values in plan_v5 for value in values})

    def test_fixture_materializes_implied_task_sources(self):
        with tempfile.TemporaryDirectory() as temporary:
            workspace = Path(temporary)
            PRIOR.write_fixture(self.rows[8], workspace)
            lease = workspace / "inputs" / "office-lease.pdf"
            source_map = (workspace / "inputs" / "source-map.md").read_text(encoding="utf-8")
            self.assertTrue(lease.read_bytes().startswith(b"%PDF"))
            self.assertIn("inputs/office-lease.pdf", source_map)

    def test_browser_fixture_exposes_task_relevant_table(self):
        with tempfile.TemporaryDirectory() as temporary:
            workspace = Path(temporary)
            browser_path = PRIOR.write_fixture(self.rows[192], workspace)
            page = (workspace / browser_path).read_text(encoding="utf-8")

        self.assertIn("invoice_id", page)
        self.assertIn("vendor", page)
        self.assertIn("due_date", page)

    def test_source_grounding_uses_mapped_collection_members(self):
        row = self.rows[0]
        with tempfile.TemporaryDirectory() as temporary:
            workspace = Path(temporary)
            PRIOR.write_fixture(row, workspace)
            artifact_text = (
                "filename,width,height,size,format,status,notes\n"
                + "\n".join(
                    f"item-{index:03d}.png,1200,600,2048,PNG,ok,verified"
                    for index in range(1, 9)
                )
            )
            matched = PRIOR.matched_source_grounding_anchors(row, workspace, artifact_text)

        self.assertGreaterEqual(len(matched), 2)
        self.assertIn("item 001", matched)
        self.assertNotIn("atlas", PRIOR.source_grounding_anchors(row, workspace))

    def test_source_grounding_rejects_task_words_without_source_facts(self):
        row = self.rows[0]
        with tempfile.TemporaryDirectory() as temporary:
            workspace = Path(temporary)
            PRIOR.write_fixture(row, workspace)
            matched = PRIOR.matched_source_grounding_anchors(
                row,
                workspace,
                "Inventory dimensions, size, format, and logo flags were reviewed.",
            )

        self.assertEqual(matched, [])

    def test_task_coverage_accepts_conservative_word_variants(self):
        row = self.rows[5]

        matched = PRIOR.matched_task_terms(
            row,
            "region,record_id,headline_revenue_usd\nitem-001,TASK-6-001,437000",
        )

        self.assertEqual(matched, ["regional", "headline"])

    def test_task_coverage_rejects_source_anchors_without_task_terms(self):
        row = self.rows[5]

        matched = PRIOR.matched_task_terms(
            row,
            "item-001,TASK-6-001,437000\nitem-002,TASK-6-002,511000",
        )

        self.assertEqual(matched, [])

    def test_mapped_collection_does_not_require_generic_records(self):
        row = self.rows[0]
        paths = PRIOR.required_source_paths(row)
        self.assertIn("inputs/Brand/Assets", paths)
        self.assertNotIn("inputs/records.csv", paths)
        prompt = PRIOR.build_prompt(row)
        self.assertIn("`inputs/Brand/Assets`", prompt)
        self.assertNotIn("`inputs/records.csv`", prompt)

    def test_task_without_concrete_sources_uses_records_fallback(self):
        row = next(
            candidate for candidate in self.rows
            if not PRIOR.source_references(candidate["task"])
            and candidate["id"] not in PRIOR.COLLECTION_SPECS
            and candidate["id"] not in PRIOR.IMPLICIT_SOURCES
            and candidate["capabilityNeeded"] != "Scheduling"
        )
        self.assertIn("inputs/records.csv", PRIOR.required_source_paths(row))
        with tempfile.TemporaryDirectory() as temporary:
            workspace = Path(temporary)
            PRIOR.write_fixture(row, workspace)
            source_map = (workspace / "inputs/source-map.md").read_text(encoding="utf-8")
        self.assertIn("inputs/records.csv", source_map)

    def test_office_fixtures_include_standard_package_relationships(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            docx = root / "source.docx"
            pptx = root / "source.pptx"
            PRIOR.write_docx(docx, "Verified source text")
            PRIOR.write_pptx(pptx, "Verified source text")

            with zipfile.ZipFile(docx) as archive:
                self.assertIn("[Content_Types].xml", archive.namelist())
                self.assertIn("_rels/.rels", archive.namelist())
                self.assertIn("word/document.xml", archive.namelist())
            with zipfile.ZipFile(pptx) as archive:
                self.assertIn("[Content_Types].xml", archive.namelist())
                self.assertIn("ppt/presentation.xml", archive.namelist())
                self.assertIn("ppt/_rels/presentation.xml.rels", archive.namelist())
                self.assertIn("ppt/slides/slide1.xml", archive.namelist())

    def test_artifact_validator_checks_real_formats(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            workbook = root / "output.xlsx"
            image = root / "output.png"
            fake_workbook = root / "fake.xlsx"
            PRIOR.write_xlsx(workbook)
            PRIOR.write_png(image, width=800, height=400)
            fake_workbook.write_text("not a workbook", encoding="utf-8")

            self.assertTrue(PRIOR.validate_artifact(workbook, "xlsx")[0])
            self.assertTrue(PRIOR.validate_artifact(image, "png")[0])
            self.assertFalse(PRIOR.validate_artifact(fake_workbook, "xlsx")[0])

    def test_collection_fixtures_materialize_declared_counts_and_valid_png(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            PRIOR.write_fixture(self.rows[97], root)
            self.assertEqual(len(list((root / "inputs" / "freight-invoices").glob("*.pdf"))), 200)

        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            PRIOR.write_fixture(self.rows[0], root)
            assets = list((root / "inputs" / "Brand" / "Assets").glob("*.png"))
            self.assertEqual(len(assets), 8)
            self.assertTrue(all(path.read_bytes().startswith(b"\x89PNG\r\n\x1a\n") for path in assets))

    def test_archive_fixture_has_matching_old_and_current_modification_dates(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            PRIOR.write_fixture(self.rows[16], root)
            sources = sorted((root / "inputs" / "Client Files").glob("*.txt"))

            modified = [
                datetime.fromtimestamp(path.stat().st_mtime, tz=timezone.utc)
                for path in sources
            ]
            contents = [path.read_text(encoding="utf-8") for path in sources]

        self.assertEqual(len(sources), 8)
        self.assertEqual(sum(value.year < 2025 for value in modified), 6)
        self.assertEqual(sum(value.year >= 2025 for value in modified), 2)
        for value, content in zip(modified, contents):
            self.assertIn(f"Modified date: {value.date().isoformat()} UTC", content)
            expected = "Required disposition: archive" if value.year < 2025 else "Required disposition: keep"
            self.assertIn(expected, content)

    def test_document_packet_fixture_has_concrete_agenda_order(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            PRIOR.write_fixture(self.rows[4], root)
            agenda = (root / "inputs" / "agenda.txt").read_text(encoding="utf-8").splitlines()
            self.assertEqual(
                agenda,
                ["item-003.docx", "item-001.docx", "item-005.docx", "item-002.docx", "item-004.docx"],
            )
            self.assertEqual(
                set(agenda),
                {path.name for path in (root / "inputs" / "Board" / "July").glob("*.docx")},
            )

    def test_source_reference_extraction_keeps_workspace_relative_paths(self):
        references = PRIOR.source_references(
            "Read ~/Board/July/deck.pptx, budget.xlsx, and /notes/source.md."
        )
        self.assertEqual(
            references,
            ["Board/July/deck.pptx", "budget.xlsx", "notes/source.md"],
        )

    def test_confidential_grade_requires_real_confidential_route(self):
        row = self.rows[142]
        with tempfile.TemporaryDirectory() as temporary:
            workspace = Path(temporary)
            PRIOR.write_fixture(row, workspace)
            artifact = workspace / PRIOR.output_path(row)
            artifact.parent.mkdir(parents=True)
            artifact.write_text(
                "# Atlas board memo\n\n"
                + "Priya and Rafael will review Northstar evidence in 2026.\n" * 20,
                encoding="utf-8",
            )
            report = {
                "ok": True,
                "isConfidential": True,
                "requestedModelID": "trustedrouter/e2e",
                "selectedModelID": "trustedrouter/e2e",
                "screenshot": None,
                "tools": [
                    tool("host.file.read", "inputs/source-map.md"),
                    tool("host.file.read", "inputs/evaluation-context.md"),
                    tool("host.file.read", "inputs/records.csv"),
                    tool("host.file.read", "inputs/kpi-dashboard.xlsx"),
                    tool("host.file.read", "inputs/last-quarter-board-memo.md"),
                    tool("host.file.write", PRIOR.output_path(row)),
                    tool("host.file.read", PRIOR.output_path(row)),
                ],
            }
            hashes = {path: PRIOR.sha256(path) for path in (workspace / "inputs").iterdir()}
            checks, _ = PRIOR.grade(row, workspace, report, hashes)
        by_name = {check["name"]: check["passed"] for check in checks}
        self.assertTrue(by_name["confidential mode"])
        self.assertTrue(by_name["confidential route pinned"])
        self.assertTrue(by_name["mapped source consumption"])

    def test_grade_accepts_successful_shell_consumption_of_mapped_source(self):
        row = self.rows[142]
        with tempfile.TemporaryDirectory() as temporary:
            workspace = Path(temporary)
            PRIOR.write_fixture(row, workspace)
            artifact = workspace / PRIOR.output_path(row)
            artifact.parent.mkdir(parents=True)
            artifact.write_text(
                "# Atlas board memo\n\n"
                + "Priya and Rafael will review Northstar evidence in 2026.\n" * 20,
                encoding="utf-8",
            )
            shell = tool("host.shell.run")
            shell["inputJSON"] = json.dumps({
                "cmd": (
                    "inspect inputs/kpi-dashboard.xlsx and "
                    "inputs/last-quarter-board-memo.md"
                )
            })
            report = {
                "ok": True,
                "isConfidential": True,
                "requestedModelID": "trustedrouter/e2e",
                "selectedModelID": "trustedrouter/e2e",
                "screenshot": None,
                "tools": [
                    tool("host.file.read", "inputs/source-map.md"),
                    tool("host.file.read", "inputs/evaluation-context.md"),
                    tool("host.file.read", "inputs/records.csv"),
                    shell,
                    tool("host.file.write", PRIOR.output_path(row)),
                    tool("host.file.read", PRIOR.output_path(row)),
                ],
            }
            hashes = {path: PRIOR.sha256(path) for path in (workspace / "inputs").iterdir() if path.is_file()}
            checks, _ = PRIOR.grade(row, workspace, report, hashes)
        by_name = {check["name"]: check["passed"] for check in checks}
        self.assertTrue(by_name["mapped source consumption"])

    def test_grade_accepts_shell_quoted_collection_path_with_spaces(self):
        row = self.rows[16]
        with tempfile.TemporaryDirectory() as temporary:
            workspace = Path(temporary)
            PRIOR.write_fixture(row, workspace)
            artifact = workspace / PRIOR.output_path(row)
            artifact.parent.mkdir(parents=True)
            artifact.write_text(
                "# Client Files archive\n\n"
                + "\n".join(
                    f"- item-{index:03d}.txt -> 2024-Q{((index - 1) % 4) + 1}"
                    for index in range(1, 9)
                )
                + "\n\nArchive README records modified dates and quarterly folders.\n" * 10,
                encoding="utf-8",
            )
            shell = tool("host.shell.run")
            shell["inputJSON"] = json.dumps({
                "cmd": 'for f in inputs/"Client Files"/*.txt; do cat "$f"; done'
            })
            report = {
                "ok": True,
                "requestedModelID": PRIOR.EXACT_MODEL,
                "selectedModelID": PRIOR.EXACT_MODEL,
                "tools": [
                    tool("host.file.read", "inputs/source-map.md"),
                    tool("host.file.read", "inputs/evaluation-context.md"),
                    shell,
                    tool("host.file.write", PRIOR.output_path(row)),
                    tool("host.file.read", PRIOR.output_path(row)),
                ],
            }
            hashes = {
                path: PRIOR.sha256(path)
                for path in workspace.rglob("*") if path.is_file() and path != artifact
            }
            checks, _ = PRIOR.grade(row, workspace, report, hashes)

        by_name = {check["name"]: check["passed"] for check in checks}
        self.assertTrue(by_name["mapped source consumption"])

    def test_grade_accepts_successful_shell_artifact_readback(self):
        row = self.rows[18]
        with tempfile.TemporaryDirectory() as temporary:
            workspace = Path(temporary)
            PRIOR.write_fixture(row, workspace)
            artifact = workspace / PRIOR.output_path(row)
            PRIOR.write_xlsx(artifact, ["marketing", "budget", "monthly", "spend"])

            creation = tool("host.shell.run")
            creation["inputJSON"] = json.dumps({"cmd": "python3 build_budget.py"})
            creation["outputJSON"] = json.dumps({
                "ok": True,
                "stdout": f"saved {PRIOR.output_path(row)}\n",
            })
            inspection = tool("host.shell.run")
            inspection["inputJSON"] = json.dumps({
                "cmd": (
                    "python3 -c \"import openpyxl; "
                    f"print(openpyxl.load_workbook('{PRIOR.output_path(row)}').sheetnames)\""
                )
            })
            inspection["outputJSON"] = json.dumps({"ok": True, "stdout": "['Sheet1']\n"})
            report = {
                "ok": True,
                "requestedModelID": PRIOR.EXACT_MODEL,
                "selectedModelID": PRIOR.EXACT_MODEL,
                "tools": [
                    tool("host.file.read", "inputs/source-map.md"),
                    tool("host.file.read", "inputs/evaluation-context.md"),
                    tool("host.file.read", "inputs/records.csv"),
                    creation,
                    inspection,
                ],
            }
            hashes = {
                path: PRIOR.sha256(path)
                for path in workspace.rglob("*") if path.is_file() and path != artifact
            }
            checks, _ = PRIOR.grade(row, workspace, report, hashes)

        by_name = {check["name"]: check["passed"] for check in checks}
        self.assertTrue(by_name["artifact write"])
        self.assertTrue(by_name["artifact verification"])
        self.assertFalse(PRIOR.shell_command_inspects_path("python3 build_budget.py", PRIOR.output_path(row)))
        self.assertFalse(PRIOR.shell_command_inspects_path(
            f"wb = openpyxl.Workbook(); wb.save('{PRIOR.output_path(row)}')",
            PRIOR.output_path(row),
        ))

    def test_grade_accepts_native_pdf_merge_as_consumption_and_artifact_write(self):
        row = self.rows[4]
        with tempfile.TemporaryDirectory() as temporary:
            workspace = Path(temporary)
            PRIOR.write_fixture(row, workspace)
            artifact = workspace / PRIOR.output_path(row)
            PRIOR.write_pdf(artifact, "Board packet table of contents and ordered source pages")
            input_paths = [
                f"inputs/Board/July/{name}"
                for name in (workspace / "inputs" / "agenda.txt").read_text(encoding="utf-8").splitlines()
            ]
            merge = tool("host.pdf.merge")
            merge["inputJSON"] = json.dumps({
                "inputs": input_paths,
                "output": PRIOR.output_path(row),
            })
            report = {
                "ok": True,
                "requestedModelID": PRIOR.EXACT_MODEL,
                "selectedModelID": PRIOR.EXACT_MODEL,
                "tools": [
                    tool("host.file.read", "inputs/source-map.md"),
                    tool("host.file.read", "inputs/evaluation-context.md"),
                    tool("host.file.read", "inputs/records.csv"),
                    tool("host.file.read", "inputs/agenda.txt"),
                    merge,
                    tool("host.file.read", PRIOR.output_path(row)),
                ],
            }
            hashes = {
                path: PRIOR.sha256(path)
                for path in workspace.rglob("*") if path.is_file() and path != artifact
            }
            checks, _ = PRIOR.grade(row, workspace, report, hashes)
        by_name = {check["name"]: check["passed"] for check in checks}
        self.assertTrue(by_name["mapped source consumption"])
        self.assertTrue(by_name["artifact write"])

    def test_grade_rejects_template_placeholders(self):
        row = self.rows[0]
        with tempfile.TemporaryDirectory() as temporary:
            workspace = Path(temporary)
            PRIOR.write_fixture(row, workspace)
            artifact = workspace / PRIOR.output_path(row)
            artifact.parent.mkdir(parents=True)
            artifact.write_text(
                "# Atlas result\n\n[Your Name] owns the Northstar review in 2026.\n" * 20,
                encoding="utf-8",
            )
            report = {
                "ok": True,
                "requestedModelID": PRIOR.EXACT_MODEL,
                "selectedModelID": PRIOR.EXACT_MODEL,
                "tools": [
                    tool("host.file.read", "inputs/evaluation-context.md"),
                    tool("host.file.read", "inputs/records.csv"),
                    tool("host.file.write", PRIOR.output_path(row)),
                    tool("host.file.read", PRIOR.output_path(row)),
                ],
            }
            hashes = {path: PRIOR.sha256(path) for path in workspace.rglob("*") if path.is_file()}
            checks, _ = PRIOR.grade(row, workspace, report, hashes)
        placeholder = next(check for check in checks if check["name"] == "no template placeholders")
        self.assertFalse(placeholder["passed"])

    def test_schedule_grade_requires_persisted_automation(self):
        row = self.rows[147]
        report = {
            "ok": True,
            "isConfidential": False,
            "requestedModelID": PRIOR.EXACT_MODEL,
            "selectedModelID": PRIOR.EXACT_MODEL,
            "screenshot": None,
            "scheduledAutomation": {"id": "automation-id", "status": "active"},
        }
        checks, artifact = PRIOR.grade(row, Path("/tmp/unused"), report, {})
        self.assertIsNone(artifact)
        self.assertTrue(next(check for check in checks if check["name"] == "persisted automation")["passed"])


if __name__ == "__main__":
    unittest.main()
