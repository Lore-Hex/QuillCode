import Foundation

public enum GitInputValidator {
    public static let safeNameCharacters = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._/-"

    public static func trimmedNonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    public static func safeName(_ value: String) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw GitToolError.emptyBranch
        }
        let allowed = CharacterSet(charactersIn: safeNameCharacters)
        guard trimmed.rangeOfCharacter(from: allowed.inverted) == nil,
              !trimmed.hasPrefix("-"),
              !trimmed.contains("..")
        else {
            throw GitToolError.invalidGitName(value)
        }
        return trimmed
    }

    public static func safeRelativePath(_ path: String, cwd: URL) throws -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw GitToolError.emptyPath
        }

        let root = cwd.standardizedFileURL
        let candidate = trimmed.hasPrefix("/")
            ? URL(fileURLWithPath: trimmed)
            : root.appendingPathComponent(trimmed)
        let standardized = candidate.standardizedFileURL
        let rootPath = root.path.hasSuffix("/") ? root.path : "\(root.path)/"
        // Shared workspace boundary: lexical AND symlink-resolved, so a symlink inside the workspace
        // pointing outside cannot let a staged/restored path escape (matches FileToolExecutor).
        guard WorkspaceBoundary.isWithin(candidate, root: cwd) else {
            throw GitToolError.outsideWorkspace(path)
        }
        guard standardized.path != root.path else {
            return "."
        }
        return String(standardized.path.dropFirst(rootPath.count))
    }
}
