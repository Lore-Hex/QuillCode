import Darwin
import Foundation

struct QuillCodeDesktopUpdaterSmokeRequest: Equatable, Sendable {
    static let modeArgument = "--native-updater-smoke"

    var reportURL: URL
    var manifestURL: URL

    init?(arguments: [String]) {
        guard arguments.contains(Self.modeArgument),
              let reportURL = Self.absoluteFileURL(
                  after: "--updater-smoke-report",
                  arguments: arguments
              ),
              let manifestURL = Self.absoluteFileURL(
                  after: "--updater-smoke-manifest",
                  arguments: arguments
              )
        else {
            return nil
        }
        self.reportURL = reportURL
        self.manifestURL = manifestURL
    }

    private static func absoluteFileURL(after flag: String, arguments: [String]) -> URL? {
        let flagIndices = arguments.indices.filter { arguments[$0] == flag }
        guard flagIndices.count == 1,
              let flagIndex = flagIndices.first,
              arguments.indices.contains(flagIndex + 1)
        else {
            return nil
        }
        let value = arguments[flagIndex + 1]
        guard value.hasPrefix("/"), value != "/" else { return nil }
        return URL(fileURLWithPath: value).standardizedFileURL
    }
}

struct QuillCodeDesktopUpdaterSmokeManifestLoader: QuillCodeDesktopUpdateManifestLoading, Sendable {
    var manifestURL: URL

    func loadManifest(from _: URL, byteLimit: Int) async throws -> Data {
        guard manifestURL.isFileURL,
              byteLimit > 0,
              byteLimit < Int.max
        else {
            throw QuillCodeDesktopUpdateError.invalidResponse
        }

        do {
            let values = try manifestURL.resourceValues(forKeys: [
                .fileSizeKey,
                .isRegularFileKey,
                .isSymbolicLinkKey,
            ])
            guard values.isRegularFile == true,
                  values.isSymbolicLink != true
            else {
                throw QuillCodeDesktopUpdateError.invalidResponse
            }
            guard let fileSize = values.fileSize,
                  fileSize <= byteLimit
            else {
                throw QuillCodeDesktopUpdateError.manifestTooLarge
            }

            let handle = try FileHandle(forReadingFrom: manifestURL)
            defer { try? handle.close() }
            let data = try handle.read(upToCount: byteLimit + 1) ?? Data()
            guard data.count <= byteLimit else {
                throw QuillCodeDesktopUpdateError.manifestTooLarge
            }
            return data
        } catch let error as QuillCodeDesktopUpdateError {
            throw error
        } catch {
            throw QuillCodeDesktopUpdateError.invalidResponse
        }
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
    static func runAndExit(_ request: QuillCodeDesktopUpdaterSmokeRequest) async -> Never {
        let report: QuillCodeDesktopUpdaterSmokeReport
        do {
            report = try await stageLatestUpdate(manifestURL: request.manifestURL)
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

    private static func stageLatestUpdate(manifestURL: URL) async throws -> QuillCodeDesktopUpdaterSmokeReport {
        guard let configuration = QuillCodeDesktopUpdateConfiguration.bundled() else {
            throw QuillCodeDesktopUpdateError.updatesUnavailable
        }
        let checker = QuillCodeDesktopUpdateChecker(
            loader: QuillCodeDesktopUpdaterSmokeManifestLoader(manifestURL: manifestURL)
        )
        let release = try await candidateUpdate(
            configuration: configuration,
            checker: checker
        )
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

    static func candidateUpdate(
        configuration: QuillCodeDesktopUpdateConfiguration,
        checker: any QuillCodeDesktopUpdateChecking
    ) async throws -> QuillCodeDesktopUpdateRelease {
        let result = try await checker.check(configuration: configuration)
        if case .updateAvailable(let release) = result {
            return release
        }
        throw QuillCodeDesktopUpdateError.installationFailed(
            "the verified candidate manifest did not advance beyond the smoke fixture"
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
