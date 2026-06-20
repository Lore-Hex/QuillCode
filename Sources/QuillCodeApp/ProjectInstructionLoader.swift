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

    public static func load(
        from projectRoot: URL,
        relativePaths: [String] = defaultRelativePaths,
        maxFileBytes: Int = maxFileBytes,
        maxTotalBytes: Int = maxTotalBytes
    ) -> [ProjectInstruction] {
        let root = projectRoot.standardizedFileURL.resolvingSymlinksInPath()
        var totalBytes = 0
        var instructions: [ProjectInstruction] = []

        for relativePath in relativePaths {
            guard totalBytes < maxTotalBytes else { break }
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
