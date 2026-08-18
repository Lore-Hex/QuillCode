import Foundation
import QuillCodeApp

protocol QuillCodeDesktopApplicationRelocating: Sendable {
    func stageAndLaunch(
        configuration: QuillCodeDesktopUpdateConfiguration,
        applicationsURL: URL
    ) async throws
}

enum QuillCodeDesktopApplicationRelocationError: LocalizedError, Equatable, Sendable {
    case unavailable
    case invalidSource
    case destinationConflict
    case otherCopyRunning
    case verificationFailed
    case helperFailed

    var errorDescription: String? {
        switch self {
        case .unavailable:
            "\(QuillCodeProduct.displayName) could not write to Applications. Move the app there in Finder instead."
        case .invalidSource:
            "This copy of \(QuillCodeProduct.displayName) could not be verified for installation."
        case .destinationConflict:
            "Applications already contains a different app named \(QuillCodeProduct.displayName). Move it aside and try again."
        case .otherCopyRunning:
            "Another copy of \(QuillCodeProduct.displayName) is running. Quit it, then try moving this copy again."
        case .verificationFailed:
            "The copied app did not pass \(QuillCodeProduct.displayName)'s identity and code-signature checks."
        case .helperFailed:
            "\(QuillCodeProduct.displayName) could not start the installation helper. Move the app in Finder instead."
        }
    }
}

struct QuillCodeDesktopApplicationRelocator: QuillCodeDesktopApplicationRelocating, Sendable {
    private let runningExecutableURL: URL?

    init(runningExecutableURL: URL? = Bundle.main.executableURL) {
        self.runningExecutableURL = runningExecutableURL
    }

    func stageAndLaunch(
        configuration: QuillCodeDesktopUpdateConfiguration,
        applicationsURL: URL
    ) async throws {
        guard let runningExecutableURL else {
            throw QuillCodeDesktopApplicationRelocationError.invalidSource
        }
        let request = try await Task.detached(priority: .utility) {
            try Self.stage(
                configuration: configuration,
                applicationsURL: applicationsURL,
                runningExecutableURL: runningExecutableURL
            )
        }.value
        do {
            try Task.checkCancellation()
            try QuillCodeDesktopUpdateHelperLauncher.launch(request)
        } catch is CancellationError {
            Self.removeStaging(request)
            throw CancellationError()
        } catch {
            Self.removeStaging(request)
            throw QuillCodeDesktopApplicationRelocationError.helperFailed
        }
    }

