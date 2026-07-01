import Foundation
import QuillCodeCore
import QuillCodeTools

enum WorkspaceRemoteProjectPath {
    static func relativePath(_ rawPath: String) throws -> String {
        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.hasPrefix("/"),
              !trimmed.hasPrefix("~"),
              !trimmed.contains("\0"),
              trimmed.rangeOfCharacter(from: .newlines) == nil
        else {
            throw FileToolError.outsideWorkspace(rawPath)
        }

        var components: [String] = []
        let rawComponents = trimmed
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
        for component in rawComponents {
            switch component {
            case ".":
                continue
            case "..":
                throw FileToolError.outsideWorkspace(rawPath)
            default:
                components.append(component)
            }
        }
        guard !components.isEmpty else {
            throw FileToolError.outsideWorkspace(rawPath)
        }
        return components.joined(separator: "/")
    }

    static func directory(for relativePath: String) -> String {
        let directory = (relativePath as NSString).deletingLastPathComponent
        return directory.isEmpty || directory == "." ? "." : directory
    }

    static func artifactPath(
        connection: ProjectConnection,
        relativePath: String
    ) -> String {
        var copy = connection
        copy.path = path(connection.path, appending: relativePath)
        return copy.displayLabel
    }

    static func artifactPath(
        connection: ProjectConnection,
        absolutePath: String
    ) -> String {
        var copy = connection
        copy.path = absolutePath
        return copy.displayLabel
    }

    static func shellConnection(
        _ connection: ProjectConnection,
        cwd: String?
    ) -> ProjectConnection {
        let trimmedCWD = cwd?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmedCWD.isEmpty else { return connection }
        var copy = connection
        if trimmedCWD.hasPrefix("/") || trimmedCWD.hasPrefix("~") {
            copy.path = trimmedCWD
        } else {
            copy.path = path(connection.path, appending: trimmedCWD)
        }
        return copy
    }

    static func worktreePath(
        _ rawPath: String,
        connection: ProjectConnection
    ) throws -> String {
        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.hasPrefix("~"),
              !trimmed.contains("\0"),
              trimmed.rangeOfCharacter(from: .newlines) == nil
        else {
            throw GitToolError.emptyPath
        }
        guard let workspace = WorkspacePOSIXPathNormalizer.absolutePath(connection.path) else {
            throw GitToolError.outsideWorkspace(connection.path)
        }
        let parent = WorkspacePOSIXPathNormalizer.parentPath(of: workspace)
        let candidateRaw = trimmed.hasPrefix("/") ? trimmed : "\(parent)/\(trimmed)"
        guard let candidate = WorkspacePOSIXPathNormalizer.absolutePath(candidateRaw),
              WorkspacePOSIXPathNormalizer.isPath(candidate, inside: parent) else {
            throw GitToolError.outsideWorkspace(rawPath)
        }
        guard candidate != workspace else {
            throw GitToolError.mainWorkspaceWorktreePath
        }
        return candidate
    }

    static func path(_ base: String, appending relativePath: String) -> String {
        WorkspacePOSIXPathNormalizer.appending(relativePath, to: base)
    }
}
