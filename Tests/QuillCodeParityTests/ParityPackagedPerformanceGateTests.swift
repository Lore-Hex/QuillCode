import Foundation
import XCTest

final class ParityPackagedPerformanceGateTests: QuillCodeParityTestCase {
    func testPackagedPerformanceEvidenceStaysOnReleaseBoundary() throws {
        let snapshot = try Self.desktopSourceText(named: "QuillCodeDesktopPerformanceSnapshot.swift")
        let app = try Self.desktopSourceText(named: "QuillCodeDesktopApp.swift")
        let runner = try Self.desktopSourceText(named: "QuillCodeDesktopWindowSmokeRunner.swift")
        let support = try Self.desktopSourceText(named: "QuillCodeDesktopSmokeSupport.swift")
        let activationSampler = try Self.desktopSourceText(
            named: "QuillCodeDesktopAccessibilityActivationSampler.swift"
        )
        let interactionVerifier = try Self.desktopSourceText(
            named: "QuillCodeDesktopAccessibilityInteractionVerifier.swift"
        )
        let hierarchySettler = try Self.desktopSourceText(
            named: "QuillCodeDesktopAccessibilityHierarchySettler.swift"
        )
        let frameSampler = try Self.desktopSourceText(
            named: "QuillCodeDesktopAccessibilityFrameSampler.swift"
        )
        let packagedSmoke = try Self.scriptText(named: "packaged-macos-smoke.sh")
        let performanceSmoke = try Self.scriptText(named: "packaged-macos-performance-smoke.sh")
        let packageDownloads = try Self.scriptText(named: "package-macos-downloads.sh")
        let releaseNotes = try Self.scriptText(named: "build-release-notes.py")
        let downloads = try Self.docsText(named: "DOWNLOADS.md")

        Self.assertSource(snapshot, containsAll: [
            "proc_pidinfo(",
            "PROC_PIDTASKINFO",
            "pti_resident_size",
            "pti_threadnum",
            #"static let measurement = "initial-live-window""#,
            #"static let postInteractionMeasurement = "settled-after-native-interaction-sweep""#,
            #"static let repeatedInteractionMeasurement = "settled-after-repeated-native-interaction-sweep""#,
            "interactionSweepCount = 2",
            "residentMemoryGrowthBytes",
            "threadGrowth",
            "repeatedInteractionResidentMemoryGrowthBytes",
            "repeatedInteractionThreadGrowth"
        ])
        Self.assertSource(app, contains: "QuillCodeDesktopLaunchClock.appEntryUptime")
        Self.assertSource(app, excludes: "await controller.refreshModelCatalog()")
        let smokeLaunchStart = try XCTUnwrap(
            app.range(of: "private enum QuillCodeDesktopWindowSmokeLaunch")
        ).lowerBound
        Self.assertSource(String(app[smokeLaunchStart...]), excludes: "Task.sleep")
        Self.assertSource(runner, containsAll: [
            "QuillCodeDesktopInitialPerformanceSnapshot.capture(",
            "QuillCodeDesktopProcessResourceSnapshot.capture()",
            "initialPerformance.completingRepeatedInteractionSweep(",
            #"markStage("interaction-sweep-1")"#,
            #"markStage("interaction-sweep-2")"#,
            #"markStage("complete")"#
        ])
        XCTAssertEqual(
            runner.components(
                separatedBy: "QuillCodeDesktopAccessibilityActivationSampler.validatedReport("
            ).count - 1,
            2
        )
        let performanceIndex = try XCTUnwrap(runner.range(of: "let initialPerformance = try")).lowerBound
        let screenshotIndex = try XCTUnwrap(runner.range(of: "captureValidatedImageStats(")).lowerBound
        let interactionIndex = try XCTUnwrap(
            runner.range(of: "QuillCodeDesktopAccessibilityActivationSampler.validatedReport(")
        ).lowerBound
        let completedPerformanceIndex = try XCTUnwrap(
            runner.range(of: "initialPerformance.completingRepeatedInteractionSweep(")
        ).lowerBound
        XCTAssertLessThan(performanceIndex, screenshotIndex)
        XCTAssertLessThan(interactionIndex, completedPerformanceIndex)
        Self.assertSource(support, contains: #""performance": performance.dictionary"#)
        Self.assertSource(activationSampler, containsAll: [
            "candidateIdentifiers(for: probe)",
            "matchingAnyIdentifier: directCandidates",
            #"markStage("start", contractID: contract.contractID)"#,
            #"markStage("complete", contractID: contract.contractID)"#,
            "QuillCodeDesktopProcessResourceSnapshot.capture()"
        ])
        Self.assertSource(interactionVerifier, contains: "matchingIdentifiers: [identifier]")
        Self.assertSource(hierarchySettler, containsAll: [
            "layoutSentinelIdentifiers",
            "matchingIdentifiers: layoutSentinelIdentifiers"
        ])
        Self.assertSource(frameSampler, containsAll: [
            "targetIdentifiers",
            "matchingIdentifiers: targetIdentifiers"
        ])

        Self.assertSource(packagedSmoke, containsAll: [
            "packaged-performance.json",
            #"QUILLCODE_PACKAGED_MACOS_SMOKE_CONFIGURATION:-release"#,
            #"--configuration "$APP_CONFIGURATION""#,
            "--seed-daily-driver-window-smoke",
            #"--window-smoke-performance-workload "daily-driver-100-chats""#,
            "performance-window-report.json",
            "native-click-probe-contracts.py\" performance",
            "performance_manifest=packaged-performance.json"
        ])
        Self.assertSource(performanceSmoke, containsAll: [
            "--native-window-smoke",
            "--seed-daily-driver-window-smoke",
            #"--window-smoke-performance-workload "daily-driver-100-chats""#,
            "PERFORMANCE_ATTEMPT_COUNT=3",
            #"REPORT_PATHS+=("$REPORT_PATH")"#,
            "--max-launch-ready-milliseconds",
            "--max-resident-memory-bytes",
            "--max-resident-memory-growth-bytes",
            "--max-repeated-resident-memory-growth-bytes",
            "--max-thread-count",
            "--max-repeated-thread-growth",
            "QUILLCODE_PACKAGED_PERFORMANCE_ATTEMPT_TIMEOUT_SECONDS",
            #"ATTEMPT_TIMEOUT_SECONDS="${QUILLCODE_PACKAGED_PERFORMANCE_ATTEMPT_TIMEOUT_SECONDS:-180}""#,
            "terminate_smoke_process",
            "QUILLCODE_MAX_LAUNCH_READY_MILLISECONDS",
            "QUILLCODE_MAX_RESIDENT_MEMORY_BYTES",
            "QUILLCODE_MAX_RESIDENT_MEMORY_GROWTH_BYTES",
            "QUILLCODE_MAX_REPEATED_RESIDENT_MEMORY_GROWTH_BYTES",
            "QUILLCODE_MAX_THREAD_COUNT",
            "QUILLCODE_MAX_REPEATED_THREAD_GROWTH"
        ])
        Self.assertSource(packageDownloads, containsAll: [
            "Quill-Cowork-macOS-$ARCH-PERFORMANCE.json",
            "scripts/packaged-macos-performance-smoke.sh",
            "performance=Quill-Cowork-macOS-$ARCH-PERFORMANCE.json",
            #"SWIFT_BUILD_ARGUMENTS+=(-debug-info-format "$SWIFT_DEBUG_INFO_FORMAT")"#
        ])
        Self.assertSource(releaseNotes, containsAll: [
            "performance evidence",
            "Quill-Cowork-macOS-arm64-PERFORMANCE.json",
            "Quill-Cowork-macOS-x86_64-PERFORMANCE.json"
        ])
        Self.assertSource(downloads, containsAll: [
            "within three",
            "256 MiB",
            "80 MiB",
            "16 MiB",
            "64 threads",
            "4 additional threads",
            "PERFORMANCE.json"
        ])
    }

    func testPerformanceValidatorWritesBoundedEvidenceManifest() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let result = try runValidator(
            reports: [fixture.report],
            manifest: fixture.manifest,
            maximumLaunchMilliseconds: 1_000,
            maximumResidentBytes: 128 * 1_024 * 1_024
        )
        XCTAssertEqual(result.exitCode, 0, result.output)

        let data = try Data(contentsOf: fixture.manifest)
        let manifest = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(manifest["ok"] as? Bool, true)
        XCTAssertEqual(manifest["withinBudget"] as? Bool, true)
        XCTAssertEqual(manifest["schemaVersion"] as? Int, 4)
        XCTAssertEqual(manifest["workload"] as? String, "daily-driver-100-chats")
        XCTAssertEqual(manifest["measurement"] as? String, "initial-live-window")
        XCTAssertEqual(
            manifest["postInteractionMeasurement"] as? String,
            "settled-after-native-interaction-sweep"
        )
        XCTAssertEqual(manifest["launchReadyMilliseconds"] as? Double, 750)
        XCTAssertEqual(manifest["residentMemoryBytes"] as? Int, 96 * 1_024 * 1_024)
        XCTAssertEqual(
            manifest["postInteractionResidentMemoryBytes"] as? Int,
            100 * 1_024 * 1_024
        )
        XCTAssertEqual(manifest["residentMemoryGrowthBytes"] as? Int, 4 * 1_024 * 1_024)
        XCTAssertEqual(manifest["postInteractionThreadCount"] as? Int, 20)
        XCTAssertEqual(manifest["threadGrowth"] as? Int, 2)
        XCTAssertEqual(
            manifest["repeatedInteractionMeasurement"] as? String,
            "settled-after-repeated-native-interaction-sweep"
        )
        XCTAssertEqual(manifest["interactionSweepCount"] as? Int, 2)
        XCTAssertEqual(
            manifest["repeatedInteractionResidentMemoryBytes"] as? Int,
            102 * 1_024 * 1_024
        )
        XCTAssertEqual(
            manifest["repeatedInteractionResidentMemoryGrowthBytes"] as? Int,
            2 * 1_024 * 1_024
        )
        XCTAssertEqual(manifest["repeatedInteractionThreadCount"] as? Int, 19)
        XCTAssertEqual(manifest["repeatedInteractionThreadGrowth"] as? Int, -1)
        XCTAssertEqual(manifest["aggregation"] as? String, "single-attempt")
        XCTAssertEqual(manifest["attemptCount"] as? Int, 1)
        let budgets = try XCTUnwrap(manifest["budgets"] as? [String: Any])
        XCTAssertEqual(budgets["maximumLaunchReadyMilliseconds"] as? Double, 1_000)
        XCTAssertEqual(budgets["maximumResidentMemoryBytes"] as? Int, 128 * 1_024 * 1_024)
        XCTAssertEqual(budgets["maximumResidentMemoryGrowthBytes"] as? Int, 80 * 1_024 * 1_024)
        XCTAssertEqual(
            budgets["maximumRepeatedResidentMemoryGrowthBytes"] as? Int,
            16 * 1_024 * 1_024
        )
        XCTAssertEqual(budgets["maximumThreadCount"] as? Int, 64)
        XCTAssertEqual(budgets["maximumRepeatedThreadGrowth"] as? Int, 4)
    }

