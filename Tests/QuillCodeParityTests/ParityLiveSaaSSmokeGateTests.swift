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

    func testLiveSaaSSmokeScriptDocumentsOptionalManualContract() throws {
        let script = try Self.scriptText(named: "live-saas-smoke.sh")
        let validator = try Self.nativeClickProbeValidatorText()
        let coworkerDocs = try Self.docsText(named: "COWORKER_TASK_TRACKER.md")

        XCTAssertTrue(script.contains("QUILLCODE_LIVE_SAAS_EVIDENCE"))
        XCTAssertTrue(script.contains("native-click-probe-contracts.py\" live-saas"))
        XCTAssertTrue(validator.contains("def write_live_saas_manifest"))
        XCTAssertTrue(validator.contains("accountState must be signed-in"))
        XCTAssertTrue(validator.contains("catalogTaskIDs must be a non-empty list"))
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
