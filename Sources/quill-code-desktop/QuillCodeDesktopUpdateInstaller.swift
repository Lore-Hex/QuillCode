import Foundation

protocol QuillCodeDesktopUpdateInstalling: Sendable {
    func stageAndLaunch(
        preparedUpdate: QuillCodeDesktopPreparedUpdate,
        configuration: QuillCodeDesktopUpdateConfiguration
    ) async throws
}

struct QuillCodeDesktopUpdateInstaller: QuillCodeDesktopUpdateInstalling, Sendable {
    private let runningExecutableURL: URL?

    init(runningExecutableURL: URL? = Bundle.main.executableURL) {
        self.runningExecutableURL = runningExecutableURL
    }

    func stageAndLaunch(
        preparedUpdate: QuillCodeDesktopPreparedUpdate,
        configuration: QuillCodeDesktopUpdateConfiguration
    ) async throws {
        guard configuration.applicationURL.pathExtension == "app",
              let runningExecutableURL,
              FileManager.default.isExecutableFile(atPath: runningExecutableURL.path)
        else {
            throw QuillCodeDesktopUpdateError.installationUnavailable
        }

        let request = try await Task.detached(priority: .utility) {
            try Self.stage(
                preparedUpdate: preparedUpdate,
                configuration: configuration,
                runningExecutableURL: runningExecutableURL
            )
        }.value
        try Task.checkCancellation()
        try Self.launchHelper(request)
    }

    private static func stage(
        preparedUpdate: QuillCodeDesktopPreparedUpdate,
        configuration: QuillCodeDesktopUpdateConfiguration,
        runningExecutableURL: URL
    ) throws -> QuillCodeDesktopUpdateHelperRequest {
        let fileManager = FileManager.default
        let destinationURL = configuration.applicationURL.standardizedFileURL
        let destinationParent = destinationURL.deletingLastPathComponent()
        guard fileManager.fileExists(atPath: destinationURL.path),
              fileManager.isWritableFile(atPath: destinationParent.path)
        else {
            throw QuillCodeDesktopUpdateError.installationUnavailable
        }

        let identifier = UUID().uuidString.lowercased()
        let baseName = destinationURL.deletingPathExtension().lastPathComponent
        let incomingURL = destinationParent.appendingPathComponent(
            ".\(baseName).update-\(identifier).app",
            isDirectory: true
        )
        let backupURL = destinationParent.appendingPathComponent(
            ".\(baseName).backup-\(identifier).app",
            isDirectory: true
        )
        let failedURL = destinationParent.appendingPathComponent(
            ".\(baseName).failed-\(identifier).app",
            isDirectory: true
        )
        let handshakeURL = preparedUpdate.workspaceURL.appendingPathComponent(
            "launch-\(identifier).ack",
            isDirectory: false
        )
        let helperURL = preparedUpdate.workspaceURL.appendingPathComponent(
            "QuillCoworkUpdateHelper-\(identifier)",
            isDirectory: false
        )
        let logURL = preparedUpdate.workspaceURL.appendingPathComponent(
            "install-\(identifier).log",
            isDirectory: false
        )
        let resultURL = try QuillCodeDesktopUpdatePaths.installResultURL()

        guard !fileManager.fileExists(atPath: incomingURL.path),
              !fileManager.fileExists(atPath: backupURL.path),
              !fileManager.fileExists(atPath: failedURL.path)
        else {
            throw QuillCodeDesktopUpdateError.installationFailed("a staging path already exists")
        }

        do {
            try fileManager.copyItem(at: preparedUpdate.applicationURL, to: incomingURL)
            try QuillCodeDesktopDownloadedApplicationValidator.validate(
                incomingURL,
                release: preparedUpdate.release,
                configuration: configuration
            )
            try fileManager.copyItem(at: runningExecutableURL, to: helperURL)
            try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helperURL.path)
            try fileManager.createDirectory(
                at: resultURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        } catch {
            try? fileManager.removeItem(at: incomingURL)
            try? fileManager.removeItem(at: helperURL)
            if let updateError = error as? QuillCodeDesktopUpdateError {
                throw updateError
            }
            throw QuillCodeDesktopUpdateError.installationFailed("the verified app could not be staged")
        }

        return QuillCodeDesktopUpdateHelperRequest(
            parentProcessID: ProcessInfo.processInfo.processIdentifier,
            helperURL: helperURL,
            incomingApplicationURL: incomingURL,
            destinationApplicationURL: destinationURL,
            backupApplicationURL: backupURL,
            failedApplicationURL: failedURL,
            handshakeURL: handshakeURL,
            resultURL: resultURL,
            logURL: logURL,
            expectedBundleIdentifier: configuration.bundleIdentifier,
            expectedVersion: preparedUpdate.release.version,
            expectedBuild: preparedUpdate.release.build
        )
    }

