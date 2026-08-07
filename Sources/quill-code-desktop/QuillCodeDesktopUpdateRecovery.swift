import Foundation

protocol QuillCodeDesktopUpdateRecovering: Sendable {
    func recoverInterruptedUpdate(
        configuration: QuillCodeDesktopUpdateConfiguration
    ) async
}

struct QuillCodeDesktopUpdateRecovery: QuillCodeDesktopUpdateRecovering, Sendable {
    static let productionGracePeriod: TimeInterval = 2 * 60

    private let gracePeriod: TimeInterval

    init(gracePeriod: TimeInterval = productionGracePeriod) {
        self.gracePeriod = gracePeriod.isFinite && gracePeriod >= 0
            ? gracePeriod
            : Self.productionGracePeriod
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
        _ = try? await Task.detached(priority: .utility) {
            try Self.removeOrphanedStagingApplications(
                beside: applicationURL,
                bundleIdentifier: bundleIdentifier
            )
        }.value
    }

    @discardableResult
    static func removeOrphanedStagingApplications(
        beside applicationURL: URL,
        bundleIdentifier: String
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

    private static func isOwnedStagingApplication(_ url: URL, baseName: String) -> Bool {
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
}
