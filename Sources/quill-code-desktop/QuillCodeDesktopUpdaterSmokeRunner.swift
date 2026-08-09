import Darwin
import Foundation

struct QuillCodeDesktopUpdaterSmokeRequest: Equatable, Sendable {
    static let modeArgument = "--native-updater-smoke"

    var reportURL: URL

    init?(arguments: [String]) {
        guard arguments.contains(Self.modeArgument),
              let flagIndex = arguments.firstIndex(of: "--updater-smoke-report"),
              arguments.indices.contains(flagIndex + 1)
        else {
            return nil
        }
        let value = arguments[flagIndex + 1]
        guard value.hasPrefix("/"), !value.isEmpty else { return nil }
        reportURL = URL(fileURLWithPath: value).standardizedFileURL
    }
}

struct QuillCodeDesktopUpdaterSmokeReport: Codable, Equatable, Sendable {
    var ok: Bool
    var sourceVersion: String?
    var sourceBuild: String?
    var targetVersion: String?
    var targetBuild: String?
    var targetCommit: String?
    var message: String
}

@MainActor
enum QuillCodeDesktopUpdaterSmokeRunner {
    static let feedPropagationAttemptLimit = 6
    private static let feedPropagationRetryDelayNanoseconds: UInt64 = 2_000_000_000

    static func runAndExit(_ request: QuillCodeDesktopUpdaterSmokeRequest) async -> Never {
        let report: QuillCodeDesktopUpdaterSmokeReport
        do {
            report = try await stageLatestUpdate()
        } catch {
            report = QuillCodeDesktopUpdaterSmokeReport(
                ok: false,
                sourceVersion: Bundle.main.object(
                    forInfoDictionaryKey: "CFBundleShortVersionString"
                ) as? String,
                sourceBuild: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
                targetVersion: nil,
                targetBuild: nil,
                targetCommit: nil,
                message: error.localizedDescription
            )
        }

        let exitCode: Int32
        do {
            try write(report, to: request.reportURL)
            exitCode = report.ok ? 0 : 1
        } catch {
            FileHandle.standardError.write(Data(
                "quill-code-desktop updater smoke could not write its report: \(error)\n".utf8
            ))
            exitCode = 1
        }
        Darwin.exit(exitCode)
    }

    private static func stageLatestUpdate() async throws -> QuillCodeDesktopUpdaterSmokeReport {
        guard let configuration = QuillCodeDesktopUpdateConfiguration.bundled() else {
            throw QuillCodeDesktopUpdateError.updatesUnavailable
        }
        let release = try await waitForAvailableUpdate(configuration: configuration)
        let prepared = try await QuillCodeDesktopUpdatePreparer().prepare(
            release: release,
            configuration: configuration
        )
        try await QuillCodeDesktopUpdateInstaller().stageAndLaunch(
            preparedUpdate: prepared,
            configuration: configuration
        )
        return QuillCodeDesktopUpdaterSmokeReport(
            ok: true,
            sourceVersion: configuration.currentVersion,
            sourceBuild: configuration.currentBuild,
            targetVersion: release.version,
            targetBuild: release.build,
            targetCommit: release.commit,
            message: "The verified update was staged and its detached installer started."
        )
    }

    static func waitForAvailableUpdate(
        configuration: QuillCodeDesktopUpdateConfiguration,
        checker: any QuillCodeDesktopUpdateChecking = QuillCodeDesktopUpdateChecker(),
        retryDelay: @escaping @Sendable () async throws -> Void = {
            try await Task.sleep(nanoseconds: feedPropagationRetryDelayNanoseconds)
        }
    ) async throws -> QuillCodeDesktopUpdateRelease {
        for attempt in 1...feedPropagationAttemptLimit {
            let result = try await checker.check(configuration: configuration)
            if case .updateAvailable(let release) = result {
                return release
            }
            if attempt < feedPropagationAttemptLimit {
                try await retryDelay()
            }
        }
        throw QuillCodeDesktopUpdateError.installationFailed(
            "the published update feed did not advance beyond the smoke fixture after bounded retries"
        )
    }

    private static func write(
        _ report: QuillCodeDesktopUpdaterSmokeReport,
        to reportURL: URL
    ) throws {
        try FileManager.default.createDirectory(
            at: reportURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(report).write(to: reportURL, options: [.atomic])
    }
}
