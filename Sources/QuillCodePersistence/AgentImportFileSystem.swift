import Foundation
import QuillCodeCore

enum AgentImportFileSystem {
    static let maximumFileBytes = 1_000_000
    static let maximumDirectoryFiles = 512
    static let maximumDirectoryBytes = 20_000_000

    static func regularFile(
        _ url: URL,
        inside root: URL,
        maximumBytes: Int = maximumFileBytes
    ) -> URL? {
        let root = root.standardizedFileURL.resolvingSymlinksInPath()
        let candidate = url.standardizedFileURL
        guard WorkspaceBoundary.isWithin(candidate, root: root),
              let values = try? candidate.resourceValues(
                forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
              ),
              values.isRegularFile == true,
              values.isSymbolicLink != true,
              let fileSize = values.fileSize,
              fileSize >= 0,
              fileSize <= maximumBytes
        else { return nil }
        let resolved = candidate.resolvingSymlinksInPath()
        return WorkspaceBoundary.isWithin(resolved, root: root) ? resolved : nil
    }

    static func directory(_ url: URL, inside root: URL) -> URL? {
        let root = root.standardizedFileURL.resolvingSymlinksInPath()
        let candidate = url.standardizedFileURL
        guard WorkspaceBoundary.isWithin(candidate, root: root),
              let values = try? candidate.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
              values.isDirectory == true,
              values.isSymbolicLink != true
        else { return nil }
        let resolved = candidate.resolvingSymlinksInPath()
        return WorkspaceBoundary.isWithin(resolved, root: root) ? resolved : nil
    }

