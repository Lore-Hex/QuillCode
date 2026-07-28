import XCTest

final class ParityLiveSaaSSmokeGateTests: QuillCodeParityTestCase {
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
        XCTAssertTrue(coverage.contains(#""pendingTaskCount": 203"#), coverage)
        XCTAssertTrue(coverage.contains(#""provenTaskIDs": ["#), coverage)
        XCTAssertTrue(coverage.contains(#"196"#), coverage)
        XCTAssertTrue(coverage.contains(#"199"#), coverage)
        XCTAssertTrue(coverage.contains(#"200"#), coverage)
        XCTAssertTrue(coverage.contains(#""evidenceByTaskID": {"#), coverage)
        let markdown = try String(contentsOf: markdownURL, encoding: .utf8)
        XCTAssertTrue(markdown.contains("# QuillCode Coworker Coverage"), markdown)
        XCTAssertTrue(markdown.contains("| Row | Evidence | Service | Task | Source |"), markdown)
        XCTAssertTrue(markdown.contains("| 199 | live-saas | Salesforce | Update CRM status |"), markdown)
        XCTAssertTrue(markdown.contains("Rows not listed here remain unproven"), markdown)
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
          "catalogTaskIDs": [15, 16, 68],
          "taskIDs": [15, 16, 68],
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
        XCTAssertTrue(coverage.contains(#""provenTaskCount": 3"#), coverage)
        XCTAssertTrue(coverage.contains(#""evidenceType": "packaged-one-turn-coworker""#), coverage)
        XCTAssertTrue(coverage.contains(#""15": ["#), coverage)
        XCTAssertTrue(coverage.contains(#""16": ["#), coverage)
        XCTAssertTrue(coverage.contains(#""68": ["#), coverage)
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

    func testLiveSaaSTemplateRejectsInvalidCatalogRows() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("quillcode-live-saas-template-rejection-tests")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let templateURL = temporaryDirectory.appendingPathComponent("invalid-template.json")
        let result = try Self.runPython(
            Self.packageRoot().appendingPathComponent("scripts/native-click-probe-contracts.py"),
            arguments: ["live-saas-template", "207", "--output", templateURL.path]
        )

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("catalogTaskIDs[0] must be between 1 and 206"), result.output)
        XCTAssertFalse(FileManager.default.fileExists(atPath: templateURL.path))
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