    private static func stage(
        configuration: QuillCodeDesktopUpdateConfiguration,
        applicationsURL: URL,
        runningExecutableURL: URL
    ) throws -> QuillCodeDesktopUpdateHelperRequest {
        let fileManager = FileManager.default
        let sourceURL = configuration.applicationURL.standardizedFileURL
        let destinationParent = applicationsURL.standardizedFileURL
        let destinationURL = destinationParent.appendingPathComponent(
            "\(QuillCodeProduct.displayName).app",
            isDirectory: true
        )
        guard sourceURL.pathExtension == "app",
              sourceURL != destinationURL,
              runningExecutableURL.standardizedFileURL.path.hasPrefix(sourceURL.path + "/"),
              fileManager.isExecutableFile(atPath: runningExecutableURL.path),
              nonSymlinkDirectoryExists(destinationParent),
              fileManager.isWritableFile(atPath: destinationParent.path)
        else {
            throw QuillCodeDesktopApplicationRelocationError.unavailable
        }

        let destinationExists = fileManager.fileExists(atPath: destinationURL.path)
        if destinationExists {
            guard nonSymlinkDirectoryExists(destinationURL),
                  Bundle(url: destinationURL)?.bundleIdentifier == configuration.bundleIdentifier
            else {
                throw QuillCodeDesktopApplicationRelocationError.destinationConflict
            }
        }

        let requirement = try validationRequirement(
            configuration: configuration,
            sourceURL: sourceURL
        )
        let identifier = UUID().uuidString.lowercased()
        let cacheRoot = try QuillCodeDesktopUpdatePaths.cacheRoot()
        let resultURL = try QuillCodeDesktopUpdatePaths.installResultURL()
        try fileManager.createDirectory(
            at: cacheRoot,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let workspaceURL = cacheRoot.appendingPathComponent(
            "install-\(identifier)",
            isDirectory: true
        )
        try fileManager.createDirectory(
            at: workspaceURL,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )

        let incomingURL = destinationParent.appendingPathComponent(
            ".\(QuillCodeProduct.displayName).update-\(identifier).app",
            isDirectory: true
        )
        let helperURL = workspaceURL.appendingPathComponent(
            "QuillCoworkInstallHelper-\(identifier)",
            isDirectory: false
        )
        let request = QuillCodeDesktopUpdateHelperRequest(
            parentProcessID: ProcessInfo.processInfo.processIdentifier,
            helperURL: helperURL,
            incomingApplicationURL: incomingURL,
            destinationApplicationURL: destinationURL,
            handshakeURL: workspaceURL.appendingPathComponent(
                "launch-\(identifier).ack",
                isDirectory: false
            ),
            resultURL: resultURL,
            logURL: workspaceURL.appendingPathComponent(
                "install-\(identifier).log",
                isDirectory: false
            ),
            expectedBundleIdentifier: requirement.bundleIdentifier,
            expectedVersion: requirement.version,
            expectedBuild: requirement.build,
            expectedCommit: requirement.commit,
            activationMode: destinationExists ? .replaceExisting : .installNew,
            rollbackApplicationURL: destinationExists ? nil : sourceURL
        )

        guard !fileManager.fileExists(atPath: incomingURL.path) else {
            try? fileManager.removeItem(at: workspaceURL)
            throw QuillCodeDesktopApplicationRelocationError.unavailable
        }
        do {
            try fileManager.copyItem(at: sourceURL, to: incomingURL)
            try QuillCodeDesktopDownloadedApplicationValidator.validate(
                incomingURL,
                requirement: requirement
            )
            try fileManager.copyItem(at: runningExecutableURL, to: helperURL)
            try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helperURL.path)
            try fileManager.createDirectory(
                at: request.resultURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            return request
        } catch {
            removeStaging(request)
            if error is QuillCodeDesktopUpdateError {
                throw QuillCodeDesktopApplicationRelocationError.verificationFailed
            }
            throw QuillCodeDesktopApplicationRelocationError.unavailable
        }
    }

    private static func validationRequirement(
        configuration: QuillCodeDesktopUpdateConfiguration,
        sourceURL: URL
    ) throws -> QuillCodeDesktopApplicationValidationRequirement {
        guard let bundle = Bundle(url: sourceURL),
              bundle.bundleIdentifier == configuration.bundleIdentifier,
              let commit = bundle.object(
                forInfoDictionaryKey: QuillCodeDesktopBuildMetadata.commitInfoKey
              ) as? String,
              QuillCodeDesktopBuildMetadata.isCanonicalCommit(commit)
        else {
            throw QuillCodeDesktopApplicationRelocationError.invalidSource
        }
        let signingRequirement: QuillCodeDesktopUpdateSigningRequirement
        if let teamIdentifier = configuration.expectedSigningTeamIdentifier {
            signingRequirement = .developerID(teamIdentifier: teamIdentifier)
        } else {
            guard configuration.channel == .tester else {
                throw QuillCodeDesktopApplicationRelocationError.invalidSource
            }
            signingRequirement = .adHoc
        }
        return QuillCodeDesktopApplicationValidationRequirement(
            bundleIdentifier: configuration.bundleIdentifier,
            version: configuration.currentVersion,
            build: configuration.currentBuild,
            commit: commit,
            architecture: configuration.architecture,
            signingRequirement: signingRequirement
        )
    }

    private static func nonSymlinkDirectoryExists(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(
            forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
        ) else {
            return false
        }
        return values.isDirectory == true && values.isSymbolicLink != true
    }

    private static func removeStaging(_ request: QuillCodeDesktopUpdateHelperRequest) {
        try? FileManager.default.removeItem(at: request.incomingApplicationURL)
        try? FileManager.default.removeItem(at: request.helperURL.deletingLastPathComponent())
    }
}
