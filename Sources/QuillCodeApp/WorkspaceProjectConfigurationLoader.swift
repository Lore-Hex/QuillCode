import Foundation

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
        var defaultLocalEnvironmentID: String?
        var localEnvironmentOrder: [String] = []
        var localEnvironmentDrafts: [String: WorktreeLocalEnvironmentDraft] = [:]

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

            if let environmentID = localEnvironmentID(from: section) {
                if localEnvironmentDrafts[environmentID] == nil,
                   localEnvironmentOrder.count < WorktreeLocalEnvironment.maxCount {
                    localEnvironmentOrder.append(environmentID)
                    localEnvironmentDrafts[environmentID] = WorktreeLocalEnvironmentDraft()
                }
                localEnvironmentDrafts[environmentID]?.apply(
                    key: assignment.key,
                    value: assignment.value,
                    parseString: parseString
                )
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
            case ("worktree_setup", "default_environment"):
                defaultLocalEnvironmentID = parseString(assignment.value)
            default:
                continue
            }
        }

        let localEnvironments = localEnvironmentOrder.compactMap { environmentID in
            localEnvironmentDrafts[environmentID]?.configuration(id: environmentID)
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
            ),
            localEnvironments: localEnvironments,
            defaultLocalEnvironmentID: defaultLocalEnvironmentID
        )
    }

    private static func localEnvironmentID(from section: String?) -> String? {
        let prefix = "local_environments."
        guard let section, section.hasPrefix(prefix) else { return nil }
        return WorktreeLocalEnvironment.normalizedID(String(section.dropFirst(prefix.count)))
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

private struct WorktreeLocalEnvironmentDraft {
    var title: String?
    var description: String?
    var scriptPath: String?
    var macOSScriptPath: String?
    var linuxScriptPath: String?

    mutating func apply(
        key: String,
        value: String,
        parseString: (String) -> String?
    ) {
        switch key {
        case "title":
            title = parseString(value)
        case "description":
            description = parseString(value)
        case "script":
            scriptPath = parseString(value) ?? ""
        case "macos":
            macOSScriptPath = parseString(value) ?? ""
        case "linux":
            linuxScriptPath = parseString(value) ?? ""
        default:
            break
        }
    }

    func configuration(id: String) -> WorktreeLocalEnvironment? {
        WorktreeLocalEnvironment(
            id: id,
            title: title,
            description: description,
            scriptPath: scriptPath,
            macOSScriptPath: macOSScriptPath,
            linuxScriptPath: linuxScriptPath
        )
    }
}
