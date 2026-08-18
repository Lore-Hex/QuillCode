import Darwin
import Foundation
import QuillCodeApp

struct QuillCodeDesktopRelocationSmokeRequest: Sendable {
    static let modeArgument = "--native-relocation-smoke"

    var applicationsURL: URL
    var reportURL: URL

    init?(arguments: [String]) {
        guard arguments.contains(Self.modeArgument),
              let applicationsPath = Self.value(
                after: "--relocation-smoke-applications",
                arguments: arguments
              ),
              let reportPath = Self.value(
                after: "--relocation-smoke-report",
                arguments: arguments
              ),
              applicationsPath.hasPrefix("/"),
              reportPath.hasPrefix("/"),
              URL(fileURLWithPath: reportPath).pathExtension == "json"
        else {
            return nil
        }
        applicationsURL = URL(
            fileURLWithPath: applicationsPath,
            isDirectory: true
        ).standardizedFileURL
        reportURL = URL(fileURLWithPath: reportPath).standardizedFileURL
    }

    private static func value(after key: String, arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: key),
              arguments.indices.contains(index + 1)
        else {
            return nil
        }
        let value = arguments[index + 1]
        return value.isEmpty ? nil : value
    }
}

struct QuillCodeDesktopRelocationSmokeReport: Codable, Sendable {
    enum Status: String, Codable, Sendable {
        case helperLaunched = "helper-launched"
        case failed
    }

    var status: Status
    var product: String
    var sourceApplicationPath: String
    var destinationApplicationPath: String
    var resultPath: String
    var version: String
    var build: String
    var commit: String
    var error: String?
}

@MainActor
enum QuillCodeDesktopRelocationSmokeRunner {
    static func runAndExit(_ request: QuillCodeDesktopRelocationSmokeRequest) async {
        guard let configuration = QuillCodeDesktopUpdateConfiguration.bundled(),
              let sourceBundle = Bundle(url: configuration.applicationURL),
              let commit = sourceBundle.object(
                forInfoDictionaryKey: QuillCodeDesktopBuildMetadata.commitInfoKey
              ) as? String,
              QuillCodeDesktopBuildMetadata.isCanonicalCommit(commit),
              let resultURL = try? QuillCodeDesktopUpdatePaths.installResultURL()
        else {
            writeFailure(
                request: request,
                configuration: nil,
                resultURL: nil,
                commit: nil,
                message: "packaged update metadata is unavailable"
            )
            Darwin.exit(EXIT_FAILURE)
        }

        do {
            try QuillCodeDesktopRelocationSmokeFiles.prepare(
                applicationsURL: request.applicationsURL,
                reportURL: request.reportURL,
                resultURL: resultURL
            )
            try await QuillCodeDesktopApplicationRelocator().stageAndLaunch(
                configuration: configuration,
                applicationsURL: request.applicationsURL
            )
            try write(
                report: report(
                    status: .helperLaunched,
                    request: request,
                    configuration: configuration,
                    resultURL: resultURL,
                    commit: commit,
                    error: nil
                ),
                to: request.reportURL
            )
            QuillCodeDesktopSystemApplication.terminateForUpdate()
        } catch {
            writeFailure(
                request: request,
                configuration: configuration,
                resultURL: resultURL,
                commit: commit,
                message: error.localizedDescription
            )
            Darwin.exit(EXIT_FAILURE)
        }
    }

    private static func writeFailure(
        request: QuillCodeDesktopRelocationSmokeRequest,
        configuration: QuillCodeDesktopUpdateConfiguration?,
        resultURL: URL?,
        commit: String?,
        message: String
    ) {
        try? write(
            report: QuillCodeDesktopRelocationSmokeReport(
                status: .failed,
                product: QuillCodeProduct.displayName,
                sourceApplicationPath: configuration?.applicationURL.path ??
                    Bundle.main.bundleURL.path,
                destinationApplicationPath: request.applicationsURL.appendingPathComponent(
                    "\(QuillCodeProduct.displayName).app",
                    isDirectory: true
                ).path,
                resultPath: resultURL?.path ?? "unknown",
                version: configuration?.currentVersion ?? "unknown",
                build: configuration?.currentBuild ?? "unknown",
                commit: commit ?? "unknown",
                error: message
            ),
            to: request.reportURL
        )
    }

    private static func report(
        status: QuillCodeDesktopRelocationSmokeReport.Status,
        request: QuillCodeDesktopRelocationSmokeRequest,
        configuration: QuillCodeDesktopUpdateConfiguration,
        resultURL: URL,
        commit: String,
        error: String?
    ) -> QuillCodeDesktopRelocationSmokeReport {
        QuillCodeDesktopRelocationSmokeReport(
            status: status,
            product: QuillCodeProduct.displayName,
            sourceApplicationPath: configuration.applicationURL.path,
            destinationApplicationPath: request.applicationsURL.appendingPathComponent(
                "\(QuillCodeProduct.displayName).app",
                isDirectory: true
            ).path,
            resultPath: resultURL.path,
            version: configuration.currentVersion,
            build: configuration.currentBuild,
            commit: commit,
            error: error
        )
    }

    private static func write(
        report: QuillCodeDesktopRelocationSmokeReport,
        to url: URL
    ) throws {
        let data = try JSONEncoder().encode(report)
        guard data.count <= 64 * 1_024 else {
            throw QuillCodeDesktopApplicationRelocationError.unavailable
        }
        try data.write(to: url, options: [.atomic, .completeFileProtection])
    }
}

private enum QuillCodeDesktopRelocationSmokeFiles {
    static func prepare(applicationsURL: URL, reportURL: URL, resultURL: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: applicationsURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try fileManager.createDirectory(
            at: reportURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try? fileManager.removeItem(at: reportURL)
        try? fileManager.removeItem(at: resultURL)
    }
}
