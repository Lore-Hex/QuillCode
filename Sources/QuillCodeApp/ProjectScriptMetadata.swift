import Foundation
import QuillCodeCore

struct ProjectScriptMetadata: Equatable {
    var title: String?
    var description: String?
    var order: Int?
    var environment: [String: String]
    var workingDirectory: String?
    var timeoutSeconds: Int?
}

enum ProjectScriptMetadataLoader {
    static let maxMetadataBytes = 16 * 1024
    static let maxWorkingDirectoryLength = 240
    static let minTimeoutSeconds = 1
    static let maxTimeoutSeconds = 1_800

    static func load(root: URL, scriptURL: URL) -> ProjectScriptMetadata? {
        let metadataURL = scriptURL.deletingPathExtension().appendingPathExtension("json")
        let resolvedMetadataURL = metadataURL.standardizedFileURL.resolvingSymlinksInPath()
        guard resolvedMetadataURL.path.hasPrefix(root.path + "/"),
              resolvedMetadataURL.pathExtension == "json",
              let values = try? resolvedMetadataURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
              values.isRegularFile == true,
              let size = values.fileSize,
              size <= maxMetadataBytes,
              let data = try? Data(contentsOf: resolvedMetadataURL),
              let decoded = try? JSONDecoder().decode(MetadataFile.self, from: data)
        else {
            return nil
        }

        return ProjectScriptMetadata(
            title: normalized(decoded.title, maxLength: 80),
            description: normalized(decoded.description, maxLength: 200),
            order: decoded.order,
            environment: EnvironmentOverridePolicy.normalizedMetadata(decoded.environment),
            workingDirectory: normalizedWorkingDirectory(decoded.workingDirectory, root: root),
            timeoutSeconds: normalizedTimeoutSeconds(decoded.timeoutSeconds)
        )
    }

    static func title(from baseName: String) -> String {
        let words = baseName
            .replacingOccurrences(of: "_", with: "-")
            .split(separator: "-")
            .map(String.init)
        guard !words.isEmpty else { return baseName }
        return words
            .map { word in
                guard let first = word.first else { return word }
                return first.uppercased() + word.dropFirst()
            }
            .joined(separator: " ")
    }

    static func shellScriptCommand(relativePath: String, workingDirectory: String?) -> String {
        let scriptPath = scriptPath(relativePath: relativePath, from: workingDirectory)
        let shellCommand = "sh \(shellQuote(scriptPath))"
        return workingDirectory.map { "cd \(shellQuote($0)) && \(shellCommand)" } ?? shellCommand
    }

    private static func scriptPath(relativePath: String, from workingDirectory: String?) -> String {
        guard let workingDirectory else {
            return relativePath
        }
        let depth = workingDirectory
            .split(separator: "/", omittingEmptySubsequences: true)
            .count
        guard depth > 0 else {
            return relativePath
        }
        return Array(repeating: "..", count: depth).joined(separator: "/") + "/\(relativePath)"
    }

    private static func normalized(_ value: String?, maxLength: Int) -> String? {
        guard let value else { return nil }
        let collapsed = value
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !collapsed.isEmpty else { return nil }
        return String(collapsed.prefix(maxLength))
    }

    private static func normalizedWorkingDirectory(_ value: String?, root: URL) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.count <= maxWorkingDirectoryLength,
              !trimmed.hasPrefix("/"),
              !trimmed.contains("\0"),
              trimmed.rangeOfCharacter(from: .newlines) == nil
        else {
            return nil
        }

        let components = trimmed
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
        guard !components.isEmpty,
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." })
        else {
            return nil
        }

        let relativePath = components.joined(separator: "/")
        let directoryURL = root
            .appendingPathComponent(relativePath)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        guard isPath(directoryURL.path, inside: root.path) else {
            return nil
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directoryURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            return nil
        }
        return relativePath
    }

    private static func normalizedTimeoutSeconds(_ value: Int?) -> Int? {
        guard let value,
              (minTimeoutSeconds...maxTimeoutSeconds).contains(value)
        else {
            return nil
        }
        return value
    }

    private static func isPath(_ path: String, inside rootPath: String) -> Bool {
        path == rootPath || path.hasPrefix(rootPath + "/")
    }

    private static func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private struct MetadataFile: Decodable {
        var title: String?
        var description: String?
        var order: Int?
        var environment: [String: String]?
        var workingDirectory: String?
        var timeoutSeconds: Int?

        enum CodingKeys: String, CodingKey {
            case title
            case description
            case order
            case environment
            case workingDirectory
            case workingDirectorySnake = "working_directory"
            case timeoutSeconds
            case timeoutSecondsSnake = "timeout_seconds"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            title = try container.decodeIfPresent(String.self, forKey: .title)
            description = try container.decodeIfPresent(String.self, forKey: .description)
            order = try container.decodeIfPresent(Int.self, forKey: .order)
            environment = try container.decodeIfPresent([String: String].self, forKey: .environment)
            workingDirectory = try container.decodeIfPresent(String.self, forKey: .workingDirectory)
                ?? container.decodeIfPresent(String.self, forKey: .workingDirectorySnake)
            timeoutSeconds = try container.decodeIfPresent(Int.self, forKey: .timeoutSeconds)
                ?? container.decodeIfPresent(Int.self, forKey: .timeoutSecondsSnake)
        }
    }
}
