import Foundation
import XCTest

final class ParityPackagedPerformanceGateTests: QuillCodeParityTestCase {
    func testPackagedPerformanceEvidenceStaysOnReleaseBoundary() throws {
        let snapshot = try Self.desktopSourceText(named: "QuillCodeDesktopPerformanceSnapshot.swift")
        let app = try Self.desktopSourceText(named: "QuillCodeDesktopApp.swift")
        let runner = try Self.desktopSourceText(named: "QuillCodeDesktopWindowSmokeRunner.swift")
        let support = try Self.desktopSourceText(named: "QuillCodeDesktopSmokeSupport.swift")
        let packagedSmoke = try Self.scriptText(named: "packaged-macos-smoke.sh")
        let performanceSmoke = try Self.scriptText(named: "packaged-macos-performance-smoke.sh")
        let packageDownloads = try Self.scriptText(named: "package-macos-downloads.sh")
        let workflow = try Self.workflowText(named: "download-builds.yml")
        let downloads = try Self.docsText(named: "DOWNLOADS.md")

        Self.assertSource(snapshot, containsAll: [
            "proc_pidinfo(",
            "PROC_PIDTASKINFO",
            "pti_resident_size",
            "pti_threadnum",
            #"static let measurement = "initial-live-window""#
        ])
        Self.assertSource(app, contains: "QuillCodeDesktopLaunchClock.appEntryUptime")
        Self.assertSource(app, excludes: "await controller.refreshModelCatalog()")
        let smokeLaunchStart = try XCTUnwrap(
            app.range(of: "private enum QuillCodeDesktopWindowSmokeLaunch")
        ).lowerBound
        Self.assertSource(String(app[smokeLaunchStart...]), excludes: "Task.sleep")
        Self.assertSource(runner, contains: "QuillCodeDesktopPerformanceSnapshot.capture(")
        let performanceIndex = try XCTUnwrap(runner.range(of: "let performance = try")).lowerBound
        let screenshotIndex = try XCTUnwrap(runner.range(of: "captureValidatedImageStats(")).lowerBound
        XCTAssertLessThan(performanceIndex, screenshotIndex)
        Self.assertSource(support, contains: #""performance": performance.dictionary"#)

        Self.assertSource(packagedSmoke, containsAll: [
            "packaged-performance.json",
            "native-click-probe-contracts.py\" performance",
            "performance_manifest=packaged-performance.json"
        ])
        Self.assertSource(performanceSmoke, containsAll: [
            "--native-window-smoke",
            "PERFORMANCE_ATTEMPT_COUNT=3",
            #"REPORT_PATHS+=("$REPORT_PATH")"#,
            "--max-launch-ready-milliseconds",
            "--max-resident-memory-bytes",
            "QUILLCODE_MAX_LAUNCH_READY_MILLISECONDS",
            "QUILLCODE_MAX_RESIDENT_MEMORY_BYTES"
        ])
        Self.assertSource(packageDownloads, containsAll: [
            "Quill-Cowork-macOS-$ARCH-PERFORMANCE.json",
            "scripts/packaged-macos-performance-smoke.sh",
            "performance=Quill-Cowork-macOS-$ARCH-PERFORMANCE.json",
            #"SWIFT_BUILD_ARGUMENTS+=(-debug-info-format "$SWIFT_DEBUG_INFO_FORMAT")"#
        ])
        Self.assertSource(workflow, contains: "measured launch and resident-memory release evidence")
        Self.assertSource(downloads, containsAll: [
            "within three",
            "256 MiB",
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
        XCTAssertEqual(manifest["measurement"] as? String, "initial-live-window")
        XCTAssertEqual(manifest["launchReadyMilliseconds"] as? Double, 750)
        XCTAssertEqual(manifest["residentMemoryBytes"] as? Int, 96 * 1_024 * 1_024)
        XCTAssertEqual(manifest["aggregation"] as? String, "single-attempt")
        XCTAssertEqual(manifest["attemptCount"] as? Int, 1)
        let budgets = try XCTUnwrap(manifest["budgets"] as? [String: Any])
        XCTAssertEqual(budgets["maximumLaunchReadyMilliseconds"] as? Double, 1_000)
        XCTAssertEqual(budgets["maximumResidentMemoryBytes"] as? Int, 128 * 1_024 * 1_024)
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
        residentMemoryBytes: Int = 96 * 1_024 * 1_024
    ) throws {
        let payload: [String: Any] = [
            "ok": true,
            "appName": "Quill Cowork",
            "performance": [
                "schemaVersion": 1,
                "measurement": "initial-live-window",
                "launchReadyMilliseconds": launchReadyMilliseconds,
                "residentMemoryBytes": residentMemoryBytes,
                "threadCount": 18
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
                "--max-resident-memory-bytes", String(maximumResidentBytes)
            ]
        )
    }
}
