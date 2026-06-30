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

        guard let relativePath = WorkspaceBoundary.safeRelativePath(trimmed, root: cwd) else {
            throw GitToolError.outsideWorkspace(path)
        }
        return relativePath
    }
}