    private static func launchHelper(_ request: QuillCodeDesktopUpdateHelperRequest) throws {
        FileManager.default.createFile(atPath: request.logURL.path, contents: nil)
        let logHandle = try FileHandle(forWritingTo: request.logURL)
        let process = Process()
        process.executableURL = request.helperURL
        process.arguments = request.arguments
        process.standardOutput = logHandle
        process.standardError = logHandle
        do {
            try process.run()
        } catch {
            try? logHandle.close()
            throw QuillCodeDesktopUpdateError.installationFailed("the update helper could not start")
        }
    }
}

struct QuillCodeDesktopUpdateHelperRequest: Equatable, Sendable {
    static let modeArgument = "--quillcode-apply-update"

    var parentProcessID: Int32
    var helperURL: URL
    var incomingApplicationURL: URL
    var destinationApplicationURL: URL
    var backupApplicationURL: URL
    var failedApplicationURL: URL
    var handshakeURL: URL
    var resultURL: URL
    var logURL: URL
    var expectedBundleIdentifier: String
    var expectedVersion: String
    var expectedBuild: String

    var arguments: [String] {
        [
            Self.modeArgument,
            "--parent-pid", String(parentProcessID),
            "--incoming-app", incomingApplicationURL.path,
            "--destination-app", destinationApplicationURL.path,
            "--backup-app", backupApplicationURL.path,
            "--failed-app", failedApplicationURL.path,
            "--handshake", handshakeURL.path,
            "--result", resultURL.path,
            "--bundle-id", expectedBundleIdentifier,
            "--version", expectedVersion,
            "--build", expectedBuild
        ]
    }

    static func parse(arguments: [String], executableURL: URL? = Bundle.main.executableURL) -> Self? {
        guard let modeIndex = arguments.firstIndex(of: modeArgument), let executableURL else { return nil }
        var values: [String: String] = [:]
        var index = modeIndex + 1
        while index + 1 < arguments.count {
            let key = arguments[index]
            if key.hasPrefix("--") {
                values[key] = arguments[index + 1]
                index += 2
            } else {
                index += 1
            }
        }
        guard let parentValue = values["--parent-pid"],
              let parentProcessID = Int32(parentValue),
              parentProcessID > 1,
              let incoming = values["--incoming-app"],
              let destination = values["--destination-app"],
              let backup = values["--backup-app"],
              let failed = values["--failed-app"],
              let handshake = values["--handshake"],
              let result = values["--result"],
              let bundleIdentifier = values["--bundle-id"],
              let version = values["--version"],
              let build = values["--build"]
        else {
            return nil
        }
        return Self(
            parentProcessID: parentProcessID,
            helperURL: executableURL.standardizedFileURL,
            incomingApplicationURL: URL(fileURLWithPath: incoming).standardizedFileURL,
            destinationApplicationURL: URL(fileURLWithPath: destination).standardizedFileURL,
            backupApplicationURL: URL(fileURLWithPath: backup).standardizedFileURL,
            failedApplicationURL: URL(fileURLWithPath: failed).standardizedFileURL,
            handshakeURL: URL(fileURLWithPath: handshake).standardizedFileURL,
            resultURL: URL(fileURLWithPath: result).standardizedFileURL,
            logURL: URL(fileURLWithPath: "/dev/null"),
            expectedBundleIdentifier: bundleIdentifier,
            expectedVersion: version,
            expectedBuild: build
        )
    }
}
