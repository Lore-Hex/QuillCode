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

    private static func normalizedScriptPath(_ value: String) -> String? {
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

    init(
        localActionDirectories: [String] = defaultLocalActionDirectories,
        maxLocalActions: Int = defaultMaxLocalActions,
        beforeAgentRunHookDirectories: [String] = defaultBeforeAgentRunHookDirectories,
        afterAgentRunHookDirectories: [String] = defaultAfterAgentRunHookDirectories,
        maxRunHooks: Int = ProjectRunHookLoader.maxHooks,
        worktreeSetup: WorktreeSetupConfiguration = WorktreeSetupConfiguration()
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
    }

    init(
        additionalLocalActionDirectories: [String],
        maxLocalActions: Int?,
        additionalBeforeAgentRunHookDirectories: [String] = [],
        additionalAfterAgentRunHookDirectories: [String] = [],
        maxRunHooks: Int? = nil,
        worktreeSetup: WorktreeSetupConfiguration = WorktreeSetupConfiguration()
    ) {
        self.init(
            localActionDirectories: Self.defaultLocalActionDirectories + additionalLocalActionDirectories,
            maxLocalActions: maxLocalActions ?? Self.defaultMaxLocalActions,
            beforeAgentRunHookDirectories: Self.defaultBeforeAgentRunHookDirectories
                + additionalBeforeAgentRunHookDirectories,
            afterAgentRunHookDirectories: Self.defaultAfterAgentRunHookDirectories
                + additionalAfterAgentRunHookDirectories,
            maxRunHooks: maxRunHooks ?? ProjectRunHookLoader.maxHooks,
            worktreeSetup: worktreeSetup
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
        var seen = Set<String>()
        var normalized: [String] = []
        for directory in directories {
            guard normalized.count < maxConfiguredLocalActionDirectories,
                  let value = normalizedDirectory(directory),
                  seen.insert(value).inserted
            else {
                continue
            }
            normalized.append(value)
        }
        return normalized.isEmpty ? defaultLocalActionDirectories : normalized
    }

    private static func normalizedHookDirectories(_ directories: [String], defaults: [String]) -> [String] {
        var seen = Set<String>()
        var normalized: [String] = []
        for directory in directories {
            guard normalized.count < maxConfiguredHookDirectories,
                  let value = normalizedDirectory(directory),
                  seen.insert(value).inserted
            else {
                continue
            }
            normalized.append(value)
        }
        return normalized.isEmpty ? defaults : normalized
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

enum WorkspaceProjectConfigurationLoader {
    static let relativePath = ".quillcode/config.toml"
    private static let maxConfigBytes = 16 * 1024

    static func load(from projectRoot: URL) -> WorkspaceProjectConfiguration {
        let root = projectRoot.standardizedFileURL.resolvingSymlinksInPath()
        let configURL = root
            .appendingPathComponent(relativePath)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        guard configURL.path.hasPrefix(root.path + "/"),
              configURL.pathExtension == "toml",
              let values = try? configURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
              values.isRegularFile == true,
              let fileSize = values.fileSize,
              fileSize <= maxConfigBytes,
              let text = try? String(contentsOf: configURL, encoding: .utf8)
        else {
            return WorkspaceProjectConfiguration()
        }

        return parse(text)
    }

    static func parse(_ text: String) -> WorkspaceProjectConfiguration {
        var section: String?
        var additionalDirectories: [String] = []
        var maxLocalActions: Int?
        var additionalBeforeHookDirectories: [String] = []
        var additionalAfterHookDirectories: [String] = []
        var maxRunHooks: Int?
        var worktreeSetupScript = WorktreeSetupConfiguration.defaultScriptPath
        var worktreeSetupMacOSScript = WorktreeSetupConfiguration.defaultMacOSScriptPath
        var worktreeSetupLinuxScript = WorktreeSetupConfiguration.defaultLinuxScriptPath
        var hasWorktreeSetupConfiguration = false

        for rawLine in text.components(separatedBy: .newlines) {
            let line = stripComment(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            if line.hasPrefix("["), line.hasSuffix("]") {
                section = line.dropFirst().dropLast()
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                continue
            }

            guard let assignment = assignment(from: line) else {
                continue
            }

            switch (section, assignment.key) {
            case (nil, "local_action_directory"), ("local_actions", "directory"):
                if let directory = parseString(assignment.value) {
                    additionalDirectories.append(directory)
                }
            case (nil, "local_action_directories"), ("local_actions", "directories"):
                additionalDirectories.append(contentsOf: parseStringArray(assignment.value))
            case (nil, "max_local_actions"), ("local_actions", "max"):
                maxLocalActions = Int(assignment.value.trimmingCharacters(in: .whitespaces))
            case ("hooks", "before_agent_run_directory"):
                if let directory = parseString(assignment.value) {
                    additionalBeforeHookDirectories.append(directory)
                }
            case ("hooks", "before_agent_run_directories"):
                additionalBeforeHookDirectories.append(contentsOf: parseStringArray(assignment.value))
            case ("hooks", "after_agent_run_directory"):
                if let directory = parseString(assignment.value) {
                    additionalAfterHookDirectories.append(directory)
                }
            case ("hooks", "after_agent_run_directories"):
                additionalAfterHookDirectories.append(contentsOf: parseStringArray(assignment.value))
            case ("hooks", "max"):
                maxRunHooks = Int(assignment.value.trimmingCharacters(in: .whitespaces))
            case ("worktree_setup", "script"):
                hasWorktreeSetupConfiguration = true
                worktreeSetupScript = parseString(assignment.value) ?? ""
            case ("worktree_setup", "macos"):
                hasWorktreeSetupConfiguration = true
                worktreeSetupMacOSScript = parseString(assignment.value) ?? ""
            case ("worktree_setup", "linux"):
                hasWorktreeSetupConfiguration = true
                worktreeSetupLinuxScript = parseString(assignment.value) ?? ""
            default:
                continue
            }
        }

        return WorkspaceProjectConfiguration(
            additionalLocalActionDirectories: additionalDirectories,
            maxLocalActions: maxLocalActions,
            additionalBeforeAgentRunHookDirectories: additionalBeforeHookDirectories,
            additionalAfterAgentRunHookDirectories: additionalAfterHookDirectories,
            maxRunHooks: maxRunHooks,
            worktreeSetup: WorktreeSetupConfiguration(
                scriptPath: worktreeSetupScript,
                macOSScriptPath: worktreeSetupMacOSScript,
                linuxScriptPath: worktreeSetupLinuxScript,
                isExplicitlyConfigured: hasWorktreeSetupConfiguration
            )
        )
    }

    private static func assignment(from line: String) -> (key: String, value: String)? {
        let parts = line.split(separator: "=", maxSplits: 1).map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        guard parts.count == 2, !parts[0].isEmpty else {
            return nil
        }
        return (parts[0], parts[1])
    }

    private static func parseString(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("\""), trimmed.hasSuffix("\""), trimmed.count >= 2 else { return nil }
        return unescapedString(String(trimmed.dropFirst().dropLast()))
    }

    private static func parseStringArray(_ value: String) -> [String] {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("["), trimmed.hasSuffix("]") else {
            return []
        }
        let body = String(trimmed.dropFirst().dropLast())
        var values: [String] = []
        var current = ""
        var isQuoted = false
        var isEscaped = false

        func appendCurrent() {
            guard let value = parseString(current) else { return }
            values.append(value)
            current = ""
        }

        for character in body {
            if isEscaped {
                current.append(character)
                isEscaped = false
                continue
            }
            if character == "\\" {
                current.append(character)
                isEscaped = true
                continue
            }
            if character == "\"" {
                isQuoted.toggle()
                current.append(character)
                continue
            }
            if character == ",", !isQuoted {
                appendCurrent()
                continue
            }
            current.append(character)
        }
        appendCurrent()
        return values
    }

    private static func stripComment(_ line: String) -> String {
        var output = ""
        var isQuoted = false
        var isEscaped = false
        for character in line {
            if isEscaped {
                output.append(character)
                isEscaped = false
                continue
            }
            if character == "\\" {
                output.append(character)
                isEscaped = true
                continue
            }
            if character == "\"" {
                isQuoted.toggle()
                output.append(character)
                continue
            }
            if character == "#", !isQuoted {
                break
            }
            output.append(character)
        }
        return output
    }

    private static func unescapedString(_ value: String) -> String {
        var output = ""
        var isEscaped = false
        for character in value {
            if isEscaped {
                switch character {
                case "n":
                    output.append("\n")
                case "t":
                    output.append("\t")
                case "\"", "\\":
                    output.append(character)
                default:
                    output.append(character)
                }
                isEscaped = false
                continue
            }
            if character == "\\" {
                isEscaped = true
            } else {
                output.append(character)
            }
        }
        if isEscaped {
            output.append("\\")
        }
        return output
    }
}
