public enum GitDiffSelection: Equatable, Sendable {
    case unstaged
    case staged
    case commit(String)
    case branch(String)
}

public struct GitDiffOptions: Equatable, Sendable {
    public let selection: GitDiffSelection

    public init(
        staged: Bool = false,
        commit: String? = nil,
        baseBranch: String? = nil
    ) throws {
        let commit = try Self.validatedReference(commit)
        let baseBranch = try Self.validatedReference(baseBranch)
        let selectorCount = (staged ? 1 : 0) + (commit == nil ? 0 : 1) + (baseBranch == nil ? 0 : 1)
        guard selectorCount <= 1 else {
            throw GitToolError.ambiguousDiffSelection
        }

        if staged {
            selection = .staged
        } else if let commit {
            selection = .commit(commit)
        } else if let baseBranch {
            selection = .branch(baseBranch)
        } else {
            selection = .unstaged
        }
    }

    public var gitArguments: [String] {
        switch selection {
        case .unstaged:
            return ["diff"]
        case .staged:
            return ["diff", "--staged"]
        case .commit(let reference):
            return [
                "show", "--format=", "--no-ext-diff", "--find-renames", "--find-copies",
                reference, "--"
            ]
        case .branch(let baseBranch):
            return [
                "diff", "--no-ext-diff", "--find-renames", "--find-copies",
                "\(baseBranch)...HEAD", "--"
            ]
        }
    }

    private static func validatedReference(_ value: String?) throws -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw GitToolError.emptyDiffReference
        }
        return try GitInputValidator.safeName(trimmed)
    }
}