    func testPerformanceValidatorFailsClosedAboveEitherBudget() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let slow = try runValidator(
            reports: [fixture.report],
            manifest: fixture.manifest,
            maximumLaunchMilliseconds: 500,
            maximumResidentBytes: 128 * 1_024 * 1_024
        )
        XCTAssertNotEqual(slow.exitCode, 0)
        XCTAssertTrue(slow.output.contains("exceeds 500.00ms budget"), slow.output)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.manifest.path))

        let large = try runValidator(
            reports: [fixture.report],
            manifest: fixture.manifest,
            maximumLaunchMilliseconds: 1_000,
            maximumResidentBytes: 64 * 1_024 * 1_024
        )
        XCTAssertNotEqual(large.exitCode, 0)
        XCTAssertTrue(large.output.contains("exceeds 67108864 byte budget"), large.output)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.manifest.path))
    }

    func testPerformanceValidatorUsesMedianOfThreeFreshProcesses() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let reports = try [3_300.0, 2_700.0, 2_800.0].enumerated().map { index, launch in
            let report = fixture.root.appendingPathComponent("window-report-\(index + 1).json")
            try writeReport(to: report, launchReadyMilliseconds: launch)
            return report
        }

        let result = try runValidator(
            reports: reports,
            manifest: fixture.manifest,
            maximumLaunchMilliseconds: 3_000,
            maximumResidentBytes: 128 * 1_024 * 1_024
        )
        XCTAssertEqual(result.exitCode, 0, result.output)

        let data = try Data(contentsOf: fixture.manifest)
        let manifest = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(manifest["aggregation"] as? String, "median-of-fresh-processes")
        XCTAssertEqual(manifest["launchReadyMilliseconds"] as? Double, 2_800)
        XCTAssertEqual(manifest["attemptCount"] as? Int, 3)
        XCTAssertEqual(manifest["selectedAttempt"] as? Int, 3)
        XCTAssertEqual(manifest["passingAttemptCount"] as? Int, 2)
        XCTAssertEqual(manifest["requiredPassingAttemptCount"] as? Int, 2)
        XCTAssertEqual((manifest["attempts"] as? [[String: Any]])?.count, 3)
    }

    func testPerformanceValidatorFailsWhenMostFreshProcessesMissLaunchBudget() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let reports = try [3_300.0, 3_200.0, 2_800.0].enumerated().map { index, launch in
            let report = fixture.root.appendingPathComponent("window-report-\(index + 1).json")
            try writeReport(to: report, launchReadyMilliseconds: launch)
            return report
        }

        let result = try runValidator(
            reports: reports,
            manifest: fixture.manifest,
            maximumLaunchMilliseconds: 3_000,
            maximumResidentBytes: 128 * 1_024 * 1_024
        )
        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("only 1 of 3 packaged launches met"), result.output)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.manifest.path))
    }

    func testPerformanceValidatorFailsWhenAnyFreshProcessMissesMemoryBudget() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let reports = try [96, 129, 97].enumerated().map { index, residentMiB in
            let report = fixture.root.appendingPathComponent("window-report-\(index + 1).json")
            try writeReport(
                to: report,
                launchReadyMilliseconds: 750,
                residentMemoryBytes: residentMiB * 1_024 * 1_024
            )
            return report
        }

        let result = try runValidator(
            reports: reports,
            manifest: fixture.manifest,
            maximumLaunchMilliseconds: 3_000,
            maximumResidentBytes: 128 * 1_024 * 1_024
        )
        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("exceeds 134217728 byte budget"), result.output)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.manifest.path))
    }

    func testPerformanceValidatorFailsAbovePostInteractionMemoryBudget() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try writeReport(
            to: fixture.report,
            launchReadyMilliseconds: 750,
            postInteractionResidentMemoryBytes: 129 * 1_024 * 1_024
        )

        let result = try runValidator(
            reports: [fixture.report],
            manifest: fixture.manifest,
            maximumLaunchMilliseconds: 3_000,
            maximumResidentBytes: 128 * 1_024 * 1_024
        )
        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("post-interaction resident memory"), result.output)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.manifest.path))
    }

    func testPerformanceValidatorFailsAboveRepeatedInteractionMemoryBudget() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try writeReport(
            to: fixture.report,
            launchReadyMilliseconds: 750,
            repeatedInteractionResidentMemoryBytes: 129 * 1_024 * 1_024
        )

        let result = try runValidator(
            reports: [fixture.report],
            manifest: fixture.manifest,
            maximumLaunchMilliseconds: 3_000,
            maximumResidentBytes: 128 * 1_024 * 1_024
        )
        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("repeated-interaction resident memory"), result.output)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.manifest.path))
    }

    func testPerformanceValidatorFailsAboveRetainedMemoryGrowthBudget() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try writeReport(
            to: fixture.report,
            launchReadyMilliseconds: 750,
            residentMemoryBytes: 96 * 1_024 * 1_024,
            postInteractionResidentMemoryBytes: 177 * 1_024 * 1_024
        )

        let result = try runValidator(
            reports: [fixture.report],
            manifest: fixture.manifest,
            maximumLaunchMilliseconds: 3_000,
            maximumResidentBytes: 256 * 1_024 * 1_024
        )
        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("retained resident-memory growth"), result.output)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.manifest.path))
    }

    func testPerformanceValidatorFailsWhenRepeatedInteractionMemoryDoesNotConverge() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try writeReport(
            to: fixture.report,
            launchReadyMilliseconds: 750,
            postInteractionResidentMemoryBytes: 100 * 1_024 * 1_024,
            repeatedInteractionResidentMemoryBytes: 117 * 1_024 * 1_024
        )

        let result = try runValidator(
            reports: [fixture.report],
            manifest: fixture.manifest,
            maximumLaunchMilliseconds: 3_000,
            maximumResidentBytes: 256 * 1_024 * 1_024
        )
        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(
            result.output.contains("repeated-interaction retained resident-memory growth"),
            result.output
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.manifest.path))
    }

    func testPerformanceValidatorFailsAbovePostInteractionThreadBudget() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try writeReport(
            to: fixture.report,
            launchReadyMilliseconds: 750,
            postInteractionThreadCount: 65
        )

        let result = try runValidator(
            reports: [fixture.report],
            manifest: fixture.manifest,
            maximumLaunchMilliseconds: 3_000,
            maximumResidentBytes: 128 * 1_024 * 1_024
        )
        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("post-interaction thread count"), result.output)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.manifest.path))
    }

    func testPerformanceValidatorFailsAboveRepeatedInteractionThreadBudget() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try writeReport(
            to: fixture.report,
            launchReadyMilliseconds: 750,
            repeatedInteractionThreadCount: 65
        )

        let result = try runValidator(
            reports: [fixture.report],
            manifest: fixture.manifest,
            maximumLaunchMilliseconds: 3_000,
            maximumResidentBytes: 128 * 1_024 * 1_024
        )
        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("repeated-interaction thread count"), result.output)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.manifest.path))
    }

    func testPerformanceValidatorFailsWhenRepeatedInteractionThreadsDoNotConverge() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try writeReport(
            to: fixture.report,
            launchReadyMilliseconds: 750,
            postInteractionThreadCount: 20,
            repeatedInteractionThreadCount: 25
        )

        let result = try runValidator(
            reports: [fixture.report],
            manifest: fixture.manifest,
            maximumLaunchMilliseconds: 3_000,
            maximumResidentBytes: 128 * 1_024 * 1_024
        )
        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("repeated-interaction thread growth"), result.output)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.manifest.path))
    }

    func testPerformanceValidatorRejectsForgedRepeatedInteractionDelta() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let reportData = try Data(contentsOf: fixture.report)
        var report = try XCTUnwrap(
            JSONSerialization.jsonObject(with: reportData) as? [String: Any]
        )
        var performance = try XCTUnwrap(report["performance"] as? [String: Any])
        performance["repeatedInteractionResidentMemoryGrowthBytes"] = 1
        report["performance"] = performance
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted])
            .write(to: fixture.report, options: .atomic)

        let result = try runValidator(
            reports: [fixture.report],
            manifest: fixture.manifest,
            maximumLaunchMilliseconds: 3_000,
            maximumResidentBytes: 128 * 1_024 * 1_024
        )
        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(
            result.output.contains("repeated resident-memory growth does not match"),
            result.output
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.manifest.path))
    }

    func testPerformanceValidatorRejectsMislabeledWorkload() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let reportData = try Data(contentsOf: fixture.report)
        var report = try XCTUnwrap(
            JSONSerialization.jsonObject(with: reportData) as? [String: Any]
        )
        var performance = try XCTUnwrap(report["performance"] as? [String: Any])
        performance["workload"] = "first-run-empty"
        report["performance"] = performance
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted])
            .write(to: fixture.report, options: .atomic)

        let result = try runValidator(
            reports: [fixture.report],
            manifest: fixture.manifest,
            maximumLaunchMilliseconds: 3_000,
            maximumResidentBytes: 128 * 1_024 * 1_024
        )
        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("unexpected packaged performance workload"), result.output)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.manifest.path))
    }

    private func makeFixture() throws -> (root: URL, report: URL, manifest: URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("quillcode-performance-gate-(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let report = root.appendingPathComponent("window-report.json")
        let manifest = root.appendingPathComponent("performance.json")
        try writeReport(to: report, launchReadyMilliseconds: 750)
        return (root, report, manifest)
    }

    private func writeReport(
        to report: URL,
        launchReadyMilliseconds: Double,
        residentMemoryBytes: Int = 96 * 1_024 * 1_024,
        postInteractionResidentMemoryBytes: Int = 100 * 1_024 * 1_024,
        repeatedInteractionResidentMemoryBytes: Int = 102 * 1_024 * 1_024,
        threadCount: Int = 18,
        postInteractionThreadCount: Int = 20,
        repeatedInteractionThreadCount: Int = 19
    ) throws {
        let payload: [String: Any] = [
            "ok": true,
            "appName": "Quill Cowork",
            "performance": [
                "schemaVersion": 4,
                "workload": "daily-driver-100-chats",
                "measurement": "initial-live-window",
                "launchReadyMilliseconds": launchReadyMilliseconds,
                "residentMemoryBytes": residentMemoryBytes,
                "threadCount": threadCount,
                "postInteractionMeasurement": "settled-after-native-interaction-sweep",
                "postInteractionResidentMemoryBytes": postInteractionResidentMemoryBytes,
                "postInteractionThreadCount": postInteractionThreadCount,
                "residentMemoryGrowthBytes": postInteractionResidentMemoryBytes - residentMemoryBytes,
                "threadGrowth": postInteractionThreadCount - threadCount,
                "repeatedInteractionMeasurement": "settled-after-repeated-native-interaction-sweep",
                "interactionSweepCount": 2,
                "repeatedInteractionResidentMemoryBytes": repeatedInteractionResidentMemoryBytes,
                "repeatedInteractionThreadCount": repeatedInteractionThreadCount,
                "repeatedInteractionResidentMemoryGrowthBytes": (
                    repeatedInteractionResidentMemoryBytes - postInteractionResidentMemoryBytes
                ),
                "repeatedInteractionThreadGrowth": (
                    repeatedInteractionThreadCount - postInteractionThreadCount
                )
            ]
        ]
        try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted])
            .write(to: report, options: .atomic)
    }

    private func runValidator(
        reports: [URL],
        manifest: URL,
        maximumLaunchMilliseconds: Int,
        maximumResidentBytes: Int
    ) throws -> ScriptResult {
        try Self.runPython(
            Self.packageRoot().appendingPathComponent("scripts/native-click-probe-contracts.py"),
            arguments: ["performance"] + reports.map(\.path) + [
                "--manifest", manifest.path,
                "--max-launch-ready-milliseconds", String(maximumLaunchMilliseconds),
                "--max-resident-memory-bytes", String(maximumResidentBytes),
                "--max-resident-memory-growth-bytes", String(80 * 1_024 * 1_024),
                "--max-repeated-resident-memory-growth-bytes", String(16 * 1_024 * 1_024),
                "--max-thread-count", "64",
                "--max-repeated-thread-growth", "4"
            ]
        )
    }
}
