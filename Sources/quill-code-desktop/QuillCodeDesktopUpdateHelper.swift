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
            try validateStaging(request, environment: environment)
            didValidate = true
            try validateActivation(request)
            guard QuillCodeDesktopUpdateProcessMonitor.waitForExit(
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
        guard fileManager.fileExists(atPath: request.incomingApplicationURL.path),
              bundleMatches(
                request.incomingApplicationURL,
                identifier: request.expectedBundleIdentifier,
                version: request.expectedVersion,
                build: request.expectedBuild,
                commit: request.expectedCommit
              )
        else {
            return
        }
        try? fileManager.removeItem(at: request.incomingApplicationURL)
    }

    private static func validateStaging(
        _ request: QuillCodeDesktopUpdateHelperRequest,
        environment: QuillCodeDesktopUpdateHelperEnvironment
    ) throws {
        let fileManager = FileManager.default
        let parent = request.destinationApplicationURL.deletingLastPathComponent().standardizedFileURL
        let baseName = request.destinationApplicationURL.deletingPathExtension().lastPathComponent
        guard request.incomingApplicationURL.deletingLastPathComponent().standardizedFileURL == parent,
              request.destinationApplicationURL.pathExtension == "app",
              request.incomingApplicationURL.pathExtension == "app",
              QuillCodeDesktopUpdateRecovery.isOwnedStagingApplication(
                request.incomingApplicationURL,
                baseName: baseName
              ),
              fileManager.fileExists(atPath: request.incomingApplicationURL.path),
              bundleMatches(
                request.incomingApplicationURL,
                identifier: request.expectedBundleIdentifier,
                version: request.expectedVersion,
                build: request.expectedBuild,
                commit: request.expectedCommit
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

    private static func validateActivation(_ request: QuillCodeDesktopUpdateHelperRequest) throws {
        let fileManager = FileManager.default
        switch request.activationMode {
        case .replaceExisting:
            guard request.rollbackApplicationURL == nil,
                  fileManager.fileExists(atPath: request.destinationApplicationURL.path),
                  bundleMatches(
                    request.destinationApplicationURL,
                    identifier: request.expectedBundleIdentifier,
                    version: nil,
                    build: nil,
                    commit: nil
                  )
            else {
                throw QuillCodeDesktopUpdateError.installationFailed(
                    "the existing app cannot be replaced safely"
                )
            }
        case .installNew:
            guard !fileManager.fileExists(atPath: request.destinationApplicationURL.path),
                  let rollbackApplicationURL = request.rollbackApplicationURL,
                  rollbackApplicationURL != request.destinationApplicationURL,
                  rollbackApplicationURL != request.incomingApplicationURL,
                  bundleMatches(
                    rollbackApplicationURL,
                    identifier: request.expectedBundleIdentifier,
                    version: request.expectedVersion,
                    build: request.expectedBuild,
                    commit: request.expectedCommit
                  )
            else {
                throw QuillCodeDesktopUpdateError.installationFailed(
                    "the new installation request is no longer safe"
                )
            }
        }
    }

    private static func install(
        _ request: QuillCodeDesktopUpdateHelperRequest,
        environment: QuillCodeDesktopUpdateHelperEnvironment
    ) throws {
        let fileManager = FileManager.default
        try activate(request)

        let launchedProcess: QuillCodeDesktopLaunchedApplication
        do {
            launchedProcess = try QuillCodeDesktopUpdateApplicationLauncher.launch(
                request.destinationApplicationURL,
                handshakeURL: request.handshakeURL,
                mode: environment.applicationLaunchMode,
                timeout: environment.launchHandshakeTimeout
            )
        } catch {
            try rollback(request, environment: environment)
            throw recoveredFailure("could not be launched", request: request)
        }

        guard QuillCodeDesktopUpdateProcessMonitor.waitForFile(
            request.handshakeURL,
            timeout: environment.launchHandshakeTimeout
        ) else {
            QuillCodeDesktopUpdateProcessMonitor.terminate(launchedProcess.processIdentifier)
            try rollback(request, environment: environment)
            throw recoveredFailure("did not finish launching", request: request)
        }
        guard QuillCodeDesktopUpdateProcessMonitor.remainsRunning(
            launchedProcess,
            for: environment.launchStabilityDuration
        ) else {
            QuillCodeDesktopUpdateProcessMonitor.terminate(launchedProcess.processIdentifier)
            try rollback(request, environment: environment)
            throw recoveredFailure("stopped during startup", request: request)
        }

        try? fileManager.removeItem(at: request.incomingApplicationURL)
        try? fileManager.removeItem(at: request.handshakeURL)
        writeResult(
            .success(version: request.expectedVersion, build: request.expectedBuild),
            to: request.resultURL,
            allowedResultURL: environment.resultURL
        )
        removeCompletedWorkspaceIfSafe(request, cacheRoot: environment.cacheRootURL)
    }

    private static func removeCompletedWorkspaceIfSafe(
        _ request: QuillCodeDesktopUpdateHelperRequest,
        cacheRoot: URL
    ) {
        let root = cacheRoot.standardizedFileURL
        let workspace = request.handshakeURL.deletingLastPathComponent().standardizedFileURL
        guard workspace != root,
              workspace.deletingLastPathComponent().standardizedFileURL == root,
              request.helperURL.deletingLastPathComponent().standardizedFileURL == workspace,
              request.logURL.deletingLastPathComponent().standardizedFileURL == workspace
        else {
            return
        }
        try? FileManager.default.removeItem(at: workspace)
    }

    private static func rollback(
        _ request: QuillCodeDesktopUpdateHelperRequest,
        environment: QuillCodeDesktopUpdateHelperEnvironment
    ) throws {
        let fileManager = FileManager.default
        switch request.activationMode {
        case .replaceExisting:
            guard fileManager.fileExists(atPath: request.destinationApplicationURL.path),
                  fileManager.fileExists(atPath: request.incomingApplicationURL.path)
            else {
                throw QuillCodeDesktopUpdateError.installationFailed(
                    "the previous app backup is missing"
                )
            }
            try swapApplications(
                request.destinationApplicationURL,
                request.incomingApplicationURL
            )
            _ = try QuillCodeDesktopUpdateApplicationLauncher.launch(
                request.destinationApplicationURL,
                handshakeURL: nil,
                mode: environment.applicationLaunchMode,
                timeout: environment.launchHandshakeTimeout
            )
            try? fileManager.removeItem(at: request.incomingApplicationURL)
        case .installNew:
            guard fileManager.fileExists(atPath: request.destinationApplicationURL.path),
                  !fileManager.fileExists(atPath: request.incomingApplicationURL.path),
                  let rollbackApplicationURL = request.rollbackApplicationURL,
                  bundleMatches(
                    request.destinationApplicationURL,
                    identifier: request.expectedBundleIdentifier,
                    version: request.expectedVersion,
                    build: request.expectedBuild,
                    commit: request.expectedCommit
                  )
            else {
                throw QuillCodeDesktopUpdateError.installationFailed(
                    "the original app could not be restored"
                )
            }
            try fileManager.removeItem(at: request.destinationApplicationURL)
            _ = try QuillCodeDesktopUpdateApplicationLauncher.launch(
                rollbackApplicationURL,
                handshakeURL: nil,
                mode: environment.applicationLaunchMode,
                timeout: environment.launchHandshakeTimeout
            )
        }
        try? fileManager.removeItem(at: request.handshakeURL)
    }

    private static func activate(_ request: QuillCodeDesktopUpdateHelperRequest) throws {
        switch request.activationMode {
        case .replaceExisting:
            try swapApplications(
                request.destinationApplicationURL,
                request.incomingApplicationURL
            )
        case .installNew:
            let result = request.incomingApplicationURL.withUnsafeFileSystemRepresentation { incoming in
                request.destinationApplicationURL.withUnsafeFileSystemRepresentation { destination in
                    guard let incoming, let destination else { return Int32(-1) }
                    return renameatx_np(
                        AT_FDCWD,
                        incoming,
                        AT_FDCWD,
                        destination,
                        UInt32(RENAME_EXCL)
                    )
                }
            }
            guard result == 0 else {
                throw QuillCodeDesktopUpdateError.installationFailed(
                    "the app could not be moved into Applications atomically"
                )
            }
        }
    }

    private static func recoveredFailure(
        _ reason: String,
        request: QuillCodeDesktopUpdateHelperRequest
    ) -> QuillCodeDesktopUpdateError {
        let recovery = request.activationMode == .installNew
            ? "the original copy was reopened"
            : "the previous build was restored"
        return .installationFailed("the new build \(reason); \(recovery)")
    }

    private static func swapApplications(_ firstURL: URL, _ secondURL: URL) throws {
        // Keep the destination bundle present if the helper or machine stops during activation.
        let result = firstURL.withUnsafeFileSystemRepresentation { firstPath in
            secondURL.withUnsafeFileSystemRepresentation { secondPath in
                guard let firstPath, let secondPath else { return Int32(-1) }
                return renameatx_np(
                    AT_FDCWD,
                    firstPath,
                    AT_FDCWD,
                    secondPath,
                    UInt32(RENAME_SWAP)
                )
            }
        }
        guard result == 0 else {
            throw QuillCodeDesktopUpdateError.installationFailed(
                "the app bundles could not be swapped atomically"
            )
        }
    }

    private static func bundleMatches(
        _ url: URL,
        identifier: String,
        version: String?,
        build: String?,
        commit: String?
    ) -> Bool {
        guard let values = try? url.resourceValues(
            forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
        ),
              values.isDirectory == true,
              values.isSymbolicLink != true,
              let bundle = Bundle(url: url),
              bundle.bundleIdentifier == identifier
        else {
            return false
        }
        if let version,
           bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String != version {
            return false
        }
        if let build,
           bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String != build {
            return false
        }
        if let commit,
           bundle.object(forInfoDictionaryKey: QuillCodeDesktopBuildMetadata.commitInfoKey) as? String != commit {
            return false
        }
        return true
    }

    private static func writeResult(
        _ result: QuillCodeDesktopUpdateInstallResult,
        to url: URL,
        allowedResultURL: URL
    ) {
        guard url.standardizedFileURL == allowedResultURL.standardizedFileURL,
              let data = try? JSONEncoder().encode(result),
              data.count <= QuillCodeDesktopUpdateInstallResult.maximumEncodedBytes
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
    var launchStabilityDuration: TimeInterval
    var applicationLaunchMode: QuillCodeDesktopUpdateApplicationLaunchMode = .directProcess

    static func production() throws -> Self {
        Self(
            cacheRootURL: try QuillCodeDesktopUpdatePaths.cacheRoot(),
            resultURL: try QuillCodeDesktopUpdatePaths.installResultURL(),
            parentExitTimeout: 30,
            launchHandshakeTimeout: 45,
            launchStabilityDuration: 3,
            applicationLaunchMode: .launchServices
        )
    }
}
