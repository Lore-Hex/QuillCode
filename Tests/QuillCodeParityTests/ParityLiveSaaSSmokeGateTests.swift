import XCTest

final class ParityLiveSaaSSmokeGateTests: QuillCodeParityTestCase {
    func testSaaSAnalogueFixturesExposeInteractiveContracts() throws {
        let fixtureRoot = Self.packageRoot()
            .appendingPathComponent("Tests/Fixtures/SaaSAnalogue")
        let crm = try String(
            contentsOf: fixtureRoot.appendingPathComponent("crm.html"),
            encoding: .utf8
        )
        let sheet = try String(
            contentsOf: fixtureRoot.appendingPathComponent("shared-sheet.html"),
            encoding: .utf8
        )

        XCTAssertTrue(crm.contains(#"input name="status""#))
        XCTAssertTrue(crm.contains(#"button class="save" data-action="save""#))
        XCTAssertTrue(crm.contains(#"data-testid="status" data-saved="false""#))
        XCTAssertTrue(crm.contains(#"result.dataset.saved = "true""#))
        XCTAssertTrue(sheet.contains(#"data-cell="launch-date" contenteditable="true""#))
        XCTAssertTrue(sheet.contains(#"button data-action="mark-done""#))
        XCTAssertTrue(sheet.contains(#"data-testid="sheet-state" data-done="false""#))
        XCTAssertTrue(sheet.contains(#"result.dataset.done = "true""#))
    }

    func testLiveSaaSSmokeValidatorAcceptsSignedInBrowserAndComputerUseEvidence() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("quillcode-live-saas-smoke-tests")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let evidenceURL = temporaryDirectory.appendingPathComponent("salesforce-evidence.json")
        let manifestURL = temporaryDirectory.appendingPathComponent("live-saas-manifest.json")
        try validLiveSaaSEvidence.write(to: evidenceURL, atomically: true, encoding: .utf8)

        let result = try Self.runPython(
            Self.packageRoot().appendingPathComponent("scripts/native-click-probe-contracts.py"),
            arguments: ["live-saas", evidenceURL.path, "--manifest", manifestURL.path]
        )

        XCTAssertEqual(result.exitCode, 0, result.output)
        let manifest = try String(contentsOf: manifestURL, encoding: .utf8)
        XCTAssertTrue(manifest.contains(#""liveSaaSValidated": true"#))
        XCTAssertTrue(manifest.contains(#""serviceName": "Salesforce""#))
        XCTAssertTrue(manifest.contains(#""catalogTaskIDs": ["#))
        XCTAssertTrue(manifest.contains(#"199"#))
        XCTAssertTrue(manifest.contains(#""urlHost": "example.salesforce.com""#))
        XCTAssertTrue(manifest.contains(#""computerUseActionCount": 2"#))
    }

    func testLiveSaaSSmokeValidatorRejectsCapturedSecrets() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("quillcode-live-saas-secret-tests")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let evidenceURL = temporaryDirectory.appendingPathComponent("unsafe-evidence.json")
        let manifestURL = temporaryDirectory.appendingPathComponent("unsafe-manifest.json")
        try validLiveSaaSEvidence
            .replacingOccurrences(of: "Qualified lead saved", with: "token=sk-tr-v1-unsafe")
            .write(to: evidenceURL, atomically: true, encoding: .utf8)

        let result = try Self.runPython(
            Self.packageRoot().appendingPathComponent("scripts/native-click-probe-contracts.py"),
            arguments: ["live-saas", evidenceURL.path, "--manifest", manifestURL.path]
        )

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("appears to contain a secret"), result.output)
        XCTAssertFalse(FileManager.default.fileExists(atPath: manifestURL.path))
    }

    func testCoworkerCatalogCoverageSummarizesValidatedLiveSaaSRows() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("quillcode-coworker-catalog-coverage-tests")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let firstEvidenceURL = temporaryDirectory.appendingPathComponent("salesforce-evidence.json")
        let firstManifestURL = temporaryDirectory.appendingPathComponent("salesforce-manifest.json")
        let secondEvidenceURL = temporaryDirectory.appendingPathComponent("sheets-evidence.json")
        let secondManifestURL = temporaryDirectory.appendingPathComponent("sheets-manifest.json")
        let coverageURL = temporaryDirectory.appendingPathComponent("coworker-coverage.json")
        let markdownURL = temporaryDirectory.appendingPathComponent("coworker-coverage.md")

        try validLiveSaaSEvidence.write(to: firstEvidenceURL, atomically: true, encoding: .utf8)
        try validLiveSaaSEvidence
            .replacingOccurrences(of: #""catalogTaskIDs": [199]"#, with: #""catalogTaskIDs": [196, 200]"#)
            .replacingOccurrences(of: #""serviceName": "Salesforce""#, with: #""serviceName": "Google Sheets""#)
            .replacingOccurrences(of: #""url": "https://example.salesforce.com/lightning/r/Lead/001/view""#, with: #""url": "https://docs.google.com/spreadsheets/d/example/edit""#)
            .write(to: secondEvidenceURL, atomically: true, encoding: .utf8)

        let validator = Self.packageRoot().appendingPathComponent("scripts/native-click-probe-contracts.py")
        XCTAssertEqual(try Self.runPython(validator, arguments: ["live-saas", firstEvidenceURL.path, "--manifest", firstManifestURL.path]).exitCode, 0)
        XCTAssertEqual(try Self.runPython(validator, arguments: ["live-saas", secondEvidenceURL.path, "--manifest", secondManifestURL.path]).exitCode, 0)

        let result = try Self.runPython(
            validator,
            arguments: [
                "coworker-catalog",
                firstManifestURL.path,
                secondManifestURL.path,
                "--output",
                coverageURL.path,
                "--markdown-output",
                markdownURL.path,
            ]
        )

        XCTAssertEqual(result.exitCode, 0, result.output)
        let coverage = try String(contentsOf: coverageURL, encoding: .utf8)
        XCTAssertTrue(coverage.contains(#""provenTaskCount": 3"#), coverage)
        XCTAssertTrue(coverage.contains(#""pendingTaskCount": 317"#), coverage)
        XCTAssertTrue(coverage.contains(#""last": 320"#), coverage)
        XCTAssertTrue(coverage.contains(#""total": 320"#), coverage)
        XCTAssertTrue(coverage.contains(#""provenTaskIDs": ["#), coverage)
        XCTAssertTrue(coverage.contains(#"196"#), coverage)
        XCTAssertTrue(coverage.contains(#"199"#), coverage)
        XCTAssertTrue(coverage.contains(#"200"#), coverage)
        XCTAssertTrue(coverage.contains(#""evidenceByTaskID": {"#), coverage)
        let markdown = try String(contentsOf: markdownURL, encoding: .utf8)
        XCTAssertTrue(markdown.contains("# Quill Cowork Coworker Coverage"), markdown)
        XCTAssertTrue(markdown.contains("| Row | Result | Category | Task | Evidence or next gap |"), markdown)
        XCTAssertTrue(markdown.contains("| 199 | proven | Sales | In HubSpot"), markdown)
        XCTAssertTrue(markdown.contains("live-saas"), markdown)
        XCTAssertTrue(markdown.contains("| 210 | pending | CRM Nudges |"), markdown)
        XCTAssertTrue(markdown.contains("| 320 | pending | Pricing & Competitive Intelligence |"), markdown)
        XCTAssertTrue(markdown.contains("All catalog rows are listed"), markdown)
    }

    func testCoworkerCatalogCoverageAcceptsPackagedOneTurnRows() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("quillcode-coworker-catalog-one-turn-tests")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let manifestURL = temporaryDirectory.appendingPathComponent("packaged-one-turn-coworker.json")
        let coverageURL = temporaryDirectory.appendingPathComponent("coworker-coverage.json")
        try """
        {
          "ok": true,
          "packagedOneTurnCoworkerValidated": true,
          "catalogSpreadsheetURL": "https://docs.google.com/spreadsheets/d/1uq8uYGwoAxdwPcVn11nysjoozZjKY4acYZNVw-Hu5LM/edit?gid=0#gid=0",
          "catalogTaskIDs": [15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68],
          "taskIDs": [15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68],
          "launchServicesMatchesDirect": true,
          "oneTurnCoworkerMatchesDirect": true
        }
        """.write(to: manifestURL, atomically: true, encoding: .utf8)

        let result = try Self.runPython(
            Self.packageRoot().appendingPathComponent("scripts/native-click-probe-contracts.py"),
            arguments: ["coworker-catalog", manifestURL.path, "--output", coverageURL.path]
        )

        XCTAssertEqual(result.exitCode, 0, result.output)
        let coverage = try String(contentsOf: coverageURL, encoding: .utf8)
        XCTAssertTrue(coverage.contains(#""provenTaskCount": 54"#), coverage)
        XCTAssertTrue(coverage.contains(#""evidenceType": "packaged-one-turn-coworker""#), coverage)
        XCTAssertTrue(coverage.contains(#""15": ["#), coverage)
        XCTAssertTrue(coverage.contains(#""16": ["#), coverage)
        XCTAssertTrue(coverage.contains(#""17": ["#), coverage)
        XCTAssertTrue(coverage.contains(#""18": ["#), coverage)
        XCTAssertTrue(coverage.contains(#""19": ["#), coverage)
        XCTAssertTrue(coverage.contains(#""20": ["#), coverage)
        XCTAssertTrue(coverage.contains(#""21": ["#), coverage)
        XCTAssertTrue(coverage.contains(#""22": ["#), coverage)
        XCTAssertTrue(coverage.contains(#""23": ["#), coverage)
        XCTAssertTrue(coverage.contains(#""24": ["#), coverage)
        XCTAssertTrue(coverage.contains(#""25": ["#), coverage)
        XCTAssertTrue(coverage.contains(#""26": ["#), coverage)
        XCTAssertTrue(coverage.contains(#""27": ["#), coverage)
        XCTAssertTrue(coverage.contains(#""28": ["#), coverage)
        XCTAssertTrue(coverage.contains(#""29": ["#), coverage)
        XCTAssertTrue(coverage.contains(#""30": ["#), coverage)
        XCTAssertTrue(coverage.contains(#""31": ["#), coverage)
        XCTAssertTrue(coverage.contains(#""32": ["#), coverage)
        XCTAssertTrue(coverage.contains(#""33": ["#), coverage)
        XCTAssertTrue(coverage.contains(#""34": ["#), coverage)
        XCTAssertTrue(coverage.contains(#""35": ["#), coverage)
        XCTAssertTrue(coverage.contains(#""36": ["#), coverage)
        XCTAssertTrue(coverage.contains(#""37": ["#), coverage)
        XCTAssertTrue(coverage.contains(#""38": ["#), coverage)
        XCTAssertTrue(coverage.contains(#""39": ["#), coverage)
        XCTAssertTrue(coverage.contains(#""40": ["#), coverage)
        XCTAssertTrue(coverage.contains(#""41": ["#), coverage)
        XCTAssertTrue(coverage.contains(#""42": ["#), coverage)
        XCTAssertTrue(coverage.contains(#""43": ["#), coverage)
        XCTAssertTrue(coverage.contains(#""48": ["#), coverage)
        XCTAssertTrue(coverage.contains(#""50": ["#), coverage)
        XCTAssertTrue(coverage.contains(#""51": ["#), coverage)
        XCTAssertTrue(coverage.contains(#""52": ["#), coverage)
        XCTAssertTrue(coverage.contains(#""53": ["#), coverage)
        XCTAssertTrue(coverage.contains(#""54": ["#), coverage)
        XCTAssertTrue(coverage.contains(#""55": ["#), coverage)
        XCTAssertTrue(coverage.contains(#""56": ["#), coverage)
        XCTAssertTrue(coverage.contains(#""57": ["#), coverage)
        XCTAssertTrue(coverage.contains(#""58": ["#), coverage)
        XCTAssertTrue(coverage.contains(#""59": ["#), coverage)
        XCTAssertTrue(coverage.contains(#""60": ["#), coverage)
        XCTAssertTrue(coverage.contains(#""61": ["#), coverage)
        XCTAssertTrue(coverage.contains(#""62": ["#), coverage)
        XCTAssertTrue(coverage.contains(#""63": ["#), coverage)
        XCTAssertTrue(coverage.contains(#""64": ["#), coverage)
        XCTAssertTrue(coverage.contains(#""65": ["#), coverage)
        XCTAssertTrue(coverage.contains(#""66": ["#), coverage)
        XCTAssertTrue(coverage.contains(#""67": ["#), coverage)
        XCTAssertTrue(coverage.contains(#""68": ["#), coverage)
    }

    func testCoworkerCatalogCoverageAcceptsPackagedMultiFileArtifactRows() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("quillcode-coworker-catalog-multi-file-tests")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let oneTurnManifestURL = temporaryDirectory.appendingPathComponent("packaged-one-turn-coworker.json")
        let multiFileManifestURL = temporaryDirectory.appendingPathComponent("packaged-multi-file-artifact.json")
        let coverageURL = temporaryDirectory.appendingPathComponent("coworker-coverage.json")
        try """
        {
          "ok": true,
          "packagedOneTurnCoworkerValidated": true,
          "catalogSpreadsheetURL": "https://docs.google.com/spreadsheets/d/1uq8uYGwoAxdwPcVn11nysjoozZjKY4acYZNVw-Hu5LM/edit?gid=0#gid=0",
          "catalogTaskIDs": [15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68],
          "taskIDs": [15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68],
          "launchServicesMatchesDirect": true,
          "oneTurnCoworkerMatchesDirect": true
        }
        """.write(to: oneTurnManifestURL, atomically: true, encoding: .utf8)
        try """
        {
          "ok": true,
          "packagedMultiFileArtifactValidated": true,
          "catalogSpreadsheetURL": "https://docs.google.com/spreadsheets/d/1uq8uYGwoAxdwPcVn11nysjoozZjKY4acYZNVw-Hu5LM/edit?gid=0#gid=0",
          "catalogTaskIDs": [69, 70, 71, 72, 73],
          "taskIDs": [69, 70, 71, 72, 73],
          "launchServicesMatchesDirect": true,
          "multiFileArtifactMatchesDirect": true,
          "catalogCases": [
            {
              "taskID": 69,
              "prompt": "Draft the CEO all-hands email announcing the reorg from `org-changes.pptx` and the answers in `reorg-qa`, covering the eight hardest questions."
            },
            {
              "taskID": 70,
              "prompt": "Pull the key claims from the three Gartner and Forrester PDFs in `analyst-reports` and flag where they contradict each other."
            },
            {
              "taskID": 71,
              "prompt": "Rename every PDF in `Documents/Invoices` to YYYY-MM-DD_Vendor_Amount.pdf based on what's inside each file, and leave an undo log."
            },
            {
              "taskID": 72,
              "prompt": "Check `allocations.csv` for anyone booked over 100% across the three concurrent projects and propose a rebalance with named swaps."
            },
            {
              "taskID": 73,
              "prompt": "Audit the 30 subcontractor COI PDFs in `coi-pdfs`: pull carrier, policy number, limits, and expiry, then flag anything under $1M or expiring within 60 days."
            }
          ]
        }
        """.write(to: multiFileManifestURL, atomically: true, encoding: .utf8)

        let result = try Self.runPython(
            Self.packageRoot().appendingPathComponent("scripts/native-click-probe-contracts.py"),
            arguments: [
                "coworker-catalog",
                oneTurnManifestURL.path,
                multiFileManifestURL.path,
                "--output",
                coverageURL.path,
            ]
        )

        XCTAssertEqual(result.exitCode, 0, result.output)
        let coverage = try String(contentsOf: coverageURL, encoding: .utf8)
        XCTAssertTrue(coverage.contains(#""provenTaskCount": 59"#), coverage)
        XCTAssertTrue(coverage.contains(#""pendingTaskCount": 261"#), coverage)
        XCTAssertTrue(coverage.contains(#""evidenceType": "packaged-multi-file-artifact""#), coverage)
        XCTAssertTrue(coverage.contains(#""69": ["#), coverage)
        XCTAssertTrue(coverage.contains(#""70": ["#), coverage)
        XCTAssertTrue(coverage.contains(#""71": ["#), coverage)
        XCTAssertTrue(coverage.contains(#""72": ["#), coverage)
        XCTAssertTrue(coverage.contains(#""73": ["#), coverage)
    }

    func testCoworkerCatalogCoverageRejectsManifestWithoutCatalogRows() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("quillcode-coworker-catalog-rejection-tests")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let manifestURL = temporaryDirectory.appendingPathComponent("unlinked-manifest.json")
        let coverageURL = temporaryDirectory.appendingPathComponent("coworker-coverage.json")
        try """
        {
          "ok": true,
          "liveSaaSValidated": true,
          "catalogSpreadsheetURL": "https://docs.google.com/spreadsheets/d/other/edit",
          "catalogTaskIDs": [199],
          "serviceName": "Salesforce",
          "taskName": "Update CRM status",
          "urlHost": "example.salesforce.com"
        }
        """.write(to: manifestURL, atomically: true, encoding: .utf8)

        let result = try Self.runPython(
            Self.packageRoot().appendingPathComponent("scripts/native-click-probe-contracts.py"),
            arguments: ["coworker-catalog", manifestURL.path, "--output", coverageURL.path]
        )

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("canonical coworker catalog spreadsheet"), result.output)
        XCTAssertFalse(FileManager.default.fileExists(atPath: coverageURL.path))
    }

    func testCoworkerCatalogCoverageSeparatesSaaSAnaloguesFromLiveProof() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("quillcode-coworker-saas-analogue-tests")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let manifestURL = temporaryDirectory.appendingPathComponent("packaged-saas-analogue.json")
        let coverageURL = temporaryDirectory.appendingPathComponent("coworker-coverage.json")
        let markdownURL = temporaryDirectory.appendingPathComponent("coworker-coverage.md")
        try """
        {
          "ok": true,
          "saasAnalogueValidated": true,
          "catalogSpreadsheetURL": "https://docs.google.com/spreadsheets/d/1uq8uYGwoAxdwPcVn11nysjoozZjKY4acYZNVw-Hu5LM/edit?gid=0#gid=0",
          "catalogTaskIDs": [199, 200],
          "usesSyntheticData": true,
          "externalSaaSValidated": false,
          "browserWorkflowMatchesDirect": true,
          "launchServicesMatchesDirect": true,
          "analogueScenarios": [
            {"taskID": 199, "scenario": "CRM update", "workflowKey": "browserWorkflowSmoke"},
            {"taskID": 200, "scenario": "Sheet cleanup", "workflowKey": "browserSpreadsheetWorkflowSmoke"}
          ],
          "limitations": [
            "Uses synthetic local records.",
            "Does not validate external authentication or vendor behavior."
          ]
        }
        """.write(to: manifestURL, atomically: true, encoding: .utf8)

        let result = try Self.runPython(
            Self.packageRoot().appendingPathComponent("scripts/native-click-probe-contracts.py"),
            arguments: [
                "coworker-catalog",
                manifestURL.path,
                "--output",
                coverageURL.path,
                "--markdown-output",
                markdownURL.path,
            ]
        )

        XCTAssertEqual(result.exitCode, 0, result.output)
        let coverage = try String(contentsOf: coverageURL, encoding: .utf8)
        XCTAssertTrue(coverage.contains(#""provenTaskCount": 0"#), coverage)
        XCTAssertTrue(coverage.contains(#""analogueTaskCount": 2"#), coverage)
        XCTAssertTrue(coverage.contains(#""pendingTaskCount": 318"#), coverage)
        XCTAssertTrue(coverage.contains(#""result": "analogue""#), coverage)
        XCTAssertTrue(coverage.contains(#""evidenceClass": "analogue""#), coverage)
        let markdown = try String(contentsOf: markdownURL, encoding: .utf8)
        XCTAssertTrue(markdown.contains("| 199 | analogue | Sales | In HubSpot"), markdown)
        XCTAssertTrue(markdown.contains("| 200 | analogue | Shared Sheet Cleanup |"), markdown)
        XCTAssertTrue(markdown.contains("it does not validate external authentication or vendor behavior"), markdown)
    }

    func testLiveSaaSTemplateWritesRowLinkedEvidenceSkeleton() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("quillcode-live-saas-template-tests")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let templateURL = temporaryDirectory.appendingPathComponent("salesforce-template.json")
        let result = try Self.runPython(
            Self.packageRoot().appendingPathComponent("scripts/native-click-probe-contracts.py"),
            arguments: [
                "live-saas-template",
                "199",
                "200",
                "--output",
                templateURL.path,
                "--service-name",
                "Salesforce",
                "--task-name",
                "Update CRM rows",
                "--url",
                "https://example.salesforce.com/lightning/o/Lead/list",
            ]
        )

        XCTAssertEqual(result.exitCode, 0, result.output)
        let template = try String(contentsOf: templateURL, encoding: .utf8)
        XCTAssertTrue(template.contains(#""catalogTaskIDs": ["#), template)
        XCTAssertTrue(template.contains(#"199"#), template)
        XCTAssertTrue(template.contains(#"200"#), template)
        XCTAssertTrue(template.contains(#""serviceName": "Salesforce""#), template)
        XCTAssertTrue(template.contains(#""taskName": "Update CRM rows""#), template)
        XCTAssertTrue(template.contains(#""url": "https://example.salesforce.com/lightning/o/Lead/list""#), template)
        XCTAssertTrue(template.contains(#""host.browser.open""#), template)
        XCTAssertTrue(template.contains(#""host.browser.inspect""#), template)
        XCTAssertTrue(template.contains(#""captureChecklist": ["#), template)
        XCTAssertTrue(template.contains("Replace every TODO before running scripts/live-saas-smoke.sh"), template)
    }

    func testLiveSaaSTemplateAcceptsCatalogRowsAndRejectsTheNextUnknownRow() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("quillcode-live-saas-template-rejection-tests")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let templateURL = temporaryDirectory.appendingPathComponent("crm-template.json")
        let accepted = try Self.runPython(
            Self.packageRoot().appendingPathComponent("scripts/native-click-probe-contracts.py"),
            arguments: ["live-saas-template", "207", "210", "--output", templateURL.path]
        )
        XCTAssertEqual(accepted.exitCode, 0, accepted.output)
        let template = try String(contentsOf: templateURL, encoding: .utf8)
        XCTAssertTrue(template.contains("207"), template)
        XCTAssertTrue(template.contains("210"), template)

        let invalidTemplateURL = temporaryDirectory.appendingPathComponent("invalid-template.json")
        let rejected = try Self.runPython(
            Self.packageRoot().appendingPathComponent("scripts/native-click-probe-contracts.py"),
            arguments: ["live-saas-template", "321", "--output", invalidTemplateURL.path]
        )
        XCTAssertNotEqual(rejected.exitCode, 0)
        XCTAssertTrue(
            rejected.output.contains("catalogTaskIDs[0] must match a catalog row ID between 1 and 320"),
            rejected.output
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: invalidTemplateURL.path))
    }

    func testLiveSaaSSmokeScriptDocumentsOptionalManualContract() throws {
        let script = try Self.scriptText(named: "live-saas-smoke.sh")
        let templateScript = try Self.scriptText(named: "live-saas-template.sh")
        let validator = try Self.nativeClickProbeValidatorText()
        let catalogReporter = try String(
            contentsOf: Self.packageRoot()
                .appendingPathComponent("scripts/native_click_probe_contracts/coworker_catalog.py"),
            encoding: .utf8
        )
        let coworkerDocs = try Self.docsText(named: "COWORKER_TASK_TRACKER.md")

        XCTAssertTrue(script.contains("QUILLCODE_LIVE_SAAS_EVIDENCE"))
        XCTAssertTrue(script.contains("native-click-probe-contracts.py\" live-saas"))
        XCTAssertTrue(templateScript.contains("live-saas-template"))
        XCTAssertTrue(templateScript.contains("QUILLCODE_LIVE_SAAS_SERVICE_NAME"))
        XCTAssertTrue(validator.contains("coworker-catalog"))
        XCTAssertTrue(validator.contains("live-saas-template"))
        XCTAssertTrue(validator.contains("def write_live_saas_manifest"))
        XCTAssertTrue(validator.contains("--markdown-output"))
        XCTAssertTrue(catalogReporter.contains("def coworker_catalog_markdown"))
        XCTAssertTrue(validator.contains("accountState must be signed-in"))
        XCTAssertTrue(validator.contains("catalogTaskIDs must be a non-empty list"))
        XCTAssertTrue(coworkerDocs.contains("live-saas-template.sh"))
        XCTAssertTrue(coworkerDocs.contains("live-saas-smoke.sh"))
        XCTAssertTrue(coworkerDocs.contains("catalogTaskIDs"))
    }

    private var validLiveSaaSEvidence: String {
        """
        {
          "ok": true,
          "catalogTaskIDs": [199],
          "serviceName": "Salesforce",
          "taskName": "Update CRM status",
          "url": "https://example.salesforce.com/lightning/r/Lead/001/view",
          "accountState": "signed-in",
          "toolSequence": [
            "host.browser.open",
            "host.browser.inspect",
            "host.browser.type",
            "host.browser.click",
            "host.computer.screenshot",
            "host.computer.click"
          ],
          "browser": {
            "inspectionDepth": "Live DOM snapshot",
            "signedInIndicator": "Acme Workspace",
            "beforeText": "Acme Workspace Lead status Open",
            "afterText": "Acme Workspace Lead status Qualified",
            "resultText": "Qualified lead saved",
            "actionSelector": "button[data-action='save']"
          },
          "computerUse": {
            "actions": [
              "host.computer.screenshot",
              "host.computer.click"
            ],
            "foregroundApplication": "QuillCode",
            "screenshotArtifactExists": true
          }
        }
        """
    }
}
