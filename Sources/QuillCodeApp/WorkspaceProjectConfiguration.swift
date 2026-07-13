import Foundation

struct WorktreeSetupConfiguration: Equatable {
    static let defaultScriptPath = ".quillcode/setup.sh"
    static let defaultMacOSScriptPath = ".quillcode/setup.macos.sh"
    static let defaultLinuxScriptPath = ".quillcode/setup.linux.sh"

    var scriptPath: String
    var macOSScriptPath: String
    var linuxScriptPath: String
    var isExplicitlyConfigured: Bool
    var isValid: Bool

    init(
        scriptPath: String = defaultScriptPath,
        macOSScriptPath: String = defaultMacOSScriptPath,
        linuxScriptPath: String = defaultLinuxScriptPath,
        isExplicitlyConfigured: Bool = false
    ) {
        let normalizedScriptPath = Self.normalizedScriptPath(scriptPath)
        let normalizedMacOSScriptPath = Self.normalizedScriptPath(macOSScriptPath)
        let normalizedLinuxScriptPath = Self.normalizedScriptPath(linuxScriptPath)
        self.scriptPath = normalizedScriptPath ?? Self.defaultScriptPath
        self.macOSScriptPath = normalizedMacOSScriptPath ?? Self.defaultMacOSScriptPath
        self.linuxScriptPath = normalizedLinuxScriptPath ?? Self.defaultLinuxScriptPath
        self.isExplicitlyConfigured = isExplicitlyConfigured
        self.isValid = normalizedScriptPath != nil
            && normalizedMacOSScriptPath != nil
            && normalizedLinuxScriptPath != nil
    }

    static func normalizedScriptPath(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.count <= 240,
              !trimmed.hasPrefix("/"),
              !trimmed.contains("\0"),
              trimmed.rangeOfCharacter(from: .newlines) == nil,
              URL(fileURLWithPath: trimmed).pathExtension == "sh"
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
        return components.joined(separator: "/")
    }
}

struct WorkspaceProjectConfiguration: Equatable {
    static let defaultLocalActionDirectories = LocalEnvironmentActionLoader.defaultDirectories
    static let defaultMaxLocalActions = LocalEnvironmentActionLoader.maxActions
    static let maxConfiguredLocalActionDirectories = 8
    static let maxLocalActionsLimit = 64
    static let defaultBeforeAgentRunHookDirectories = ProjectRunHookLoader.defaultBeforeAgentRunDirectories
    static let defaultAfterAgentRunHookDirectories = ProjectRunHookLoader.defaultAfterAgentRunDirectories
    static let maxConfiguredHookDirectories = 8
    static let maxRunHooksLimit = 32

    var localActionDirectories: [String]
    var maxLocalActions: Int
    var beforeAgentRunHookDirectories: [String]
    var afterAgentRunHookDirectories: [String]
    var maxRunHooks: Int
    var worktreeSetup: WorktreeSetupConfiguration
    var localEnvironments: [WorktreeLocalEnvironment]
    var defaultLocalEnvironmentID: String?

    init(
        localActionDirectories: [String] = defaultLocalActionDirectories,
        maxLocalActions: Int = defaultMaxLocalActions,
        beforeAgentRunHookDirectories: [String] = defaultBeforeAgentRunHookDirectories,
        afterAgentRunHookDirectories: [String] = defaultAfterAgentRunHookDirectories,
        maxRunHooks: Int = ProjectRunHookLoader.maxHooks,
        worktreeSetup: WorktreeSetupConfiguration = WorktreeSetupConfiguration(),
        localEnvironments: [WorktreeLocalEnvironment] = [],
        defaultLocalEnvironmentID: String? = nil
    ) {
        self.localActionDirectories = Self.normalizedDirectories(localActionDirectories)
        self.maxLocalActions = Self.normalizedMaxLocalActions(maxLocalActions)
        self.beforeAgentRunHookDirectories = Self.normalizedHookDirectories(
            beforeAgentRunHookDirectories,
            defaults: Self.defaultBeforeAgentRunHookDirectories
        )
        self.afterAgentRunHookDirectories = Self.normalizedHookDirectories(
            afterAgentRunHookDirectories,
            defaults: Self.defaultAfterAgentRunHookDirectories
        )
        self.maxRunHooks = Self.normalizedMaxRunHooks(maxRunHooks)
        self.worktreeSetup = worktreeSetup
        self.localEnvironments = Array(localEnvironments.prefix(WorktreeLocalEnvironment.maxCount))

        let normalizedDefaultID = defaultLocalEnvironmentID.flatMap(WorktreeLocalEnvironment.normalizedID)
        if let normalizedDefaultID,
           self.localEnvironments.contains(where: { $0.id == normalizedDefaultID }) {
            self.defaultLocalEnvironmentID = normalizedDefaultID
        } else {
            self.defaultLocalEnvironmentID = nil
        }
    }

    init(
        additionalLocalActionDirectories: [String],
        maxLocalActions: Int?,
        additionalBeforeAgentRunHookDirectories: [String] = [],
        additionalAfterAgentRunHookDirectories: [String] = [],
        maxRunHooks: Int? = nil,
        worktreeSetup: WorktreeSetupConfiguration = WorktreeSetupConfiguration(),
        localEnvironments: [WorktreeLocalEnvironment] = [],
        defaultLocalEnvironmentID: String? = nil
    ) {
        self.init(
            localActionDirectories: Self.defaultLocalActionDirectories + additionalLocalActionDirectories,
            maxLocalActions: maxLocalActions ?? Self.defaultMaxLocalActions,
            beforeAgentRunHookDirectories: Self.defaultBeforeAgentRunHookDirectories
                + additionalBeforeAgentRunHookDirectories,
            afterAgentRunHookDirectories: Self.defaultAfterAgentRunHookDirectories
                + additionalAfterAgentRunHookDirectories,
            maxRunHooks: maxRunHooks ?? ProjectRunHookLoader.maxHooks,
            worktreeSetup: worktreeSetup,
            localEnvironments: localEnvironments,
            defaultLocalEnvironmentID: defaultLocalEnvironmentID
        )
    }

    private static func normalizedMaxLocalActions(_ value: Int) -> Int {
        guard (1...maxLocalActionsLimit).contains(value) else {
            return defaultMaxLocalActions
        }
        return value
    }

    private static func normalizedMaxRunHooks(_ value: Int) -> Int {
        guard (1...maxRunHooksLimit).contains(value) else {
            return ProjectRunHookLoader.maxHooks
        }
        return value
    }

    private static func normalizedDirectories(_ directories: [String]) -> [String] {
        normalizedDirectories(
            directories,
            maximumCount: maxConfiguredLocalActionDirectories,
            fallback: defaultLocalActionDirectories
        )
    }

    private static func normalizedHookDirectories(_ directories: [String], defaults: [String]) -> [String] {
        normalizedDirectories(
            directories,
            maximumCount: maxConfiguredHookDirectories,
            fallback: defaults
        )
    }

    private static func normalizedDirectories(
        _ directories: [String],
        maximumCount: Int,
        fallback: [String]
    ) -> [String] {
        var seen = Set<String>()
        let normalized = directories.compactMap { directory -> String? in
            guard seen.count < maximumCount,
                  let value = normalizedDirectory(directory),
                  seen.insert(value).inserted
            else {
                return nil
            }
            return value
        }
        return normalized.isEmpty ? fallback : normalized
    }

    private static func normalizedDirectory(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.count <= 200,
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
        return components.joined(separator: "/")
    }
}
