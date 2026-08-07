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
        XCTAssertTrue(manifest.contains(#""catalogSpreadsheetURL": "https://docs.google.com/spreadsheets/d/"#), manifest)
        XCTAssertTrue(manifest.contains(#""catalogTaskIDs": ["#), manifest)
        XCTAssertTrue(manifest.contains(#"42"#), manifest)
        XCTAssertTrue(manifest.contains(#""notificationTitle": "Quill Cowork scheduled task ready""#), manifest)
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
        let templateScript = try Self.scriptText(named: "scheduled-notification-observation-template.sh")
        let coworkerDocs = try Self.docsText(named: "COWORKER_TASK_TRACKER.md")
        let testPlan = try Self.docsText(named: "TEST_PLAN.md")

        XCTAssertTrue(validator.contains("scheduled-notification-observation"))
        XCTAssertTrue(validator.contains("scheduledNotificationObservationValidated"))
        XCTAssertTrue(validator.contains("scheduled-notification-observation-template"))
        XCTAssertTrue(script.contains("QUILLCODE_SCHEDULED_NOTIFICATION_EVIDENCE"))
        XCTAssertTrue(script.contains("scheduled-notification-observation"))
        XCTAssertTrue(templateScript.contains("scheduled-notification-observation-template"))
        XCTAssertTrue(coworkerDocs.contains("scheduled-notification-observation-smoke.sh"))
        XCTAssertTrue(coworkerDocs.contains("scheduled-notification-observation-template.sh"))
        XCTAssertTrue(testPlan.contains("scheduled-notification-observation-smoke.sh"))
        XCTAssertTrue(testPlan.contains("scheduled-notification-observation-template.sh"))
    }

    func testCoworkerCatalogCoverageAcceptsScheduledNotificationObservationManifests() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("quillcode-scheduled-notification-catalog-tests")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let evidenceURL = temporaryDirectory.appendingPathComponent("notification-observation.json")
        let manifestURL = temporaryDirectory.appendingPathComponent("notification-observation-manifest.json")
        let coverageURL = temporaryDirectory.appendingPathComponent("coworker-coverage.json")
        let validator = Self.packageRoot().appendingPathComponent("scripts/native-click-probe-contracts.py")
        try validObservationEvidence.write(to: evidenceURL, atomically: true, encoding: .utf8)

        XCTAssertEqual(
            try Self.runPython(
                validator,
                arguments: ["scheduled-notification-observation", evidenceURL.path, "--manifest", manifestURL.path]
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
        XCTAssertTrue(coverage.contains(#""pendingTaskCount": 309"#), coverage)
        XCTAssertTrue(coverage.contains(#""last": 310"#), coverage)
        XCTAssertTrue(coverage.contains(#""total": 310"#), coverage)
        XCTAssertTrue(coverage.contains(#""42": ["#), coverage)
        XCTAssertTrue(coverage.contains(#""evidenceType": "scheduled-notification-observation""#), coverage)
        XCTAssertTrue(coverage.contains(#""serviceName": "Quill Cowork Notifications""#), coverage)
    }

    func testScheduledNotificationObservationTemplateWritesRowLinkedSkeleton() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("quillcode-scheduled-notification-template-tests")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let templateURL = temporaryDirectory.appendingPathComponent("scheduled-notification-template.json")
        let result = try Self.runPython(
            Self.packageRoot().appendingPathComponent("scripts/native-click-probe-contracts.py"),
            arguments: [
                "scheduled-notification-observation-template",
                "42",
                "43",
                "--output",
                templateURL.path,
            ]
        )

        XCTAssertEqual(result.exitCode, 0, result.output)
        let template = try String(contentsOf: templateURL, encoding: .utf8)
        XCTAssertTrue(template.contains(#""catalogTaskIDs": ["#), template)
        XCTAssertTrue(template.contains(#"42"#), template)
        XCTAssertTrue(template.contains(#"43"#), template)
        XCTAssertTrue(template.contains(#""notificationTitle": "Quill Cowork scheduled task ready""#), template)
        XCTAssertTrue(template.contains(#""activationAction": "open-follow-up-thread""#), template)
        XCTAssertTrue(template.contains(#""packagedScheduledCoworkerManifest": {"#), template)
        XCTAssertTrue(template.contains("Replace every TODO before running scripts/scheduled-notification-observation-smoke.sh"), template)
    }

    func testScheduledNotificationObservationTemplateRejectsInvalidRows() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("quillcode-scheduled-notification-template-rejection-tests")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let templateURL = temporaryDirectory.appendingPathComponent("invalid-template.json")
        let result = try Self.runPython(
            Self.packageRoot().appendingPathComponent("scripts/native-click-probe-contracts.py"),
            arguments: ["scheduled-notification-observation-template", "311", "--output", templateURL.path]
        )

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(
            result.output.contains("catalogTaskIDs[0] must match a catalog row ID between 1 and 310"),
            result.output
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: templateURL.path))
    }

    private var validObservationEvidence: String {
        """
        {
          "ok": true,
          "catalogTaskIDs": [42],
          "capturedAt": "2026-07-28T02:05:00Z",
          "appName": "Quill Cowork",
          "observationMethod": "accessibility",
          "notificationTitle": "Quill Cowork scheduled task ready",
          "notificationBody": "check competitor pricing pages and notify me with a diff",
          "notificationVisible": true,
          "activationAction": "open-follow-up-thread",
          "activationOpenedFollowUp": true,
          "followUpThreadTitle": "Scheduled check: competitor pricing",
          "screenshotArtifact": "scheduled-notification.png",
          "screenshotArtifactExists": true,
          "observedElements": [
            "Quill Cowork scheduled task ready",
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
