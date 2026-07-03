public struct GitFetchOptions: Equatable, Sendable {
    public let remote: String
    public let prune: Bool

    public init(remote: String? = nil, prune: Bool = false) throws {
        self.remote = try GitInputValidator.safeName(GitInputValidator.trimmedNonEmpty(remote) ?? "origin")
        self.prune = prune
    }

    public var gitArguments: [String] {
        var arguments = ["fetch"]
        if prune {
            arguments.append("--prune")
        }
        arguments.append(remote)
        return arguments
    }
}

public struct GitPullOptions: Equatable, Sendable {
    public let remote: String?
    public let branch: String?
    public let ffOnly: Bool

    public init(
        remote: String? = nil,
        branch: String? = nil,
        ffOnly: Bool = true
    ) throws {
        self.remote = try GitInputValidator.trimmedNonEmpty(remote).map(GitInputValidator.safeName)
        self.branch = try GitInputValidator.trimmedNonEmpty(branch).map(GitInputValidator.safeName)
        self.ffOnly = ffOnly
    }

    public var gitArguments: [String] {
        var arguments = ["pull"]
        if ffOnly {
            arguments.append("--ff-only")
        }
        if let remote {
            arguments.append(remote)
            if let branch {
                arguments.append(branch)
            }
        } else if let branch {
            arguments += ["origin", branch]
        }
        return arguments
    }
}
