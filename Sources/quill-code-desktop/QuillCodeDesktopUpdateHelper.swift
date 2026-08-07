import Darwin
import Foundation

enum QuillCodeDesktopUpdateHelper {
    static func run(_ request: QuillCodeDesktopUpdateHelperRequest) -> Int32 {
        guard let environment = try? QuillCodeDesktopUpdateHelperEnvironment.production() else {
            fputs("Quill Cowork update failed: updater paths are unavailable\n", stderr)
            return 1
        }
        return run(request, environment: environment)
    }

    static func run(
        _ request: QuillCodeDesktopUpdateHelperRequest,
        environment: QuillCodeDesktopUpdateHelperEnvironment
    ) -> Int32 {
        var didValidate = false
        do {
            try validate(request, environment: environment)
            didValidate = true
            guard waitForProcessToExit(
                request.parentProcessID,
                timeout: environment.parentExitTimeout
            ) else {
                throw QuillCodeDesktopUpdateError.installationFailed("the running app did not exit")
            }
            try install(request, environment: environment)
            return 0
        } catch {
            if didValidate {
                removeUnactivatedStagingIfSafe(request)
            }
            writeResult(
                .failure(message: error.localizedDescription),
                to: request.resultURL,
                allowedResultURL: environment.resultURL
            )
            fputs("Quill Cowork update failed: \(error.localizedDescription)\n", stderr)
            return 1
        }
    }

