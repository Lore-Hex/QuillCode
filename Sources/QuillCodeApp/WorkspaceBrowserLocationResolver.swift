import Foundation

struct WorkspaceBrowserLocationResolver: Sendable, Hashable {
    var workspaceRoot: URL?

    func resolve(_ rawValue: String) -> URL? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let url = URL(string: trimmed),
           let scheme = url.scheme?.lowercased(),
           ["http", "https", "file"].contains(scheme) {
            return url
        }

        if trimmed.hasPrefix("localhost")
            || trimmed.hasPrefix("127.0.0.1")
            || trimmed.hasPrefix("[::1]") {
            return URL(string: "http://\(trimmed)")
        }

        if let workspaceRoot,
           let fileURL = projectFileURL(trimmed, workspaceRoot: workspaceRoot) {
            return fileURL
        }

        if workspaceRoot != nil, looksLikeProjectRelativeFile(trimmed) {
            return nil
        }

        if trimmed.hasPrefix("/") {
            let fileURL = URL(fileURLWithPath: trimmed)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                return fileURL.standardizedFileURL
            }
        }

        if let url = domainShorthandURL(trimmed) {
            return url
        }

        return nil
    }

    static func canFetchSnapshot(for url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    static func snapshotFetchMessage(for error: any Error) -> String {
        if let failure = error as? BrowserPageFetchFailure {
            return failure.description
        }
        return error.localizedDescription
    }

    private func looksLikeProjectRelativeFile(_ value: String) -> Bool {
        if value.hasPrefix(".") || value.contains("/") || value.contains("\\") {
            return true
        }

        let knownFileExtensions: Set<String> = [
            "css", "htm", "html", "js", "json", "md", "pdf", "svg", "txt", "xml"
        ]
        guard let ext = value.split(separator: ".").last?.lowercased(),
              ext != value.lowercased()
        else {
            return false
        }
        return knownFileExtensions.contains(ext)
    }

    private func projectFileURL(_ relativePath: String, workspaceRoot: URL) -> URL? {
        guard !relativePath.contains("..") else { return nil }
        let root = workspaceRoot.standardizedFileURL.resolvingSymlinksInPath()
        let fileURL = root
            .appendingPathComponent(relativePath)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        guard (fileURL.path == root.path || fileURL.path.hasPrefix(root.path + "/")),
              FileManager.default.fileExists(atPath: fileURL.path)
        else {
            return nil
        }
        return fileURL
    }

    private func domainShorthandURL(_ value: String) -> URL? {
        guard !value.contains("\\"),
              value.rangeOfCharacter(from: .whitespacesAndNewlines) == nil
        else {
            return nil
        }

        let firstPathComponent = value.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? value
        guard firstPathComponent.contains("."),
              !firstPathComponent.hasPrefix("."),
              !firstPathComponent.hasSuffix("."),
              !firstPathComponent.contains("..")
        else {
            return nil
        }

        let components = firstPathComponent.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count >= 2,
              components.allSatisfy({ !$0.isEmpty }),
              let suffix = components.last?.lowercased(),
              !Self.localFileSuffixes.contains(suffix)
        else {
            return nil
        }

        return URL(string: "https://\(value)")
    }

    private static let localFileSuffixes: Set<String> = [
        "css", "gif", "htm", "html", "jpeg", "jpg", "js", "json", "md", "pdf",
        "png", "svg", "txt", "webp"
    ]
}
