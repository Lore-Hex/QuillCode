import XCTest

final class ParityScheduledNotificationObservationGateTests: QuillCodeParityTestCase {
    func testScheduledNotificationObservationAcceptsRedactedPackagedEvidence() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("quillcode-scheduled-notification-observation-tests")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let evidenceURL = temporaryDirectory.appendingPathComponent("notification-observation.json")
        let manifestURL = temporaryDirectory.appendingPathComponent("notification-observation-manifest.json")
        try validObservationEvidence.write(to: evidenceURL, atomically: true, encoding: .utf8)

        let result = try Self.runPython(
            Self.packageRoot().appendingPathComponent("scripts/native-click-probe-contracts.py"),
            arguments: ["scheduled-notification-observation", evidenceURL.path, "--manifest", manifestURL.path]
        )

        XCTAssertEqual(result.exitCode, 0, result.output)
        let manifest = try String(contentsOf: manifestURL, encoding: .utf8)
        XCTAssertTrue(manifest.contains(#""scheduledNotificationObservationValidated": true"#), manifest)
        XCTAssertTrue(manifest.contains(#""notificationTitle": "QuillCode scheduled task ready""#), manifest)
        XCTAssertTrue(manifest.contains(#""activationAction": "open-follow-up-thread""#), manifest)
        XCTAssertTrue(manifest.contains(#""notificationVisible": true"#), manifest)
        XCTAssertTrue(manifest.contains(#""activationOpenedFollowUp": true"#), manifest)
    }

    func testScheduledNotificationObservationRejectsSecretsAndRawFields() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("quillcode-scheduled-notification-secret-tests")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let evidenceURL = temporaryDirectory.appendingPathComponent("unsafe-notification-observation.json")
        let manifestURL = temporaryDirectory.appendingPathComponent("unsafe-notification-observation-manifest.json")
        try validObservationEvidence
            .replacingOccurrences(
                of: #""observationMethod": "accessibility""#,
                with: #""observationMethod": "accessibility", "prompt": "raw prompt sk-tr-v1-unsafe""#
            )
            .write(to: evidenceURL, atomically: true, encoding: .utf8)

        let result = try Self.runPython(
            Self.packageRoot().appendingPathComponent("scripts/native-click-probe-contracts.py"),
            arguments: ["scheduled-notification-observation", evidenceURL.path, "--manifest", manifestURL.path]
        )

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(
            result.output.contains("raw or secret-bearing field")
                || result.output.contains("appears to contain a secret"),
            result.output
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: manifestURL.path))
    }

    func testScheduledNotificationObservationContractIsDocumented() throws {
        let validator = try Self.nativeClickProbeValidatorText()
        let script = try Self.scriptText(named: "scheduled-notification-observation-smoke.sh")
        let coworkerDocs = try Self.docsText(named: "COWORKER_TASK_TRACKER.md")
        let testPlan = try Self.docsText(named: "TEST_PLAN.md")

        XCTAssertTrue(validator.contains("scheduled-notification-observation"))
        XCTAssertTrue(validator.contains("scheduledNotificationObservationValidated"))
        XCTAssertTrue(script.contains("QUILLCODE_SCHEDULED_NOTIFICATION_EVIDENCE"))
        XCTAssertTrue(script.contains("scheduled-notification-observation"))
        XCTAssertTrue(coworkerDocs.contains("scheduled-notification-observation-smoke.sh"))
        XCTAssertTrue(testPlan.contains("scheduled-notification-observation-smoke.sh"))
    }

    private var validObservationEvidence: String {
        """
        {
          "ok": true,
          "capturedAt": "2026-07-28T02:05:00Z",
          "appName": "QuillCode",
          "observationMethod": "accessibility",
          "notificationTitle": "QuillCode scheduled task ready",
          "notificationBody": "check competitor pricing pages and notify me with a diff",
          "notificationVisible": true,
          "activationAction": "open-follow-up-thread",
          "activationOpenedFollowUp": true,
          "followUpThreadTitle": "Scheduled check: competitor pricing",
          "screenshotArtifact": "scheduled-notification.png",
          "screenshotArtifactExists": true,
          "observedElements": [
            "QuillCode scheduled task ready",
            "check competitor pricing pages and notify me with a diff",
            "Open follow-up thread"
          ],
          "packagedScheduledCoworkerManifest": {
            "ok": true,
            "scheduledCoworkerMatchesDirect": true,
            "notificationCount": 1,
            "taskText": "check competitor pricing pages and notify me with a diff",
            "followUpThreadTitle": "Scheduled check: competitor pricing"
          }
        }
        """
    }
}
