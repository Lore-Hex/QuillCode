import Foundation

enum QuillCodeDesktopLaunchRecoverySmoke {
    @MainActor
    static func runAndExit(_ request: QuillCodeDesktopSmokeRequest) async {
        do {
            let root = try QuillCodeDesktopSmokeWorkspaceRoot(request: request)
            try verify(home: root.home)
        } catch {
            FileHandle.standardError.write(
                Data("quill-code-desktop launch recovery smoke failed: \(error)\n".utf8)
            )
            exit(1)
        }
        await QuillCodeDesktopSmokeRunner.runAndExit(request)
    }

    static func verify(home: URL) throws {
        let fileURL = home
            .appendingPathComponent("launch-recovery-smoke", isDirectory: true)
            .appendingPathComponent("active-launch.json")
        let store = QuillCodeDesktopLaunchStore(fileURL: fileURL)
        let startedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let metadata = QuillCodeDesktopBuildMetadata(
            version: "0.1.0",
            build: "1",
            commit: String(repeating: "a", count: 40),
            channel: "tester",
            architecture: QuillCodeDesktopArchitecture.current,
            operatingSystem: "macOS 14.0.0"
        )

        let first = try store.beginLaunch(
            metadata: metadata,
            now: startedAt,
            processIdentifier: 70_001,
            processIsRunning: { _ in false }
        )
        try store.markReady(launchID: first.currentRecord.launchID)
        let second = try store.beginLaunch(
            metadata: metadata,
            now: startedAt.addingTimeInterval(10),
            processIdentifier: 70_002,
            processIsRunning: { _ in false }
        )
        guard second.unexpectedExit?.phase == .ready else {
            throw Failure.missingReadyIncident
        }
        try store.finishLaunch(launchID: second.currentRecord.launchID)

        let clean = try store.beginLaunch(
            metadata: metadata,
            now: startedAt.addingTimeInterval(20),
            processIdentifier: 70_003,
            processIsRunning: { _ in false }
        )
        guard clean.unexpectedExit == nil else {
            throw Failure.gracefulLaunchReportedAsUnexpected
        }
        try store.finishLaunch(launchID: clean.currentRecord.launchID)

        _ = try store.beginLaunch(
            metadata: metadata,
            now: startedAt.addingTimeInterval(30),
            processIdentifier: 70_004,
            processIsRunning: { _ in false }
        )
        let recovery = try store.beginLaunch(
            metadata: metadata,
            now: startedAt.addingTimeInterval(40),
            processIdentifier: 70_005,
            processIsRunning: { _ in false }
        )
        guard recovery.unexpectedExit?.requiresRecoveryStartup == true,
              QuillCodeDesktopStartupMode(unexpectedExit: recovery.unexpectedExit) == .recovery
        else {
            throw Failure.missingStartupRecoveryMode
        }
        try store.finishLaunch(launchID: recovery.currentRecord.launchID)
    }

    private enum Failure: LocalizedError {
        case gracefulLaunchReportedAsUnexpected
        case missingReadyIncident
        case missingStartupRecoveryMode

        var errorDescription: String? {
            switch self {
            case .gracefulLaunchReportedAsUnexpected:
                "Launch recovery smoke reported a gracefully finished launch as unexpected."
            case .missingReadyIncident:
                "Launch recovery smoke did not recover the simulated ready-state unexpected exit."
            case .missingStartupRecoveryMode:
                "Launch recovery smoke did not pause automatic work after a startup exit."
            }
        }
    }
}
