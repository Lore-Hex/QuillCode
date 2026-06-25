import Foundation
import QuillCodeCore

public enum ProjectInstructionLoader {
    public static let defaultRelativePaths = [
        "AGENTS.md",
        ".quillcode/rules.md",
        ".quillcode/instructions.md"
    ]

    public static let maxFileBytes = 50_000
    public static let maxTotalBytes = 100_000
    public static let maxScannedDirectories = 400
    public static let maxInstructionFiles = 40

    private static let ignoredDirectoryNames: Set<String> = [
        ".build",
        ".git",
        ".hg",
        ".svn",
        ".quillcode",
        "DerivedData",
        "node_modules",
        "Package.resolved"
    ]

    public static func load(
        from projectRoot: URL,
        relativePaths: [String] = defaultRelativePaths,
        maxFileBytes: Int = maxFileBytes,
        maxTotalBytes: Int = maxTotalBytes,
        includeNested: Bool = true,
        maxScannedDirectories: Int = maxScannedDirectories,
        maxInstructionFiles: Int = maxInstructionFiles
    ) -> [ProjectInstruction] {
        let root = projectRoot.standardizedFileURL.resolvingSymlinksInPath()
        var totalBytes = 0
        var instructions: [ProjectInstruction] = []
        let candidatePaths = instructionCandidatePaths(
            root: root,
            baseRelativePaths: relativePaths,
            includeNested: includeNested,
            maxScannedDirectories: maxScannedDirectories
        )

        for relativePath in candidatePaths {
            guard totalBytes < maxTotalBytes,
                  instructions.count < maxInstructionFiles
            else { break }
            let remainingBytes = maxTotalBytes - totalBytes
            let fileLimit = min(maxFileBytes, remainingBytes)
            guard let instruction = loadFile(
                root: root,
                relativePath: relativePath,
                maxBytes: fileLimit
            ) else {
                continue
            }
            totalBytes += instruction.byteCount
            instructions.append(instruction)
        }

        return instructions
    }

    private static func instructionCandidatePaths(
        root: URL,
        baseRelativePaths: [String],
        includeNested: Bool,
        maxScannedDirectories: Int
    ) -> [String] {
        var candidates = baseRelativePaths
        guard includeNested, maxScannedDirectories > 0 else {
            return candidates
        }

        let directories = nestedDirectoryPaths(root: root, maxScannedDirectories: maxScannedDirectories)
        for directory in directories {
            for relativePath in baseRelativePaths {
                candidates.append("\(directory)/\(relativePath)")
            }
        }
        return candidates
    }

    private static func nestedDirectoryPaths(root: URL, maxScannedDirectories: Int) -> [String] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsPackageDescendants]
        ) else {
            return []
        }

        var directories: [String] = []
        for case let url as URL in enumerator {
            guard directories.count < maxScannedDirectories else { break }
            guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                  values.isDirectory == true
            else {
                continue
            }

            let directoryName = url.lastPathComponent
            if values.isSymbolicLink == true || shouldSkipDirectory(named: directoryName) {
                enumerator.skipDescendants()
                continue
            }

            guard let relativePath = relativePath(from: root, to: url) else {
                enumerator.skipDescendants()
                continue
            }
            directories.append(relativePath)
        }

        return directories.sorted { lhs, rhs in
            let lhsDepth = lhs.split(separator: "/").count
            let rhsDepth = rhs.split(separator: "/").count
            if lhsDepth != rhsDepth {
                return lhsDepth < rhsDepth
            }
            return lhs.localizedStandardCompare(rhs) == .orderedAscending
        }
    }

    private static func shouldSkipDirectory(named name: String) -> Bool {
        ignoredDirectoryNames.contains(name) || name.hasPrefix(".")
    }

    private static func relativePath(from root: URL, to directory: URL) -> String? {
        let rootPath = root.standardizedFileURL.path
        let directoryPath = directory.standardizedFileURL.resolvingSymlinksInPath().path
        guard directoryPath.hasPrefix(rootPath + "/") else {
            return nil
        }
        let start = directoryPath.index(directoryPath.startIndex, offsetBy: rootPath.count + 1)
        let relativePath = String(directoryPath[start...])
        return relativePath.isEmpty ? nil : relativePath
    }

    private static func loadFile(root: URL, relativePath: String, maxBytes: Int) -> ProjectInstruction? {
        guard maxBytes > 0,
              !relativePath.contains("..")
        else {
            return nil
        }

        let fileURL = root
            .appendingPathComponent(relativePath)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        guard fileURL.path.hasPrefix(root.path + "/") || fileURL.path == root.path else {
            return nil
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDirectory),
              !isDirectory.boolValue,
              let handle = try? FileHandle(forReadingFrom: fileURL)
        else {
            return nil
        }
        defer { try? handle.close() }

        let data = handle.readData(ofLength: maxBytes + 1)
        let wasTruncated = data.count > maxBytes
        let boundedData = wasTruncated ? data.prefix(maxBytes) : data[...]
        guard var content = String(data: Data(boundedData), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !content.isEmpty
        else {
            return nil
        }

        if wasTruncated {
            content += "\n\n[QuillCode truncated this instruction file at \(maxBytes) bytes.]"
        }

        return ProjectInstruction(
            path: relativePath,
            scopePath: ProjectInstruction.scopePath(for: relativePath),
            title: title(for: relativePath),
            content: content,
            byteCount: min(data.count, maxBytes),
            wasTruncated: wasTruncated
        )
    }

    private static func title(for relativePath: String) -> String {
        switch relativePath {
        case "AGENTS.md":
            return "Project AGENTS.md"
        case ".quillcode/rules.md":
            return "QuillCode rules"
        case ".quillcode/instructions.md":
            return "QuillCode instructions"
        default:
            return relativePath
        }
    }
}
