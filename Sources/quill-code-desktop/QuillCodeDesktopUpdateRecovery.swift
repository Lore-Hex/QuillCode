import Foundation

protocol QuillCodeDesktopUpdateRecovering: Sendable {
    func recoverInterruptedUpdate(
        configuration: QuillCodeDesktopUpdateConfiguration
    ) async
}

struct QuillCodeDesktopUpdateRecovery: QuillCodeDesktopUpdateRecovering, Sendable {
    static let productionGracePeriod: TimeInterval = 2 * 60

    private let gracePeriod: TimeInterval
    private let cacheRootURL: URL?

    init(
        gracePeriod: TimeInterval = productionGracePeriod,
        cacheRootURL: URL? = nil
    ) {
        self.gracePeriod = gracePeriod.isFinite && gracePeriod >= 0
            ? gracePeriod
            : Self.productionGracePeriod
        self.cacheRootURL = cacheRootURL
    }

    func recoverInterruptedUpdate(
        configuration: QuillCodeDesktopUpdateConfiguration
    ) async {
        if gracePeriod > 0 {
            do {
                try await Task.sleep(for: .seconds(gracePeriod))
            } catch {
                return
            }
        }
        guard !Task.isCancelled else { return }
        let applicationURL = configuration.applicationURL
        let bundleIdentifier = configuration.bundleIdentifier
        let configuredCacheRoot = cacheRootURL
        _ = try? await Task.detached(priority: .utility) {
            let cacheRoot = try configuredCacheRoot ?? QuillCodeDesktopUpdatePaths.cacheRoot()
            guard let protectedStaging = try Self.reconcileInterruptedTransactions(
                configuration: configuration,
                cacheRoot: cacheRoot
            ) else {
                return
            }
            try Self.removeOrphanedStagingApplications(
                beside: applicationURL,
                bundleIdentifier: bundleIdentifier,
                preserving: protectedStaging
            )
        }.value
    }

    /// Returns `nil` when transaction evidence is damaged or ambiguous enough that cleanup must stop.
    static func reconcileInterruptedTransactions(
        configuration: QuillCodeDesktopUpdateConfiguration,
        cacheRoot: URL
    ) throws -> Set<URL>? {
        let fileManager = FileManager.default
        let cacheRoot = cacheRoot.standardizedFileURL
        guard fileManager.fileExists(atPath: cacheRoot.path) else { return [] }
        let rootValues = try cacheRoot.resourceValues(
            forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
        )
        guard rootValues.isDirectory == true, rootValues.isSymbolicLink != true else {
            return nil
        }

        let workspaces = try fileManager.contentsOfDirectory(
            at: cacheRoot,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: []
        )
        var protectedStaging: Set<URL> = []
        for workspace in workspaces {
            let transactionURL = workspace.appendingPathComponent(
                QuillCodeDesktopUpdateTransaction.fileName,
                isDirectory: false
            )
            guard fileManager.fileExists(atPath: transactionURL.path) else { continue }
            guard let transaction = try? QuillCodeDesktopUpdateTransaction.read(
                fromWorkspace: workspace,
                cacheRoot: cacheRoot
            ),
                  transaction.hasValidRecoveryLayout(
                    workspace: workspace,
                    cacheRoot: cacheRoot,
                    configuration: configuration
                  )
            else {
                return nil
            }

            let incoming = transaction.incomingApplicationURL
            protectedStaging.insert(incoming)
            let destinationIdentity = applicationIdentity(
                at: transaction.destinationApplicationURL,
                bundleIdentifier: transaction.expectedBundleIdentifier
            )
            guard fileManager.fileExists(atPath: incoming.path) else {
                if destinationIdentity != nil {
                    try? fileManager.removeItem(at: workspace)
                    protectedStaging.remove(incoming)
                }
                continue
            }
            guard let incomingIdentity = applicationIdentity(
                at: incoming,
                bundleIdentifier: transaction.expectedBundleIdentifier
            ) else {
                continue
            }

            let expectedIdentity = ApplicationIdentity(
                version: transaction.expectedVersion,
                build: transaction.expectedBuild,
                commit: transaction.expectedCommit
            )
            let replacementIsRunning = destinationIdentity == expectedIdentity &&
                configuration.currentVersion == transaction.expectedVersion &&
                configuration.currentBuild == transaction.expectedBuild
            let destinationMatchesRunningBuild =
                destinationIdentity?.version == configuration.currentVersion &&
                destinationIdentity?.build == configuration.currentBuild
            let previousBuildIsRunning = destinationMatchesRunningBuild &&
                destinationIdentity != expectedIdentity &&
                incomingIdentity == expectedIdentity
            let rollbackCanRetire = replacementIsRunning && incomingIdentity != expectedIdentity
            guard previousBuildIsRunning || rollbackCanRetire else { continue }

            do {
                try fileManager.removeItem(at: incoming)
                try? fileManager.removeItem(at: workspace)
                protectedStaging.remove(incoming)
            } catch {
                continue
            }
        }
        return protectedStaging
    }

