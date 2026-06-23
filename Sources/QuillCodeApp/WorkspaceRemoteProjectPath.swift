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
        for component in trimmed.split(separator: "/", omittingEmptySubsequences: true).map(String.init) {
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
        guard let workspace = normalizedAbsolutePOSIXPath(connection.path) else {
            throw GitToolError.outsideWorkspace(connection.path)
        }
        let parent = posixParentPath(workspace)
        let candidateRaw = trimmed.hasPrefix("/") ? trimmed : "\(parent)/\(trimmed)"
        guard let candidate = normalizedAbsolutePOSIXPath(candidateRaw),
              isPOSIXPath(candidate, inside: parent) else {
            throw GitToolError.outsideWorkspace(rawPath)
        }
        guard candidate != workspace else {
            throw GitToolError.mainWorkspaceWorktreePath
        }
        return candidate
    }

    static func path(_ base: String, appending relativePath: String) -> String {
        let trimmedBase = base.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedRelative = relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedRelative.isEmpty else { return trimmedBase.isEmpty ? "~" : trimmedBase }

        let isAbsolute = trimmedBase.hasPrefix("/")
        let isHome = trimmedBase == "~" || trimmedBase.hasPrefix("~/")
        let baseRemainder: String
        if isAbsolute {
            baseRemainder = trimmedBase.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        } else if isHome {
            baseRemainder = String(trimmedBase.dropFirst()).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        } else {
            baseRemainder = trimmedBase.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }

        var components: [String] = []
        for component in ([baseRemainder, trimmedRelative].filter { !$0.isEmpty }.joined(separator: "/")).split(separator: "/") {
            switch component {
            case "", ".":
                continue
            case "..":
                if !components.isEmpty {
                    components.removeLast()
                } else if !isAbsolute && !isHome {
                    components.append(String(component))
                }
            default:
                components.append(String(component))
            }
        }

        let suffix = components.joined(separator: "/")
        if isAbsolute {
            return "/" + suffix
        }
        if isHome || trimmedBase.isEmpty {
            return suffix.isEmpty ? "~" : "~/" + suffix
        }
        return suffix.isEmpty ? "." : suffix
    }

    private static func normalizedAbsolutePOSIXPath(_ rawPath: String) -> String? {
        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("/"),
              !trimmed.contains("\0"),
              trimmed.rangeOfCharacter(from: .newlines) == nil else {
            return nil
        }
        var components: [String] = []
        for component in trimmed.split(separator: "/", omittingEmptySubsequences: true).map(String.init) {
            switch component {
            case ".":
                continue
            case "..":
                guard !components.isEmpty else { return nil }
                components.removeLast()
            default:
                components.append(component)
            }
        }
        return components.isEmpty ? "/" : "/\(components.joined(separator: "/"))"
    }

    private static func posixParentPath(_ path: String) -> String {
        let components = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard components.count > 1 else { return "/" }
        return "/\(components.dropLast().joined(separator: "/"))"
    }

    private static func isPOSIXPath(_ path: String, inside parent: String) -> Bool {
        if parent == "/" {
            return path.hasPrefix("/")
        }
        return path == parent || path.hasPrefix("\(parent)/")
    }
}