    static func boundedDirectoryFiles(
        at directory: URL,
        root: URL,
        maximumFiles: Int = maximumDirectoryFiles,
        maximumBytes: Int = maximumDirectoryBytes
    ) -> [URL]? {
        guard maximumFiles > 0, maximumBytes > 0,
              let directory = self.directory(directory, inside: root),
              let enumerator = FileManager.default.enumerator(
                at: directory,
                includingPropertiesForKeys: [
                    .isRegularFileKey,
                    .isDirectoryKey,
                    .isSymbolicLinkKey,
                    .fileSizeKey
                ],
                options: []
              )
        else { return nil }

        var files: [URL] = []
        var byteCount = 0
        for case let candidate as URL in enumerator {
            guard WorkspaceBoundary.isWithin(candidate, root: directory),
                  let values = try? candidate.resourceValues(
                    forKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey]
                  )
            else { return nil }
            if values.isSymbolicLink == true { return nil }
            let relative = relativePath(candidate, inside: directory)
            if values.isDirectory == true {
                if shouldExcludeDirectory(relative) { enumerator.skipDescendants() }
                continue
            }
            guard values.isRegularFile == true,
                  let fileSize = values.fileSize,
                  fileSize >= 0
            else { return nil }
            if shouldExcludeFile(relative) { continue }
            files.append(candidate)
            byteCount += fileSize
            guard files.count <= maximumFiles, byteCount <= maximumBytes else { return nil }
        }
        return files.sorted { relativePath($0, inside: directory) < relativePath($1, inside: directory) }
    }

    static func readData(
        _ url: URL,
        inside root: URL,
        maximumBytes: Int = maximumFileBytes
    ) -> Data? {
        guard let file = regularFile(url, inside: root, maximumBytes: maximumBytes),
              let data = try? Data(contentsOf: file),
              data.count <= maximumBytes
        else { return nil }
        return data
    }

    static func readText(
        _ url: URL,
        inside root: URL,
        maximumBytes: Int = maximumFileBytes
    ) -> String? {
        guard let data = readData(url, inside: root, maximumBytes: maximumBytes) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func copyDirectory(
        _ source: URL,
        sourceRoot: URL,
        to destination: URL,
        destinationRoot: URL
    ) throws -> Int {
        guard let source = directory(source, inside: sourceRoot),
              let files = boundedDirectoryFiles(at: source, root: sourceRoot),
              let destination = safeDestination(destination, inside: destinationRoot),
              !FileManager.default.fileExists(atPath: destination.path)
        else {
            throw AgentImportError.invalidSourceOrDestination
        }
        try createDirectory(destination.deletingLastPathComponent(), inside: destinationRoot)
        var createdDestination = false
        do {
            try FileManager.default.createDirectory(
                at: destination,
                withIntermediateDirectories: false
            )
            createdDestination = true
            for file in files {
                let relative = relativePath(file, inside: source)
                let target = destination.appendingPathComponent(relative)
                try createDirectory(target.deletingLastPathComponent(), inside: destinationRoot)
                guard safeDestination(target, inside: destinationRoot) != nil else {
                    throw AgentImportError.invalidSourceOrDestination
                }
                try FileManager.default.copyItem(at: file, to: target)
            }
        } catch {
            if createdDestination {
                removeCreatedItem(destination, inside: destinationRoot)
            }
            throw error
        }
        return files.count
    }

    static func writeNew(
        _ data: Data,
        to destination: URL,
        inside destinationRoot: URL
    ) throws {
        guard data.count <= maximumDirectoryBytes,
              let destination = safeDestination(destination, inside: destinationRoot)
        else {
            throw AgentImportError.destinationAlreadyExists
        }
        try createDirectory(destination.deletingLastPathComponent(), inside: destinationRoot)
        let temporary = destination.deletingLastPathComponent().appendingPathComponent(
            ".quillcode-import-\(UUID().uuidString.lowercased()).tmp"
        )
        guard safeDestination(temporary, inside: destinationRoot) != nil else {
            throw AgentImportError.invalidSourceOrDestination
        }
        defer { try? FileManager.default.removeItem(at: temporary) }
        try data.write(to: temporary, options: .withoutOverwriting)
        // A hard-link publish is atomic and fails with EEXIST instead of replacing a file that
        // appeared after validation. Removing the temporary name leaves the destination intact.
        try FileManager.default.linkItem(at: temporary, to: destination)
    }

    static func removeCreatedArtifacts(_ artifacts: [AgentImportCreatedArtifact]) {
        let ordered = artifacts.sorted { lhs, rhs in
            lhs.path.split(separator: "/").count > rhs.path.split(separator: "/").count
        }
        for artifact in ordered {
            let root = URL(fileURLWithPath: artifact.projectRootPath)
                .standardizedFileURL
                .resolvingSymlinksInPath()
            let requested = URL(fileURLWithPath: artifact.path).standardizedFileURL
            guard requested.path != root.path,
                  WorkspaceBoundary.isWithin(requested, root: root)
            else { continue }

            let parent = requested.deletingLastPathComponent().resolvingSymlinksInPath()
            guard WorkspaceBoundary.isWithin(parent, root: root) else { continue }
            let validated = parent.appendingPathComponent(requested.lastPathComponent)
            try? FileManager.default.removeItem(at: validated)
        }
    }

    static func removeCreatedItem(_ destination: URL, inside root: URL) {
        let root = root.standardizedFileURL.resolvingSymlinksInPath()
        let requested = destination.standardizedFileURL
        guard requested.path != root.path,
              WorkspaceBoundary.isWithin(requested, root: root)
        else { return }
        let parent = requested.deletingLastPathComponent().resolvingSymlinksInPath()
        guard WorkspaceBoundary.isWithin(parent, root: root) else { return }
        try? FileManager.default.removeItem(
            at: parent.appendingPathComponent(requested.lastPathComponent)
        )
    }

    static func createDirectory(_ directory: URL, inside root: URL) throws {
        let standardizedRoot = root.standardizedFileURL
        if !FileManager.default.fileExists(atPath: standardizedRoot.path) {
            try FileManager.default.createDirectory(
                at: standardizedRoot,
                withIntermediateDirectories: true
            )
        }
        let rootValues = try standardizedRoot.resourceValues(
            forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
        )
        guard rootValues.isDirectory == true, rootValues.isSymbolicLink != true else {
            throw AgentImportError.invalidSourceOrDestination
        }
        let resolvedRoot = standardizedRoot.resolvingSymlinksInPath()
        if directory.standardizedFileURL.resolvingSymlinksInPath().path == resolvedRoot.path {
            return
        }
        guard let destination = safeDestination(directory, inside: root) else {
            throw AgentImportError.invalidSourceOrDestination
        }
        var current = resolvedRoot
        let relative = relativePath(destination, inside: current)
        for component in relative.split(separator: "/").map(String.init) {
            current.appendPathComponent(component, isDirectory: true)
            if FileManager.default.fileExists(atPath: current.path) {
                let values = try current.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                guard values.isDirectory == true, values.isSymbolicLink != true else {
                    throw AgentImportError.invalidSourceOrDestination
                }
            } else {
                try FileManager.default.createDirectory(at: current, withIntermediateDirectories: false)
            }
            guard WorkspaceBoundary.isWithin(current.resolvingSymlinksInPath(), root: root) else {
                throw AgentImportError.invalidSourceOrDestination
            }
        }
    }

    static func relativePath(_ url: URL, inside root: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path != rootPath, path.hasPrefix(rootPath + "/") else { return "" }
        return String(path.dropFirst(rootPath.count + 1))
    }

    static func sanitizedComponent(_ value: String, fallback: String = "imported") -> String {
        let normalized = value.lowercased().map { character -> Character in
            if character.isLetter || character.isNumber || character == "-" { return character }
            return "-"
        }
        let collapsed = String(normalized)
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")
        return String((collapsed.isEmpty ? fallback : collapsed).prefix(80))
    }

    static func fingerprint(kind: AgentImportItemKind, path: String, data: Data) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in Data("\(kind.rawValue)\n\(path)\n".utf8) + data {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(format: "%016llx", hash)
    }

    private static func safeDestination(_ url: URL, inside root: URL) -> URL? {
        let root = root.standardizedFileURL.resolvingSymlinksInPath()
        let destination = url.standardizedFileURL
        guard destination.path != root.path,
              WorkspaceBoundary.isWithin(destination, root: root)
        else { return nil }
        return destination
    }

    private static func shouldExcludeDirectory(_ relativePath: String) -> Bool {
        let components = relativePath.split(separator: "/").map(String.init)
        return components.contains { component in
            component == ".git"
                || component == ".svn"
                || component == ".hg"
                || component == "node_modules"
                || component == ".build"
        }
    }

    private static func shouldExcludeFile(_ relativePath: String) -> Bool {
        let name = URL(fileURLWithPath: relativePath).lastPathComponent.lowercased()
        if name == ".env" || name.hasPrefix(".env.") { return true }
        if name.hasSuffix(".pem") || name.hasSuffix(".key") || name.hasSuffix(".p12") { return true }
        return name.contains("credentials") || name.contains("private-key") || name.contains("private_key")
    }
}

public enum AgentImportError: Error, Sendable, CustomStringConvertible {
    case invalidSourceOrDestination
    case destinationAlreadyExists
    case unsupportedSource
    case noSelectedProjects

    public var description: String {
        switch self {
        case .invalidSourceOrDestination:
            "An import source or destination failed boundary validation."
        case .destinationAlreadyExists:
            "Import would overwrite an existing QuillCode file."
        case .unsupportedSource:
            "This import source is not supported."
        case .noSelectedProjects:
            "Choose at least one project for project-scoped setup."
        }
    }
}
