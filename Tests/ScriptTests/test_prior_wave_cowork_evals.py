import importlib.util
import csv
import json
import tempfile
import unittest
from unittest import mock
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


def write_budget_workbook(path, circular=False, broken_reference=False):
    channels = (
        ("Paid Search", 30000),
        ("Paid Social", 24000),
        ("Content and SEO", 18000),
        ("Events and Webinars", 18000),
        ("Lifecycle Email", 15000),
        ("Partner and ABM", 15000),
    )
    months = ("Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec")

    def column_name(number):
        name = ""
        while number:
            number, remainder = divmod(number - 1, 26)
            name = chr(ord("A") + remainder) + name
        return name

    def worksheet_xml(rows):
        root = ET.Element("worksheet", xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main")
        sheet_data = ET.SubElement(root, "sheetData")
        for row_number, row_values in enumerate(rows, start=1):
            row = ET.SubElement(sheet_data, "row", r=str(row_number))
            for column_number, (kind, value) in enumerate(row_values, start=1):
                reference = f"{column_name(column_number)}{row_number}"
                if kind == "string":
                    cell = ET.SubElement(row, "c", r=reference, t="inlineStr")
                    inline = ET.SubElement(cell, "is")
                    ET.SubElement(inline, "t").text = str(value)
                elif kind == "number":
                    cell = ET.SubElement(row, "c", r=reference)
                    ET.SubElement(cell, "v").text = str(value)
                else:
                    cell = ET.SubElement(row, "c", r=reference)
                    ET.SubElement(cell, "f").text = value
        return ET.tostring(root, encoding="utf-8", xml_declaration=True)

    assumptions = [[("string", "Channel"), ("string", "Annual budget")]]
    assumptions.extend([[("string", channel), ("number", budget)] for channel, budget in channels])
    monthly = [[("string", "Channel"), *(("string", month) for month in months)]]
    for row_number, (channel, _) in enumerate(channels, start=2):
        monthly.append([
            ("string", channel),
            *(("formula", f"'Assumptions'!B{row_number}/12") for _ in months),
        ])
    quarterly = [[("string", "Channel"), *(("string", quarter) for quarter in ("Q1", "Q2", "Q3", "Q4"))]]
    for row_number, (channel, _) in enumerate(channels, start=2):
        formulas = [
            f"SUM('Monthly Spend'!B{row_number}:D{row_number})",
            f"SUM('Monthly Spend'!E{row_number}:G{row_number})",
            f"SUM('Monthly Spend'!H{row_number}:J{row_number})",
            f"SUM('Monthly Spend'!K{row_number}:M{row_number})",
        ]
        if circular and row_number == 2:
            formulas[0] = "SUM(B2:D2)"
        if broken_reference and row_number == 2:
            formulas[0] = "SUM('Monthly Spend'!Z99:Z100)"
        quarterly.append([("string", channel), *(("formula", formula) for formula in formulas)])

    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as archive:
        archive.writestr(
            "[Content_Types].xml",
            """<?xml version="1.0" encoding="UTF-8"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
  <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
  <Override PartName="/xl/worksheets/sheet2.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
  <Override PartName="/xl/worksheets/sheet3.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
</Types>""",
        )
        archive.writestr(
            "_rels/.rels",
            """<?xml version="1.0" encoding="UTF-8"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
</Relationships>""",
        )
        archive.writestr(
            "xl/workbook.xml",
            """<?xml version="1.0" encoding="UTF-8"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <sheets>
    <sheet name="Assumptions" sheetId="1" r:id="rId1"/>
    <sheet name="Monthly Spend" sheetId="2" r:id="rId2"/>
    <sheet name="Quarterly Roll-up" sheetId="3" r:id="rId3"/>
  </sheets>
</workbook>""",
        )
        archive.writestr(
            "xl/_rels/workbook.xml.rels",
            """<?xml version="1.0" encoding="UTF-8"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
  <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet2.xml"/>
  <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet3.xml"/>
</Relationships>""",
        )
        archive.writestr("xl/worksheets/sheet1.xml", worksheet_xml(assumptions))
        archive.writestr("xl/worksheets/sheet2.xml", worksheet_xml(monthly))
        archive.writestr("xl/worksheets/sheet3.xml", worksheet_xml(quarterly))


class PriorWaveCoworkEvalTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.rows = PRIOR.validate_catalog(PRIOR.read_json(PRIOR.CATALOG))

    def test_catalog_covers_every_prior_wave_task_once(self):
        self.assertEqual([row["id"] for row in self.rows], list(range(1, 211)))

    def test_serial_runner_does_not_launch_queued_cases_after_interrupt(self):
        with tempfile.TemporaryDirectory() as temporary:
            with mock.patch.object(PRIOR, "run_case", side_effect=KeyboardInterrupt) as run_case:
                with self.assertRaises(KeyboardInterrupt):
                    PRIOR.run_cases_serially(
                        Path("/tmp/quill-cowork"),
                        self.rows[:3],
                        Path(temporary),
                        "test-key",
                        900,
                        False,
                    )

        self.assertEqual(run_case.call_count, 1)

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
            117: "html",
            143: "md",
        }
        for task_id, extension in expected.items():
            row = self.rows[task_id - 1]
            self.assertEqual(PRIOR.output_format(row), extension)
            self.assertTrue(PRIOR.output_path(row).endswith(f".{extension}"))
            self.assertIn(PRIOR.FORMAT_INSTRUCTIONS[extension], PRIOR.build_prompt(row))

    def test_workbook_prompt_requires_formula_dependency_verification(self):
        instruction = PRIOR.FORMAT_INSTRUCTIONS["xlsx"]

        self.assertIn("inspect every formula dependency", instruction)
        self.assertIn("quote sheet names", instruction)
        self.assertIn("circular references", instruction)

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

    def test_follow_up_fixture_contains_distinct_booth_notes(self):
        row = self.rows[32]
        with tempfile.TemporaryDirectory() as temporary:
            workspace = Path(temporary)
            PRIOR.write_fixture(row, workspace)
            with (workspace / "inputs" / "conference-leads.csv").open(
                encoding="utf-8", newline=""
            ) as source:
                prospects = list(csv.DictReader(source))

        self.assertEqual(len(prospects), 6)
        self.assertIn("booth-notes", prospects[0])
        self.assertEqual(len({prospect["booth-notes"] for prospect in prospects}), 6)
        self.assertTrue(all(prospect["first_name"] for prospect in prospects))

    def test_follow_up_prompt_requires_complete_per_prospect_sequences(self):
        prompt = PRIOR.build_prompt(self.rows[32])

        self.assertIn("exactly three fully written emails for each of the six prospects", prompt)
        self.assertIn("18 emails total", prompt)
        self.assertIn("Do not provide reusable templates", prompt)
        self.assertIn("Treat every email as draft copy", prompt)
        self.assertIn("Do not promise unsupported turnaround times", prompt)
        self.assertIn("Do not add defensive statements that those items are not prepared", prompt)
        self.assertIn("use neutral conditional language", prompt)
        self.assertIn("exactly the `first_name` field", prompt)
        self.assertIn("Do not infer or add surnames", prompt)
        self.assertIn("complete sender-neutral closing", prompt)
        self.assertIn("commentary about a blank or future signature", prompt)
        self.assertIn("Omit unrelated company finance and operating context", prompt)

    def test_prompt_keeps_completion_details_scoped_to_the_original_task(self):
        prompt = PRIOR.build_prompt(self.rows[32])

        self.assertIn("only that requested side effect", prompt)
        self.assertIn("Do not invent or claim actions, commitments", prompt)
        self.assertIn("that are material to the original task", prompt)
        self.assertIn("Omit unrelated context-packet facts", prompt)
        self.assertIn("add an action log unless the original task requests", prompt)
        self.assertNotIn("Represent requested\nrenames, deletions, messages", prompt)

    def test_currency_normalization_fixture_defines_month_and_currency(self):
        row = self.rows[120]
        with tempfile.TemporaryDirectory() as temporary:
            workspace = Path(temporary)
            PRIOR.write_fixture(row, workspace)
            with (workspace / "inputs" / "revenue_by_region.csv").open(
                encoding="utf-8", newline=""
            ) as source:
                revenue = list(csv.DictReader(source))

        self.assertEqual(
            set(revenue[0]),
            {"region", "currency", "month", "local_revenue"},
        )
        self.assertEqual({item["currency"] for item in revenue}, {"EUR", "GBP", "JPY"})
        self.assertEqual({item["month"] for item in revenue}, {"2026-05", "2026-06", "2026-07"})
        self.assertTrue(all(int(item["local_revenue"]) > 0 for item in revenue))

        prompt = PRIOR.build_prompt(row)
        self.assertIn("USD per one unit of local currency", prompt)
        self.assertIn("final published business-day observation", prompt)
        self.assertIn("Apply the rate at row level", prompt)

    def test_competitor_revenue_fixture_and_prompt_define_a_solvable_chart(self):
        row = self.rows[116]
        with tempfile.TemporaryDirectory() as temporary:
            workspace = Path(temporary)
            PRIOR.write_fixture(row, workspace)
            competitors = (workspace / "inputs" / "named-competitors.md").read_text(
                encoding="utf-8"
            )

        self.assertIn("Asana, Inc. (NYSE: ASAN)", competitors)
        self.assertIn("monday.com Ltd. (NASDAQ: MNDY)", competitors)
        self.assertIn("GitLab Inc. (NASDAQ: GTLB)", competitors)
        self.assertIn("inputs/named-competitors.md", PRIOR.required_source_paths(row))

        prompt = PRIOR.build_prompt(row)
        self.assertIn("Use exactly Asana, Inc., monday.com Ltd., and GitLab Inc.", prompt)
        self.assertIn("all four raw numeric USD quarterly values in the same `<tr>`", prompt)
        self.assertIn("first five cells in every company row", prompt)
        self.assertIn("full integer USD amount", prompt)
        self.assertIn("never an M/B abbreviation", prompt)
        self.assertIn("Do not split a company across quarter rows or use rowspans", prompt)
        self.assertIn("inline SVG chart or a functional canvas chart", prompt)
        self.assertIn("source URL in that same row for every competitor", prompt)
        self.assertIn("focused query containing the company, fiscal quarters, and revenue", prompt)
        self.assertIn("one results-history or annual-report page per company", prompt)
        self.assertIn("remove checkpoint, progress, or future-tense completion language", prompt)

    def test_travel_policy_fixture_materializes_source_and_reimbursement_checks(self):
        row = self.rows[124]
        with tempfile.TemporaryDirectory() as temporary:
            workspace = Path(temporary)
            PRIOR.write_fixture(row, workspace)
            policy = (workspace / "inputs" / "current-travel-policy.md").read_text(
                encoding="utf-8"
            )
            with (workspace / "inputs" / "records.csv").open(
                encoding="utf-8", newline=""
            ) as source:
                claims = list(csv.DictReader(source))
            source_map = (workspace / "inputs" / "source-map.md").read_text(
                encoding="utf-8"
            )

        self.assertIn("Policy version: 3.2", policy)
        self.assertIn("$0.70 per business mile", policy)
        self.assertIn("up to $65 per", policy)
        self.assertEqual(len(claims), 5)
        self.assertEqual(claims[1]["expected_updated_mileage_reimbursement_usd"], "60.90")
        self.assertEqual(claims[1]["expected_updated_meal_reimbursement_usd"], "75.00")
        self.assertEqual(claims[2]["review_note"], "pre-effective-date claim")
        self.assertIn("inputs/current-travel-policy.md", source_map)
        self.assertIn("inputs/records.csv", source_map)
        self.assertIn("inputs/current-travel-policy.md", PRIOR.required_source_paths(row))
        self.assertIn("inputs/records.csv", PRIOR.required_source_paths(row))

        prompt = PRIOR.build_prompt(row)
        self.assertIn("official IRS source", prompt)
        self.assertIn("effective 2026-01-01", prompt)
        self.assertIn("preserve every unaffected provision", prompt)
        self.assertIn("Do not call the company meal cap a GSA or IRS rate", prompt)
        self.assertIn("all five claims", prompt)

    def test_travel_policy_allows_one_authoritative_external_citation(self):
        self.assertEqual(PRIOR.minimum_source_citation_count(self.rows[124]), 1)
        self.assertEqual(PRIOR.minimum_source_citation_count(self.rows[123]), 2)

    def test_real_revenue_fixture_and_prompt_define_cpi_basis(self):
        row = self.rows[125]
        self.assertEqual(
            PRIOR.task_table(row),
            [
                ("fiscal_year", "nominal_revenue_usd", "reporting_basis", "status"),
                (2023, 4200000, "calendar-year recognized revenue", "audited"),
                (2024, 5100000, "calendar-year recognized revenue", "audited"),
                (2025, 6000000, "calendar-year recognized revenue", "audited"),
            ],
        )
        prompt = PRIOR.build_prompt(row)
        self.assertIn("CUUR0000SA0", prompt)
        self.assertIn("annual-average indexes for 2023", prompt)
        self.assertIn("observed-month proxy, never an annual average", prompt)
        self.assertIn("Do not invent a 2025 missing-month value", prompt)
        self.assertIn("latest published monthly 2026 index", prompt)
        self.assertIn("Do not invent a full-year 2026 CPI value", prompt)
        self.assertIn("Prefix every nominal and rounded real-revenue amount with `$`", prompt)
        self.assertIn("deterministic post-write validator", prompt)
        self.assertIn("rejects any repeated dollar amount", prompt)
        self.assertIn("parse a decimal dollar amount as one complete value", prompt)
        self.assertIn("validator itself is wrong", prompt)
        self.assertEqual(PRIOR.minimum_source_citation_count(row), 1)

    def test_real_revenue_semantics_require_bls_basis_and_adjusted_values(self):
        artifact = """# Real revenue in 2026 dollars

Official BLS CPI-U series CUUR0000SA0 is not seasonally adjusted. The 2023 (304.701583)
and 2024 (313.688833) inputs are annual-average indexes. The BLS 2025 annual average is not
published because October is unavailable, so 321.943 is an 11-observation
observed-month proxy. The latest monthly 2026 index is the June benchmark, not
a completed annual average. Its value is 333.952.
Source: https://www.bls.gov/cpi/data.htm

2023 CPI basis: 304.701583
2024 CPI basis: 313.688833
2025 CPI basis: 321.943
2026 CPI benchmark: 333.952

Real revenue = nominal revenue x (latest 2026 CPI / selected CPI basis index).

| Year | Nominal revenue | Real revenue | Nominal YoY | Real YoY |
| --- | ---: | ---: | ---: | ---: |
| 2023 | $4,200,000 | $4,603,187 | n/a | n/a |
| 2024 | $5,100,000 | $5,429,442 | 21.43% | 17.95% |
| 2025 | $6,000,000 | $6,223,810 | 17.65% | 14.63% |

Cumulative 2023 to 2025 growth: nominal 42.86%; real 35.21%.
General price inflation is roughly 9.6% over the selected CPI basis window.
"""
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "result.md"
            path.write_text(artifact, encoding="utf-8")
            valid, detail = PRIOR.validate_task_126_real_revenue(path)
            self.assertTrue(valid, detail)

            structured_basis_with_monthly_equations = """# Real revenue in 2026 dollars

Official BLS CPI-U series CUUR0000SA0 is not seasonally adjusted. The 2023 and 2024
inputs are annual-average indexes. The 2025 basis is an 11-observation observed-month
mean, not an annual average, because October is unavailable.
The latest monthly 2026 index is the June benchmark, not a completed annual average.
Source: https://www.bls.gov/cpi/data.htm

| Year | CPI basis (index) | Basis type |
| --- | ---: | --- |
| 2023 | 304.702 | Annual average |
| 2024 | 313.689 | Annual average |
| 2025 | 321.943 | Observed-month mean |
| 2026 (benchmark) | 333.952 | June monthly index |

(299.170 + 300.840 + 301.836 + 303.363 + 304.127 + 305.109 + 305.691 +
307.026 + 307.789 + 307.671 + 307.051 + 306.746) / 12 = 304.702 for 2023.
(308.417 + 310.326 + 312.332 + 313.548 + 314.069 + 314.175 + 314.540 +
314.796 + 315.301 + 315.664 + 315.493 + 315.605) / 12 = 313.689 for 2024.

Real revenue = nominal revenue x (latest 2026 CPI / selected CPI basis index).

| Year | Nominal revenue | Real revenue | Nominal YoY | Real YoY |
| --- | ---: | ---: | ---: | ---: |
| 2023 | $4,200,000 | $4,603,181 | n/a | n/a |
| 2024 | $5,100,000 | $5,429,439 | 21.4% | 17.9% |
| 2025 | $6,000,000 | $6,223,810 | 17.6% | 14.6% |

Cumulative 2023 to 2025 growth: nominal 42.9%; real 35.2%.
"""
            path.write_text(structured_basis_with_monthly_equations, encoding="utf-8")
            valid, detail = PRIOR.validate_task_126_real_revenue(path)
            self.assertTrue(valid, detail)

            does_not_publish_language = structured_basis_with_monthly_equations.replace(
                "The 2025 basis is an 11-observation observed-month\n"
                "mean, not an annual average, because October is unavailable.",
                "**2025:** BLS does **not** publish a calendar-year annual average because "
                "October is unavailable. The 11-observation mean is **not a full annual "
                "average**.",
            )
            path.write_text(does_not_publish_language, encoding="utf-8")
            valid, detail = PRIOR.validate_task_126_real_revenue(path)
            self.assertTrue(valid, detail)

            wrong_latest_period = structured_basis_with_monthly_equations.replace(
                "June benchmark", "July benchmark"
            ).replace(
                "June monthly index", "July monthly index"
            )
            path.write_text(wrong_latest_period, encoding="utf-8")
            valid, detail = PRIOR.validate_task_126_real_revenue(path)
            self.assertFalse(valid)
            self.assertIn("latest 2026 benchmark is June", detail)

            wrong_source_basis = artifact.replace(
                "304.701583", "306.996"
            ).replace(
                "313.688833", "315.233"
            ).replace(
                "321.943", "324.000"
            )
            path.write_text(wrong_source_basis, encoding="utf-8")
            valid, detail = PRIOR.validate_task_126_real_revenue(path)
            self.assertFalse(valid)
            self.assertIn("source-correct CPI values", detail)
            self.assertIn("source CPI mismatches", detail)

            full_precision_audit = artifact.replace(
                "2023 CPI basis: 304.701583\n"
                "2024 CPI basis: 313.688833",
                "2023 CPI basis: 304.702 (annual average, full precision 304.701583)\n"
                "2024 CPI basis: 313.689 (annual average, full precision 313.688833)",
            ).replace(
                "The BLS 2025 annual average is not\n"
                "published because October is unavailable, so 321.943 is an 11-observation\n"
                "observed-month proxy.",
                "The 2025 deflator is an observed-month proxy, not a BLS annual average, "
                "because October is unavailable. Observation count = 11.",
            ) + (
                "\nAudit trail: $4,603,187.11 -> $4,603,187; "
                "$5,429,441.60 -> $5,429,442; "
                "$6,223,809.80 -> $6,223,810.\n"
            )
            path.write_text(full_precision_audit, encoding="utf-8")
            valid, detail = PRIOR.validate_task_126_real_revenue(path)
            self.assertTrue(valid, detail)

            production_precision_audit = artifact.replace(
                "2023 CPI basis: 304.701583\n"
                "2024 CPI basis: 313.688833",
                "2023 CPI basis: 304.7015833333333333333333333333333333333\n"
                "2024 CPI basis: 313.6888333333333333333333333333333333333",
            ).replace(
                "The BLS 2025 annual average is not\n"
                "published because October is unavailable, so 321.943 is an 11-observation\n"
                "observed-month proxy.",
                "2025: The API returned no M13 (calendar-year annual average). "
                "October is unavailable, so the mean of the 11 published months is a 2025 "
                "observed-month proxy.",
            )
            path.write_text(production_precision_audit, encoding="utf-8")
            valid, detail = PRIOR.validate_task_126_real_revenue(path)
            self.assertTrue(valid, detail)

            labeled_inline_bases = production_precision_audit.replace(
                "# Real revenue in 2026 dollars",
                "# Real revenue in 2026-dollar terms",
            ) + (
                "\nCPI basis used for deflation (full precision): "
                "2026 benchmark = 333.952; 2023 basis = 304.7015833333333333333333333333333333333; "
                "2024 basis = 313.6888333333333333333333333333333333333; "
                "2025 basis = 321.943.\n"
            )
            path.write_text(labeled_inline_bases, encoding="utf-8")
            valid, detail = PRIOR.validate_task_126_real_revenue(path)
            self.assertTrue(valid, detail)
            self.assertIn("2026: Decimal('333.952')", detail)

            delta_summary_and_audit_table = artifact.replace(
                "Cumulative 2023 to 2025 growth: nominal 42.86%; real 35.21%.",
                "From 2023 to 2025, nominal revenue rose by a cumulative "
                "$1,800,000 (42.86%) increase; "
                "real revenue rose by a cumulative $1,620,623 (35.21%) increase.",
            ) + (
                "\n| Year | Nominal ($) | Ratio | = Real revenue (full precision) | Rounded |\n"
                "| --- | ---: | ---: | ---: | ---: |\n"
                "| 2023 | 4,200,000 | 1.0959969303 | 4,603,187.107386 | $4,603,187 |\n"
            )
            path.write_text(delta_summary_and_audit_table, encoding="utf-8")
            valid, detail = PRIOR.validate_task_126_real_revenue(path)
            self.assertTrue(valid, detail)

            rounded_summary = artifact.replace(
                "The BLS 2025 annual average is not\npublished because October is unavailable, so 321.943 is an 11-observation\nobserved-month proxy.",
                "The 2025 basis is an 11-observation observed-month proxy, NOT an annual average,\n"
                "because October is unavailable.",
            ) + "\nApproximate headline: real growth ~35% versus nominal growth ~43%.\n"
            path.write_text(rounded_summary, encoding="utf-8")
            valid, detail = PRIOR.validate_task_126_real_revenue(path)
            self.assertTrue(valid, detail)

            contradictory = artifact + "\n- 2023 real revenue: $4,603,314\n"
            path.write_text(contradictory, encoding="utf-8")
            valid, detail = PRIOR.validate_task_126_real_revenue(path)
            self.assertFalse(valid)
            self.assertIn("internally consistent dollar calculations", detail)
            self.assertIn("4603314", detail)

            contradictory_growth = artifact + "\n- Cumulative real growth: 99%\n"
            path.write_text(contradictory_growth, encoding="utf-8")
            valid, detail = PRIOR.validate_task_126_real_revenue(path)
            self.assertFalse(valid)
            self.assertIn("internally consistent growth calculations", detail)
            self.assertIn("99", detail)

            path.write_text(artifact.replace("CUUR0000SA0", "unknown series"), encoding="utf-8")
            valid, detail = PRIOR.validate_task_126_real_revenue(path)
            self.assertFalse(valid)
            self.assertIn("series", detail)

            mislabeled = artifact.replace(
                "an 11-observation\nobserved-month proxy",
                "an annual average (11 months, October missing)",
            )
            path.write_text(mislabeled, encoding="utf-8")
            valid, detail = PRIOR.validate_task_126_real_revenue(path)
            self.assertFalse(valid)
            self.assertIn("2025 basis is not mislabeled", detail)

            duplicate_header = artifact.replace(
                "| Year | Nominal revenue | Real revenue | Nominal YoY | Real YoY |",
                "| Year | Nominal revenue | Real revenue | Nominal YoY | Real YoY |\n"
                "| Year | Nominal revenue | Real revenue | Nominal YoY | Real YoY |",
            )
            path.write_text(duplicate_header, encoding="utf-8")
            valid, detail = PRIOR.validate_task_126_real_revenue(path)
            self.assertFalse(valid)
            self.assertIn("one well-formed revenue table", detail)

            malformed_secondary_table = artifact + (
                "\n| Item | Status |\n"
                "| 2025 CPI | Observed-month proxy |\n"
            )
            path.write_text(malformed_secondary_table, encoding="utf-8")
            valid, detail = PRIOR.validate_task_126_real_revenue(path)
            self.assertFalse(valid)
            self.assertIn("all Markdown tables are well formed", detail)

    def test_reusable_macro_prompt_allows_only_documented_runtime_fields(self):
        prompt = PRIOR.build_prompt(self.rows[59])

        self.assertIn("named bracketed runtime fields", prompt)
        self.assertIn("Document every runtime field", prompt)
        self.assertIn("generic TBD, TODO, insert, or unscoped placeholders", prompt)

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

    def test_task_42_fixture_preserves_translatable_safety_structure(self):
        with tempfile.TemporaryDirectory() as temporary:
            workspace = Path(temporary)
            PRIOR.write_fixture(self.rows[41], workspace)
            source = (workspace / "inputs/safety-guide.pdf").read_bytes().decode("latin-1")

        self.assertIn("(## Numbered Shutdown Procedure) Tj", source)
        self.assertIn("(1. Press the red STOP button", source)
        self.assertIn("(WARNING BOX 4: Report damaged guards", source)
        self.assertIn("(## Emergency Response) Tj", source)
        self.assertIn("Jo Chen or the shift supervisor", source)

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

    def test_source_grounding_accepts_five_letter_source_values(self):
        row = self.rows[120]
        with tempfile.TemporaryDirectory() as temporary:
            workspace = Path(temporary)
            PRIOR.write_fixture(row, workspace)
            matched = PRIOR.matched_source_grounding_anchors(
                row,
                workspace,
                "UK & Ireland and Japan were converted from local currency to USD.",
            )

        self.assertIn("uk ireland", matched)
        self.assertIn("japan", matched)

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

    def test_budget_workbook_semantics_require_source_rows_and_non_circular_formulas(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "budget.xlsx"
            write_budget_workbook(path)

            valid, detail = PRIOR.validate_budget_workbook(path)
            self.assertTrue(valid, detail)

            write_budget_workbook(path, circular=True)
            valid, detail = PRIOR.validate_budget_workbook(path)
            self.assertFalse(valid)
            self.assertIn("Quarterly Roll-up!B2", detail)

            write_budget_workbook(path, broken_reference=True)
            valid, detail = PRIOR.validate_budget_workbook(path)
            self.assertFalse(valid)
            self.assertIn("missing Monthly Spend!Z99", detail)

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

    def test_grade_accepts_successful_batch_read_consumption_of_mapped_sources(self):
        row = self.rows[73]
        with tempfile.TemporaryDirectory() as temporary:
            workspace = Path(temporary)
            PRIOR.write_fixture(row, workspace)
            artifact = workspace / PRIOR.output_path(row)
            PRIOR.write_xlsx(
                artifact,
                ["counterparty", "end date", "auto-renew notice window", "termination clause"],
            )
            contract_paths = sorted(
                path.relative_to(workspace).as_posix()
                for path in (workspace / "inputs" / "Contracts" / "2026").glob("*.pdf")
            )
            batch_read = tool("host.file.read_many")
            batch_read["inputJSON"] = json.dumps({
                "paths": [
                    "inputs/evaluation-context.md",
                    "inputs/renewals.xlsx",
                    *contract_paths,
                ]
            })
            report = {
                "ok": True,
                "requestedModelID": PRIOR.EXACT_MODEL,
                "selectedModelID": PRIOR.EXACT_MODEL,
                "tools": [
                    tool("host.file.read", "inputs/source-map.md"),
                    batch_read,
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
        self.assertTrue(by_name["source reads"])
        source_check = next(check for check in checks if check["name"] == "mapped source consumption")
        self.assertTrue(source_check["passed"], source_check["detail"])

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

    def test_shell_command_can_write_and_inspect_the_same_artifact(self):
        path = "outputs/task-54-deliverable.csv"
        command = (
            f'out = "{path}"\n'
            'with open(out, "w", newline="") as stream:\n'
            '    stream.write("risk_id,owner\\nR-1,Jo Chen\\n")\n'
            'with open(out, newline="") as stream:\n'
            '    print(stream.read())\n'
        )

        self.assertTrue(PRIOR.shell_command_writes_path(command, path))
        self.assertTrue(PRIOR.shell_command_writes_path(
            f"cat > {path} <<'EOF'\nrisk_id,owner\nR-1,Jo Chen\nEOF",
            path,
        ))
        self.assertTrue(PRIOR.shell_command_inspects_path(command, path))
        self.assertFalse(PRIOR.shell_command_writes_path(f'open("{path}").read()', path))

    def test_grade_accepts_executed_generated_script_as_artifact_write(self):
        row = self.rows[67]
        with tempfile.TemporaryDirectory() as temporary:
            workspace = Path(temporary)
            PRIOR.write_fixture(row, workspace)
            artifact = workspace / PRIOR.output_path(row)
            artifact.parent.mkdir(parents=True)
            artifact.write_text("project,action\nAtlas,review weekly files\n", encoding="utf-8")
            script_path = "outputs/build_68.py"
            script_content = (
                f"with open('{PRIOR.output_path(row)}', 'w') as stream:\n"
                "    stream.write('project,action\\nAtlas,review weekly files\\n')\n"
            )
            script_write = tool("host.file.write", script_path)
            script_write["inputJSON"] = json.dumps({
                "path": script_path,
                "content": script_content,
            })
            script_run = tool("host.shell.run")
            script_run["inputJSON"] = json.dumps({"cmd": f"python3 {script_path}"})
            report = {
                "ok": True,
                "requestedModelID": PRIOR.EXACT_MODEL,
                "selectedModelID": PRIOR.EXACT_MODEL,
                "tools": [
                    tool("host.file.read", "inputs/source-map.md"),
                    tool("host.file.read", "inputs/evaluation-context.md"),
                    tool("host.file.read", "inputs/weekly-work/item-001.md"),
                    script_write,
                    script_run,
                    tool("host.file.read", PRIOR.output_path(row)),
                ],
            }
            hashes = {
                path: PRIOR.sha256(path)
                for path in workspace.rglob("*") if path.is_file() and path != artifact
            }
            checks, _ = PRIOR.grade(row, workspace, report, hashes)

        by_name = {check["name"]: check["passed"] for check in checks}
        self.assertTrue(by_name["artifact write"])
        self.assertFalse(PRIOR.shell_command_executes_path(f"cat {script_path}", script_path))

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

    def test_grade_accepts_native_chart_render_as_artifact_write(self):
        row = self.rows[19]
        with tempfile.TemporaryDirectory() as temporary:
            workspace = Path(temporary)
            PRIOR.write_fixture(row, workspace)
            artifact = workspace / PRIOR.output_path(row)
            PRIOR.write_png(artifact, width=1000, height=600)
            report = {
                "ok": True,
                "requestedModelID": PRIOR.EXACT_MODEL,
                "selectedModelID": PRIOR.EXACT_MODEL,
                "tools": [
                    tool("host.file.read", "inputs/source-map.md"),
                    tool("host.file.read", "inputs/evaluation-context.md"),
                    tool("host.file.read", "inputs/regional-revenue.csv"),
                    tool("host.chart.render", PRIOR.output_path(row)),
                    tool("host.file.read", PRIOR.output_path(row)),
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
        self.assertTrue(by_name["primary artifact format"])

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
            placeholder = next(
                check for check in checks if check["name"] == "no template placeholders"
            )
            self.assertFalse(placeholder["passed"])

            artifact.write_text(
                "# Atlas result\n\nNo substitution tokens such as `[Name]` remain.\n"
                "Northstar review in 2026.\n" * 20,
                encoding="utf-8",
            )
            checks, _ = PRIOR.grade(row, workspace, report, hashes)
            placeholder = next(
                check for check in checks if check["name"] == "no template placeholders"
            )
            self.assertTrue(placeholder["passed"])

    def test_grade_ignores_placeholder_from_superseded_artifact_readback(self):
        row = self.rows[98]
        with tempfile.TemporaryDirectory() as temporary:
            workspace = Path(temporary)
            PRIOR.write_fixture(row, workspace)
            artifact = workspace / PRIOR.output_path(row)
            artifact.parent.mkdir(parents=True)
            artifact.write_text(
                "# Renewal outreach\n\nJo Chen owns the Northstar renewal review in 2026.\n" * 20,
                encoding="utf-8",
            )
            stale_read = tool("host.file.read", PRIOR.output_path(row))
            stale_read["outputJSON"] = json.dumps({"content": "Draft: {Owner: Jo Chen}"})
            report = {
                "ok": True,
                "requestedModelID": PRIOR.EXACT_MODEL,
                "selectedModelID": PRIOR.EXACT_MODEL,
                "tools": [
                    tool("host.file.read", "inputs/evaluation-context.md"),
                    tool("host.file.read", "inputs/renewals.csv"),
                    stale_read,
                    tool("host.file.write", PRIOR.output_path(row)),
                    tool("host.file.read", PRIOR.output_path(row)),
                ],
                "finalAnswer": "The corrected renewal outreach is complete.",
            }
            hashes = {
                path: PRIOR.sha256(path)
                for path in workspace.rglob("*") if path.is_file() and path != artifact
            }
            checks, _ = PRIOR.grade(row, workspace, report, hashes)

        placeholder = next(
            check for check in checks if check["name"] == "no template placeholders"
        )
        self.assertTrue(placeholder["passed"], placeholder["detail"])

    def test_reusable_macros_distinguish_runtime_fields_from_placeholders(self):
        macro_row = self.rows[59]
        ordinary_row = self.rows[0]
        reusable_text = (
            "Documented fields: [Invoice Number], [Account Name], [Amount], and [Dates]."
        )

        self.assertEqual(PRIOR.unresolved_placeholders(macro_row, reusable_text), [])
        self.assertEqual(
            PRIOR.unresolved_placeholders(macro_row, "Owner: [TBD owner]"),
            ["[TBD owner]"],
        )
        self.assertEqual(
            PRIOR.unresolved_placeholders(macro_row, "Signed by [Name]"),
            ["[Name]"],
        )
        self.assertEqual(
            PRIOR.unresolved_placeholders(ordinary_row, reusable_text),
            ["[Dates]"],
        )

    def test_task_33_semantic_grade_requires_every_personalized_sequence(self):
        row = self.rows[32]
        with tempfile.TemporaryDirectory() as temporary:
            workspace = Path(temporary)
            PRIOR.write_fixture(row, workspace)
            artifact = workspace / PRIOR.output_path(row)
            artifact.parent.mkdir(parents=True)
            sections = []
            with (workspace / "inputs" / "conference-leads.csv").open(
                encoding="utf-8", newline=""
            ) as source:
                prospects = list(csv.DictReader(source))
            for prospect in prospects:
                sections.append(
                    f"## {prospect['contact_id']} - {prospect['first_name']}\n\n"
                    + "\n\n".join(
                        f"### Email {number}\n- **Subject:** Follow-up {number}\n\n"
                        f"Hi {prospect['first_name']},\n\n"
                        f"Your {prospect['booth-notes']} conversation was useful. "
                        "Could we continue it this week?\n\nBest,\nAtlas Team"
                        for number in (1, 2, 3)
                    )
                )
            overview = "\n".join(
                f"| {prospect['contact_id']} | {prospect['first_name']} | {prospect['company']} |"
                for prospect in prospects
            )
            artifact.write_text(
                "# Conference follow-up\n\n"
                "| Contact ID | Name | Company |\n"
                "|---|---|---|\n"
                f"{overview}\n\n"
                + "\n\n".join(sections),
                encoding="utf-8",
            )

            valid, detail = PRIOR.validate_task_33_sequence(artifact)
            self.assertTrue(valid, detail)

            artifact.write_text(
                artifact.read_text(encoding="utf-8")
                + "\n\nSignature block left intentionally blank for send-time entry.\n",
                encoding="utf-8",
            )
            valid, detail = PRIOR.validate_task_33_sequence(artifact)
            self.assertFalse(valid)
            self.assertIn("deferred signatures=['Signature block left intentionally blank", detail)

            artifact.write_text(
                artifact.read_text(encoding="utf-8").replace(
                    "\n\nSignature block left intentionally blank for send-time entry.\n", "\n"
                ),
                encoding="utf-8",
            )

            artifact.write_text(
                artifact.read_text(encoding="utf-8").replace(
                    "## C-001 - Alice", "## C-001 - Alice Chen", 1
                ),
                encoding="utf-8",
            )
            valid, detail = PRIOR.validate_task_33_sequence(artifact)
            self.assertFalse(valid)
            self.assertIn("invented contact names=['C-001: Alice Chen']", detail)

            artifact.write_text(
                "# Conference follow-up\n\n## C-001\n### Email 1\nSubject: Hi {Company}\n",
                encoding="utf-8",
            )
            valid, detail = PRIOR.validate_task_33_sequence(artifact)
            self.assertFalse(valid)
            self.assertIn("missing sections", detail)

    def test_task_122_semantic_grade_requires_concrete_open_grants(self):
        valid_research = """# Open grant shortlist

| Grant opportunity | Government level | Open status | Deadline | Eligibility | Profile fit | Official source |
|---|---|---|---|---|---|---|
| Ohio Workforce Partnership Award | Ohio state | Open as of 2026-08-08 | 2026-09-15 | Ohio 501(c)(3) nonprofits delivering workforce training | Lakeview is an Ohio nonprofit with the required workforce program | https://workforce.ohio.gov/grants/partnership-award |
| Adult Skills Innovation Notice | Federal | Accepting as of 2026-08-08 | August 31, 2026 | U.S. nonprofit public charities providing adult digital-skills programs | Lakeview is a U.S. 501(c)(3) with the named program | https://www.dol.gov/grants/adult-skills-2026 |
| Employment Access Demonstration | Federal | Open as of 2026-08-08 | Rolling throughout Q3 2026 | U.S. nonprofit organizations serving displaced workers | Lakeview is a nationwide-eligible nonprofit serving displaced workers | https://www.dol.gov/grants/employment-access |

## Recommendation
Prepare the Ohio award first.
"""
        with tempfile.TemporaryDirectory() as temporary:
            artifact = Path(temporary) / "task-122-deliverable.md"
            artifact.write_text(valid_research, encoding="utf-8")
            valid, detail = PRIOR.validate_task_122_grants(artifact)
            self.assertTrue(valid, detail)

            artifact.write_text(
                valid_research.replace(
                    "Ohio Workforce Partnership Award",
                    "Ohio Grants Portal",
                ),
                encoding="utf-8",
            )
            valid, detail = PRIOR.validate_task_122_grants(artifact)
            self.assertFalse(valid)
            self.assertIn("generic portal instead of a program", detail)

            artifact.write_text(
                valid_research.replace(
                    "U.S. nonprofit organizations serving displaced workers",
                    "See portal; eligibility not verified",
                ),
                encoding="utf-8",
            )
            valid, detail = PRIOR.validate_task_122_grants(artifact)
            self.assertFalse(valid)
            self.assertIn("eligibility/profile fit is incomplete", detail)

    def test_task_123_semantic_grade_requires_complete_exact_configurations(self):
        valid_comparison = """# Laptop comparison

| Exact model/configuration | Current price | CPU | GPU | RAM | Storage | Display | Color gamut | Weight | Battery life | Product sources |
|---|---|---|---|---|---|---|---|---|---|---|
| Lenovo Creator 14, 32GB/1TB | $1,799.00 | Intel Core Ultra 9 285H | NVIDIA RTX 5060 8GB | 32 GB | 1 TB SSD | 14.5 inch 2880 x 1800 OLED | 100% DCI-P3 | 3.6 lb | 12 hours | https://www.lenovo.com/us/en/creator-14-32-1tb |
| ASUS Studio 16, 32GB/1TB | $1,899.99 | AMD Ryzen AI 9 HX 370 | NVIDIA RTX 5060 8GB | 32 GB | 1 TB SSD | 16 inch 3200 x 2000 OLED | 100% DCI-P3 | 4.1 lb | 10 hours | https://www.asus.com/us/laptops/studio-16-32-1tb |
| Apple MacBook Pro 14, 32GB/1TB | $1,949.00 | Apple M5 Pro 12-core | Apple M5 Pro 18-core integrated GPU | 32 GB | 1 TB SSD | 14.2 inch 3024 x 1964 mini-LED | 100% Display P3 | 3.5 lb | 18 hours | https://www.apple.com/shop/buy-mac/macbook-pro/32gb-1tb |

## Recommendation
Recommend Lenovo Creator 14, 32GB/1TB for the strongest GPU value under budget.
"""
        with tempfile.TemporaryDirectory() as temporary:
            artifact = Path(temporary) / "task-123-deliverable.md"
            artifact.write_text(valid_comparison, encoding="utf-8")
            valid, detail = PRIOR.validate_task_123_laptops(artifact)
            self.assertTrue(valid, detail)

            artifact.write_text(
                valid_comparison.replace("100% Display P3", "not verified"),
                encoding="utf-8",
            )
            valid, detail = PRIOR.validate_task_123_laptops(artifact)
            self.assertFalse(valid)
            self.assertIn("central specification is unverified", detail)

            artifact.write_text(
                valid_comparison.replace("$1,949.00", "$1,949.00 / $3,299.00 spec source"),
                encoding="utf-8",
            )
            valid, detail = PRIOR.validate_task_123_laptops(artifact)
            self.assertFalse(valid)
            self.assertIn("price is absent, ambiguous, or not under $2,000", detail)

    def test_task_117_semantic_grade_requires_complete_sourced_chart(self):
        row = self.rows[116]
        with tempfile.TemporaryDirectory() as temporary:
            workspace = Path(temporary)
            PRIOR.write_fixture(row, workspace)
            artifact = workspace / PRIOR.output_path(row)
            artifact.parent.mkdir(parents=True)
            with (workspace / "inputs" / "records.csv").open(
                encoding="utf-8", newline=""
            ) as source:
                totals = {}
                for record in csv.DictReader(source):
                    totals[record["quarter"]] = totals.get(record["quarter"], 0) + int(
                        record["revenue"]
                    )
            revenue_series = [
                [totals[quarter] for quarter in ("Q1", "Q2", "Q3", "Q4")],
                [181_500_000, 187_200_000, 192_100_000, 199_000_000],
                [268_000_000, 282_300_000, 299_100_000, 318_400_000],
                [214_000_000, 226_500_000, 240_000_000, 252_200_000],
            ]

            def chart_points(values, inverted=False):
                y = 100
                points = [f"0,{y}"]
                for index, (previous, current) in enumerate(zip(values, values[1:]), start=1):
                    direction = 1 if current > previous else -1 if current < previous else 0
                    y += (10 if direction > 0 else -10 if direction < 0 else 0) * (
                        1 if inverted else -1
                    )
                    points.append(f"{index * 10},{y}")
                return " ".join(points)

            chart = "".join(
                f"<polyline points='{chart_points(values)}'/>" for values in revenue_series
            )
            valid_html = (
                "<!doctype html><html><body>"
                "<table><thead><tr><th>Company</th><th>Q1</th><th>Q2</th>"
                "<th>Q3</th><th>Q4</th><th>Source</th></tr></thead><tbody>"
                f"<tr><td>Atlas Labs</td><td>${totals['Q1']:,}</td>"
                f"<td>${totals['Q2']:,}</td><td>${totals['Q3']:,}</td>"
                f"<td>${totals['Q4']:,}</td><td>Internal records</td></tr>"
                "<tr><td>Asana, Inc.</td><td>$181,500,000</td><td>$187,200,000</td>"
                "<td>$192,100,000</td><td>$199,000,000</td>"
                "<td><a href='https://investors.asana.com/results'>Official source</a></td></tr>"
                "<tr><td>monday.com Ltd.</td><td>$268,000,000</td><td>$282,300,000</td>"
                "<td>$299,100,000</td><td>$318,400,000</td>"
                "<td><a href='https://ir.monday.com/results'>Official source</a></td></tr>"
                "<tr><td>GitLab Inc.</td><td>$214,000,000</td><td>$226,500,000</td>"
                "<td>$240,000,000</td><td>$252,200,000</td>"
                "<td><a href='https://ir.gitlab.com/results'>Official source</a></td></tr>"
                f"</tbody></table><svg>{chart}</svg>"
                "</body></html>"
            )
            artifact.write_text(valid_html, encoding="utf-8")

            valid, detail = PRIOR.validate_task_117_revenue_chart(artifact)
            self.assertTrue(valid, detail)

            competitor_header_html = valid_html.replace(
                "<th>Q1</th>",
                "<th>Q1 - Asana, Inc.; monday.com Ltd.; GitLab Inc.</th>",
            )
            artifact.write_text(competitor_header_html, encoding="utf-8")
            valid, detail = PRIOR.validate_task_117_revenue_chart(artifact)
            self.assertTrue(valid, detail)

            inverted_chart = "".join(
                f"<polyline points='{chart_points(values, inverted=True)}'/>"
                for values in revenue_series
            )
            artifact.write_text(valid_html.replace(chart, inverted_chart), encoding="utf-8")
            valid, detail = PRIOR.validate_task_117_revenue_chart(artifact)
            self.assertFalse(valid)
            self.assertIn("svg series geometry", detail)

            rowspanned = valid_html.replace(
                f"<tr><td>Atlas Labs</td><td>${totals['Q1']:,}</td>"
                f"<td>${totals['Q2']:,}</td><td>${totals['Q3']:,}</td>"
                f"<td>${totals['Q4']:,}</td><td>Internal records</td></tr>",
                f"<tr><td rowspan='4'>Atlas Labs</td><td>Q1</td><td>${totals['Q1']:,}</td></tr>"
                f"<tr><td>Q2</td><td>${totals['Q2']:,}</td></tr>"
                f"<tr><td>Q3</td><td>${totals['Q3']:,}</td></tr>"
                f"<tr><td>Q4</td><td>${totals['Q4']:,}</td></tr>",
            )
            artifact.write_text(rowspanned, encoding="utf-8")
            valid, detail = PRIOR.validate_task_117_revenue_chart(artifact)
            self.assertFalse(valid)
            self.assertIn("Atlas Labs", detail)

            abbreviated = rowspanned.replace(
                f"<tr><td rowspan='4'>Atlas Labs</td><td>Q1</td><td>${totals['Q1']:,}</td></tr>"
                f"<tr><td>Q2</td><td>${totals['Q2']:,}</td></tr>"
                f"<tr><td>Q3</td><td>${totals['Q3']:,}</td></tr>"
                f"<tr><td>Q4</td><td>${totals['Q4']:,}</td></tr>",
                f"<tr><td>Atlas Labs</td><td>${totals['Q1']:,}</td>"
                f"<td>${totals['Q2']:,}</td><td>${totals['Q3']:,}</td>"
                f"<td>${totals['Q4']:,}</td><td>Internal records</td></tr>",
            ).replace("$181,500,000", "$181.5M")
            artifact.write_text(abbreviated, encoding="utf-8")
            valid, detail = PRIOR.validate_task_117_revenue_chart(artifact)
            self.assertFalse(valid)
            self.assertIn("Asana, Inc.", detail)

            artifact.write_text(
                abbreviated.replace("$181.5M", "$181,500,000"),
                encoding="utf-8",
            )
            artifact.write_text(
                artifact.read_text(encoding="utf-8").replace("<svg>", "<div>").replace(
                    "</svg>", "</div>"
                ),
                encoding="utf-8",
            )
            valid, detail = PRIOR.validate_task_117_revenue_chart(artifact)
            self.assertFalse(valid)
            self.assertIn("svg shapes=4", detail)

    def test_visible_prose_excludes_html_code_but_keeps_rendered_placeholders(self):
        html = (
            "<style>.card { color: red; margin: 0; }</style>"
            "<script>const row = { name: 'Alice' };</script>"
            "<pre>awk '{q[$7]+=$8}' inputs/records.csv</pre>"
            "<code>{for (k in q) print k, q[k]}</code>"
            "<main>Prepared for {Company}</main>"
        )
        prose = PRIOR.visible_prose(html)
        self.assertNotIn("color: red", prose)
        self.assertNotIn("const row", prose)
        self.assertNotIn("q[$7]", prose)
        self.assertNotIn("for (k in q)", prose)
        self.assertIn("{Company}", prose)

    def test_schedule_grade_requires_persisted_automation(self):
        row = self.rows[147]
        report = {
            "ok": True,
            "isConfidential": False,
            "requestedModelID": PRIOR.EXACT_MODEL,
            "selectedModelID": PRIOR.EXACT_MODEL,
            "windowSource": "swiftui-scene",
            "workspaceWindowCount": 1,
            "screenshot": None,
            "scheduledAutomation": {"id": "automation-id", "status": "active"},
        }
        checks, artifact = PRIOR.grade(row, Path("/tmp/unused"), report, {})
        self.assertIsNone(artifact)
        self.assertTrue(next(check for check in checks if check["name"] == "persisted automation")["passed"])
        self.assertTrue(next(
            check for check in checks if check["name"] == "native physical window ownership"
        )["passed"])

    def test_grade_surfaces_capture_error_and_rejects_missing_owned_window(self):
        row = self.rows[147]
        report = {
            "ok": False,
            "isConfidential": False,
            "requestedModelID": PRIOR.EXACT_MODEL,
            "selectedModelID": PRIOR.EXACT_MODEL,
            "windowSource": "eval-native-fallback",
            "workspaceWindowCount": 0,
            "desktopCaptureError": "windowNotFound",
            "screenshot": None,
            "scheduledAutomation": {"id": "automation-id", "status": "active"},
        }

        checks, _ = PRIOR.grade(row, Path("/tmp/unused"), report, {})
        lifecycle = next(check for check in checks if check["name"] == "desktop lifecycle")
        ownership = next(
            check for check in checks if check["name"] == "native physical window ownership"
        )

        self.assertFalse(lifecycle["passed"])
        self.assertEqual(lifecycle["detail"], "windowNotFound")
        self.assertFalse(ownership["passed"])
        self.assertIn("workspaceWindowCount=0", ownership["detail"])


if __name__ == "__main__":
    unittest.main()
