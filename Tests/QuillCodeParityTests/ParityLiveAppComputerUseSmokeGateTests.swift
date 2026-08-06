import XCTest

final class ParityLiveAppComputerUseSmokeGateTests: QuillCodeParityTestCase {
    func testLiveAppComputerUseAcceptsRedactedLocalAppEvidence() throws {
        let temporaryDirectory = try temporaryTestDirectory(named: "quillcode-live-app-computer-use-tests")
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let evidenceURL = temporaryDirectory.appendingPathComponent("numbers-evidence.json")
        let manifestURL = temporaryDirectory.appendingPathComponent("live-app-computer-use-manifest.json")
        try validLiveAppEvidence.write(to: evidenceURL, atomically: true, encoding: .utf8)

        let result = try Self.runPython(
            Self.packageRoot().appendingPathComponent("scripts/native-click-probe-contracts.py"),
            arguments: ["live-app-computer-use", evidenceURL.path, "--manifest", manifestURL.path]
        )

        XCTAssertEqual(result.exitCode, 0, result.output)
        let manifest = try String(contentsOf: manifestURL, encoding: .utf8)
        XCTAssertTrue(manifest.contains(#""liveAppComputerUseValidated": true"#), manifest)
        XCTAssertTrue(manifest.contains(#""appName": "Numbers""#), manifest)
        XCTAssertTrue(manifest.contains(#""catalogTaskIDs": ["#), manifest)
        XCTAssertTrue(manifest.contains(#"196"#), manifest)
        XCTAssertTrue(manifest.contains(#""foregroundApplication": "Numbers""#), manifest)
        XCTAssertTrue(manifest.contains(#""screenshotArtifactExists": true"#), manifest)
    }

    func testLiveAppComputerUseRejectsSecretsAndRawFields() throws {
        let temporaryDirectory = try temporaryTestDirectory(named: "quillcode-live-app-computer-use-secret-tests")
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let evidenceURL = temporaryDirectory.appendingPathComponent("unsafe-evidence.json")
        let manifestURL = temporaryDirectory.appendingPathComponent("unsafe-manifest.json")
        try validLiveAppEvidence
            .replacingOccurrences(
                of: #""taskCompleted": true"#,
                with: #""taskCompleted": true, "rawPrompt": "use token=sk-tr-v1-unsafe""#
            )
            .write(to: evidenceURL, atomically: true, encoding: .utf8)

        let result = try Self.runPython(
            Self.packageRoot().appendingPathComponent("scripts/native-click-probe-contracts.py"),
            arguments: ["live-app-computer-use", evidenceURL.path, "--manifest", manifestURL.path]
        )

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(
            result.output.contains("raw or secret-bearing field")
                || result.output.contains("appears to contain a secret"),
            result.output
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: manifestURL.path))
    }

    func testCoworkerCatalogCoverageAcceptsLiveAppComputerUseRows() throws {
        let temporaryDirectory = try temporaryTestDirectory(named: "quillcode-live-app-computer-use-catalog-tests")
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let evidenceURL = temporaryDirectory.appendingPathComponent("numbers-evidence.json")
        let manifestURL = temporaryDirectory.appendingPathComponent("numbers-manifest.json")
        let coverageURL = temporaryDirectory.appendingPathComponent("coworker-coverage.json")
        let validator = Self.packageRoot().appendingPathComponent("scripts/native-click-probe-contracts.py")
        try validLiveAppEvidence.write(to: evidenceURL, atomically: true, encoding: .utf8)

        XCTAssertEqual(
            try Self.runPython(
                validator,
                arguments: ["live-app-computer-use", evidenceURL.path, "--manifest", manifestURL.path]
            ).exitCode,
            0
        )

        let result = try Self.runPython(
            validator,
            arguments: ["coworker-catalog", manifestURL.path, "--output", coverageURL.path]
        )

        XCTAssertEqual(result.exitCode, 0, result.output)
        let coverage = try String(contentsOf: coverageURL, encoding: .utf8)
        XCTAssertTrue(coverage.contains(#""provenTaskCount": 1"#), coverage)
        XCTAssertTrue(coverage.contains(#""analogueTaskCount": 0"#), coverage)
        XCTAssertTrue(coverage.contains(#""pendingTaskCount": 209"#), coverage)
        XCTAssertTrue(coverage.contains(#""196": ["#), coverage)
        XCTAssertTrue(coverage.contains(#""evidenceType": "live-app-computer-use""#), coverage)
        XCTAssertTrue(coverage.contains(#""serviceName": "Numbers""#), coverage)
        XCTAssertTrue(coverage.contains(#""urlHost": "local-app:Numbers""#), coverage)
    }

    func testLiveAppComputerUseTemplateWritesRowLinkedSkeleton() throws {
        let temporaryDirectory = try temporaryTestDirectory(named: "quillcode-live-app-computer-use-template-tests")
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let templateURL = temporaryDirectory.appendingPathComponent("numbers-template.json")
        let result = try Self.runPython(
            Self.packageRoot().appendingPathComponent("scripts/native-click-probe-contracts.py"),
            arguments: [
                "live-app-computer-use-template",
                "196",
                "197",
                "--output",
                templateURL.path,
                "--app-name",
                "Numbers",
                "--task-name",
                "Update launch tracker",
            ]
        )

        XCTAssertEqual(result.exitCode, 0, result.output)
        let template = try String(contentsOf: templateURL, encoding: .utf8)
        XCTAssertTrue(template.contains(#""catalogTaskIDs": ["#), template)
        XCTAssertTrue(template.contains(#"196"#), template)
        XCTAssertTrue(template.contains(#"197"#), template)
        XCTAssertTrue(template.contains(#""appName": "Numbers""#), template)
        XCTAssertTrue(template.contains(#""taskName": "Update launch tracker""#), template)
        XCTAssertTrue(template.contains(#""host.computer.screenshot""#), template)
        XCTAssertTrue(template.contains(#""host.computer.click""#), template)
        XCTAssertTrue(template.contains("Replace every TODO before running scripts/live-app-computer-use-smoke.sh"), template)
    }

    func testLiveAppComputerUseContractIsDocumented() throws {
        let validator = try Self.nativeClickProbeValidatorText()
        let script = try Self.scriptText(named: "live-app-computer-use-smoke.sh")
        let templateScript = try Self.scriptText(named: "live-app-computer-use-template.sh")
        let coworkerDocs = try Self.docsText(named: "COWORKER_TASK_TRACKER.md")
        let testPlan = try Self.docsText(named: "TEST_PLAN.md")

        XCTAssertTrue(validator.contains("live-app-computer-use"))
        XCTAssertTrue(validator.contains("liveAppComputerUseValidated"))
        XCTAssertTrue(validator.contains("live-app-computer-use-template"))
        XCTAssertTrue(script.contains("QUILLCODE_LIVE_APP_COMPUTER_USE_EVIDENCE"))
        XCTAssertTrue(templateScript.contains("QUILLCODE_LIVE_APP_NAME"))
        XCTAssertTrue(coworkerDocs.contains("live-app-computer-use-smoke.sh"))
        XCTAssertTrue(coworkerDocs.contains("live-app-computer-use-template.sh"))
        XCTAssertTrue(testPlan.contains("live-app-computer-use-smoke.sh"))
        XCTAssertTrue(testPlan.contains("live-app-computer-use-template.sh"))
    }

    private func temporaryTestDirectory(named name: String) throws -> URL {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(name)
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        return temporaryDirectory
    }

    private var validLiveAppEvidence: String {
        """
        {
          "ok": true,
          "catalogTaskIDs": [196],
          "appName": "Numbers",
          "taskName": "Update launch tracker",
          "foregroundApplication": "Numbers",
          "taskCompleted": true,
          "toolSequence": [
            "host.computer.screenshot",
            "host.computer.click",
            "host.computer.type",
            "host.computer.key"
          ],
          "beforeStateEvidence": "Numbers Launch Tracker row Acme status Pending",
          "afterStateEvidence": "Numbers Launch Tracker row Acme status Done",
          "resultStateEvidence": "Acme status Done",
          "screenshotArtifact": "numbers-launch-tracker-after.png",
          "screenshotArtifactExists": true,
          "observedElements": [
            "Numbers",
            "Launch Tracker",
            "Acme status Done"
          ]
        }
        """
    }
}
