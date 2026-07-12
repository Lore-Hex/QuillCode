public struct WorkspaceWorktreeCreateRequest: Sendable, Hashable {
    public var path: String
    public var branch: String
    public var base: String
    public var managed: Bool

    public init(path: String, branch: String = "", base: String = "", managed: Bool = false) {
        self.path = path
        self.branch = branch
        self.base = base
        self.managed = managed
    }
}

public struct WorkspaceWorktreeOpenRequest: Sendable, Hashable {
    public var path: String

    public init(path: String) {
        self.path = path
    }
}

public struct WorkspaceWorktreeRemoveRequest: Sendable, Hashable {
    public var path: String
    public var force: Bool

    public init(path: String, force: Bool = false) {
        self.path = path
        self.force = force
    }
}

public struct WorkspaceWorktreePruneRequest: Sendable, Hashable {
    public var dryRun: Bool
    public var verbose: Bool

    public init(dryRun: Bool = false, verbose: Bool = false) {
        self.dryRun = dryRun
        self.verbose = verbose
    }
}