    @discardableResult
    static func removeOrphanedStagingApplications(
        beside applicationURL: URL,
        bundleIdentifier: String,
        preserving protectedStaging: Set<URL> = []
    ) throws -> [URL] {
        let applicationURL = applicationURL.standardizedFileURL
        let values = try applicationURL.resourceValues(
            forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
        )
        guard applicationURL.pathExtension == "app",
              values.isDirectory == true,
              values.isSymbolicLink != true,
              Bundle(url: applicationURL)?.bundleIdentifier == bundleIdentifier
        else {
            return []
        }

        let parentURL = applicationURL.deletingLastPathComponent()
        let baseName = applicationURL.deletingPathExtension().lastPathComponent
        let children = try FileManager.default.contentsOfDirectory(
            at: parentURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: []
        )
        var removed: [URL] = []
        for child in children where isOwnedStagingApplication(child, baseName: baseName) {
            guard !protectedStaging.contains(child.standardizedFileURL) else { continue }
            guard let childValues = try? child.resourceValues(
                forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
            ),
                  childValues.isDirectory == true,
                  childValues.isSymbolicLink != true
            else {
                continue
            }
            do {
                try FileManager.default.removeItem(at: child)
                removed.append(child.standardizedFileURL)
            } catch {
                continue
            }
        }
        return removed
    }

    private static func applicationIdentity(
        at applicationURL: URL,
        bundleIdentifier: String
    ) -> ApplicationIdentity? {
        guard let values = try? applicationURL.resourceValues(
            forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
        ),
              values.isDirectory == true,
              values.isSymbolicLink != true,
              let bundle = Bundle(url: applicationURL),
              bundle.bundleIdentifier == bundleIdentifier,
              let version = bundle.object(
                forInfoDictionaryKey: "CFBundleShortVersionString"
              ) as? String,
              let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
              let commit = bundle.object(
                forInfoDictionaryKey: QuillCodeDesktopBuildMetadata.commitInfoKey
              ) as? String,
              QuillCodeDesktopSemanticVersion(version) != nil,
              UInt64(build) != nil,
              QuillCodeDesktopBuildMetadata.isCanonicalCommit(commit)
        else {
            return nil
        }
        return ApplicationIdentity(version: version, build: build, commit: commit)
    }

    static func isOwnedStagingApplication(_ url: URL, baseName: String) -> Bool {
        let prefix = ".\(baseName).update-"
        let suffix = ".app"
        let name = url.lastPathComponent
        guard name.hasPrefix(prefix),
              name.hasSuffix(suffix),
              name.count > prefix.count + suffix.count
        else {
            return false
        }
        let identifierStart = name.index(name.startIndex, offsetBy: prefix.count)
        let identifierEnd = name.index(name.endIndex, offsetBy: -suffix.count)
        let identifier = String(name[identifierStart..<identifierEnd])
        guard let uuid = UUID(uuidString: identifier) else { return false }
        return uuid.uuidString.lowercased() == identifier
    }

    private struct ApplicationIdentity: Equatable {
        var version: String
        var build: String
        var commit: String
    }
}