    private static func removeUnactivatedStagingIfSafe(_ request: QuillCodeDesktopUpdateHelperRequest) {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: request.destinationApplicationURL.path),
              fileManager.fileExists(atPath: request.incomingApplicationURL.path),
              !fileManager.fileExists(atPath: request.backupApplicationURL.path)
        else {
            return
        }
        try? fileManager.removeItem(at: request.incomingApplicationURL)
    }

    private static func validate(
        _ request: QuillCodeDesktopUpdateHelperRequest,
        environment: QuillCodeDesktopUpdateHelperEnvironment
    ) throws {
        let fileManager = FileManager.default
        let parent = request.destinationApplicationURL.deletingLastPathComponent().standardizedFileURL
        let siblingURLs = [
            request.incomingApplicationURL,
            request.backupApplicationURL,
            request.failedApplicationURL
        ]
        guard siblingURLs.allSatisfy({ $0.deletingLastPathComponent().standardizedFileURL == parent }),
              request.destinationApplicationURL.pathExtension == "app",
              request.incomingApplicationURL.pathExtension == "app",
              request.backupApplicationURL.pathExtension == "app",
              request.failedApplicationURL.pathExtension == "app",
              request.incomingApplicationURL.lastPathComponent.contains(".update-"),
              request.backupApplicationURL.lastPathComponent.contains(".backup-"),
              request.failedApplicationURL.lastPathComponent.contains(".failed-"),
              fileManager.fileExists(atPath: request.destinationApplicationURL.path),
              fileManager.fileExists(atPath: request.incomingApplicationURL.path),
              !fileManager.fileExists(atPath: request.backupApplicationURL.path),
              !fileManager.fileExists(atPath: request.failedApplicationURL.path),
              bundleMatches(
                request.destinationApplicationURL,
                identifier: request.expectedBundleIdentifier,
                version: nil,
                build: nil
              ),
              bundleMatches(
                request.incomingApplicationURL,
                identifier: request.expectedBundleIdentifier,
                version: request.expectedVersion,
                build: request.expectedBuild
              ),
              QuillCodeDesktopUpdateLaunchHandshake.isAllowed(
                request.handshakeURL,
                cacheRoot: environment.cacheRootURL
              ),
              request.resultURL.standardizedFileURL == environment.resultURL.standardizedFileURL
        else {
            throw QuillCodeDesktopUpdateError.installationFailed("the staged update request is invalid")
        }
    }

    private static func install(
        _ request: QuillCodeDesktopUpdateHelperRequest,
        environment: QuillCodeDesktopUpdateHelperEnvironment
    ) throws {
        let fileManager = FileManager.default
        try fileManager.moveItem(
            at: request.destinationApplicationURL,
            to: request.backupApplicationURL
        )
        do {
            try fileManager.moveItem(
                at: request.incomingApplicationURL,
                to: request.destinationApplicationURL
            )
        } catch {
            try? fileManager.moveItem(
                at: request.backupApplicationURL,
                to: request.destinationApplicationURL
            )
            throw QuillCodeDesktopUpdateError.installationFailed("the staged app could not be activated")
        }

        let launchedProcessID = try launch(
            request.destinationApplicationURL,
            handshakeURL: request.handshakeURL
        )
        guard waitForFile(
            request.handshakeURL,
            timeout: environment.launchHandshakeTimeout
        ) else {
            terminateProcess(launchedProcessID)
            try rollback(request)
            throw QuillCodeDesktopUpdateError.installationFailed(
                "the new build did not finish launching; the previous build was restored"
            )
        }

        try? fileManager.removeItem(at: request.backupApplicationURL)
        try? fileManager.removeItem(at: request.handshakeURL)
        writeResult(
            .success(version: request.expectedVersion, build: request.expectedBuild),
            to: request.resultURL,
            allowedResultURL: environment.resultURL
        )
    }

    private static func rollback(_ request: QuillCodeDesktopUpdateHelperRequest) throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: request.destinationApplicationURL.path),
              fileManager.fileExists(atPath: request.backupApplicationURL.path)
        else {
            throw QuillCodeDesktopUpdateError.installationFailed("the previous app backup is missing")
        }
        try fileManager.moveItem(
            at: request.destinationApplicationURL,
            to: request.failedApplicationURL
        )
        do {
            try fileManager.moveItem(
                at: request.backupApplicationURL,
                to: request.destinationApplicationURL
            )
        } catch {
            try? fileManager.moveItem(
                at: request.failedApplicationURL,
                to: request.destinationApplicationURL
            )
            throw QuillCodeDesktopUpdateError.installationFailed("the previous app could not be restored")
        }
        _ = try launch(request.destinationApplicationURL, handshakeURL: nil)
        try? fileManager.removeItem(at: request.failedApplicationURL)
        try? fileManager.removeItem(at: request.handshakeURL)
    }

    private static func launch(
        _ applicationURL: URL,
        handshakeURL: URL?
    ) throws -> Int32 {
        guard let bundle = Bundle(url: applicationURL),
              let executableURL = bundle.executableURL,
              FileManager.default.isExecutableFile(atPath: executableURL.path)
        else {
            throw QuillCodeDesktopUpdateError.installationFailed("the app executable is missing")
        }
        var arguments: [String] = []
        if let handshakeURL {
            arguments = [QuillCodeDesktopUpdateLaunchHandshake.argument, handshakeURL.path]
        }
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        do {
            try process.run()
        } catch {
            throw QuillCodeDesktopUpdateError.installationFailed("the updated app could not be launched")
        }
        return process.processIdentifier
    }

    private static func bundleMatches(
        _ url: URL,
        identifier: String,
        version: String?,
        build: String?
    ) -> Bool {
        guard let bundle = Bundle(url: url), bundle.bundleIdentifier == identifier else { return false }
        if let version,
           bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String != version {
            return false
        }
        if let build,
           bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String != build {
            return false
        }
        return true
    }

    private static func waitForProcessToExit(_ processID: Int32, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if kill(processID, 0) == -1 && errno == ESRCH { return true }
            usleep(100_000)
        }
        return kill(processID, 0) == -1 && errno == ESRCH
    }

    private static func waitForFile(_ url: URL, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if FileManager.default.fileExists(atPath: url.path) { return true }
            usleep(100_000)
        }
        return FileManager.default.fileExists(atPath: url.path)
    }

    private static func terminateProcess(_ processID: Int32) {
        guard processID > 1 else { return }
        _ = kill(processID, SIGTERM)
        guard !waitForProcessToExit(processID, timeout: 3) else { return }
        _ = kill(processID, SIGKILL)
        _ = waitForProcessToExit(processID, timeout: 2)
    }

    private static func writeResult(
        _ result: QuillCodeDesktopUpdateInstallResult,
        to url: URL,
        allowedResultURL: URL
    ) {
        guard url.standardizedFileURL == allowedResultURL.standardizedFileURL,
              let data = try? JSONEncoder().encode(result)
        else {
            return
        }
        try? data.write(to: url, options: [.atomic, .completeFileProtection])
    }
}

struct QuillCodeDesktopUpdateHelperEnvironment: Sendable {
    var cacheRootURL: URL
    var resultURL: URL
    var parentExitTimeout: TimeInterval
    var launchHandshakeTimeout: TimeInterval

    static func production() throws -> Self {
        Self(
            cacheRootURL: try QuillCodeDesktopUpdatePaths.cacheRoot(),
            resultURL: try QuillCodeDesktopUpdatePaths.installResultURL(),
            parentExitTimeout: 30,
            launchHandshakeTimeout: 45
        )
    }
}
