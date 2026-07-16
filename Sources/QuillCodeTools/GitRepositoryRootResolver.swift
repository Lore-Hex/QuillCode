import Foundation

public struct GitRepositoryRoots: Sendable, Hashable {
    public var checkout: URL
    public var configuration: URL

    public init(checkout: URL, configuration: URL) {
        self.checkout = checkout
        self.configuration = configuration
    }
}

/// Resolves repository roots without launching Git or executing repository-controlled code.
/// Linked worktrees read project configuration from their primary checkout, matching Codex.
public enum GitRepositoryRootResolver {
    public static let maxMarkerBytes = 4 * 1024

    public static func resolve(containing directory: URL) -> GitRepositoryRoots? {
        guard let checkout = nearestCheckout(containing: directory) else { return nil }
        let marker = checkout.appendingPathComponent(".git", isDirectory: false)
        guard !isDirectory(marker),
              let gitDirectory = referencedDirectory(in: marker),
              let commonDirectory = referencedDirectory(
                in: gitDirectory.appendingPathComponent("commondir", isDirectory: false)
              ),
              commonDirectory.lastPathComponent == ".git"
        else {
            return GitRepositoryRoots(checkout: checkout, configuration: checkout)
        }

        let primaryCheckout = commonDirectory.deletingLastPathComponent().standardizedFileURL
        let primaryMarker = primaryCheckout.appendingPathComponent(".git", isDirectory: true)
        guard primaryMarker.standardizedFileURL.path == commonDirectory.standardizedFileURL.path,
              isDirectory(primaryMarker)
        else {
            return GitRepositoryRoots(checkout: checkout, configuration: checkout)
        }
        return GitRepositoryRoots(checkout: checkout, configuration: primaryCheckout)
    }

    private static func nearestCheckout(containing directory: URL) -> URL? {
        var candidate = directory.standardizedFileURL
        while true {
            if FileManager.default.fileExists(
                atPath: candidate.appendingPathComponent(".git", isDirectory: false).path
            ) {
                return candidate
            }
            let parent = parentDirectory(of: candidate)
            guard parent.path != candidate.path else { return nil }
            candidate = parent
        }
    }

    private static func referencedDirectory(in marker: URL) -> URL? {
        guard let markerText = boundedText(from: marker) else { return nil }
        let reference: String
        if marker.lastPathComponent == ".git" {
            guard markerText.hasPrefix("gitdir:") else { return nil }
            reference = String(markerText.dropFirst("gitdir:".count))
                .trimmingCharacters(in: .whitespaces)
        } else {
            reference = markerText
        }
        guard !reference.isEmpty, !reference.contains("\0") else { return nil }
        let base = marker.deletingLastPathComponent()
        let resolved = URL(
            fileURLWithPath: reference,
            relativeTo: reference.hasPrefix("/") ? nil : base
        ).standardizedFileURL.resolvingSymlinksInPath()
        guard isDirectory(resolved) else { return nil }
        return resolved
    }

    private static func boundedText(from file: URL) -> String? {
        guard (try? FileManager.default.destinationOfSymbolicLink(atPath: file.path)) == nil,
              let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
              values.isRegularFile == true,
              let fileSize = values.fileSize,
              fileSize <= maxMarkerBytes,
              let data = try? Data(contentsOf: file, options: [.mappedIfSafe]),
              data.count <= maxMarkerBytes,
              let text = String(data: data, encoding: .utf8)
        else { return nil }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    private static func parentDirectory(of directory: URL) -> URL {
        let path = directory.standardizedFileURL.path
        let parentPath = NSString(string: path).deletingLastPathComponent
        return URL(
            fileURLWithPath: parentPath.isEmpty ? "/" : parentPath,
            isDirectory: true
        ).standardizedFileURL
    }
}
