import Foundation
import QuillCodeCore
import QuillCodeTools

/// Redirects two model-only shell mistakes after source work has already begun: executing a
/// workspace source file as a command, and invoking a bare data label that is not executable.
/// The runner applies this only after a completed tool step, so an explicit one-shot command from
/// the user still reaches the shell and reports its real result.
enum AgentInvalidShellProposalPreflight {
    struct Correction: Equatable {
        var summary: String
        var prompt: String
    }

    static func correction(for call: ToolCall, workspaceRoot: URL) -> Correction? {
        guard call.name == ToolDefinition.shellRun.name,
              let arguments = try? ToolArguments(call.argumentsJSON),
              let rawCommand = arguments.string("cmd")?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawCommand.isEmpty
        else { return nil }

        let command = removingMatchingQuotes(from: rawCommand)
        if isIncompleteInlineInterpreterCommand(command) {
            return Correction(
                summary: "Self-healing: rejected an incomplete inline interpreter command.",
                prompt: """
                The proposed `\(command)` shell call has `-c` but no complete program to execute. \
                Issue one complete validator command with correctly balanced quoting, or use the \
                file tools directly. Do not retry an empty or unterminated `-c` command.
                """
            )
        }
        if let path = nonExecutableSourcePath(command, workspaceRoot: workspaceRoot) {
            return Correction(
                summary: "Self-healing: redirected a workspace source path away from the shell.",
                prompt: """
                ./\(path) is a source file, not a shell command. Use host.file.read if it has not \
                already been inspected; otherwise continue directly to the requested deliverable \
                using the source content already returned. Do not execute the source path.
                """
            )
        }

        guard isBareCommandName(command), !isExecutableCommand(command) else { return nil }
        return Correction(
            summary: "Self-healing: redirected an unavailable bare shell command.",
            prompt: """
            `\(command)` is not an available shell command. It appears to be a source field, event, \
            or data label from the material already inspected. Continue the requested analysis and \
            write the deliverable; do not invoke that label as a command.
            """
        )
    }

    private static func nonExecutableSourcePath(_ command: String, workspaceRoot: URL) -> String? {
        guard !command.isEmpty,
              !command.hasPrefix("/"),
              !command.hasPrefix("~"),
              !containsShellSyntax(command)
        else { return nil }

        let normalized = AgentArtifactVerificationGate.normalizedPath(command)
        let root = workspaceRoot.standardizedFileURL
        let candidate = root.appendingPathComponent(normalized).standardizedFileURL
        guard candidate.path.hasPrefix(root.path + "/"),
              Self.sourceExtensions.contains(candidate.pathExtension.lowercased())
        else { return nil }

        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory),
              !isDirectory.boolValue,
              !FileManager.default.isExecutableFile(atPath: candidate.path)
        else { return nil }
        return normalized
    }

    private static func isBareCommandName(_ command: String) -> Bool {
        command.range(of: #"^[A-Za-z_][A-Za-z0-9_.-]*$"#, options: .regularExpression) != nil
    }

    private static func isIncompleteInlineInterpreterCommand(_ command: String) -> Bool {
        command.range(
            of: #"^(?:[^\s]+/)?(?:python(?:[0-9]+(?:\.[0-9]+)*)?|node|ruby|perl)\s+-c\s*['\"]?$"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }

    private static func isExecutableCommand(_ command: String) -> Bool {
        if shellBuiltins.contains(command) { return true }
        let path = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        return path.split(separator: ":").contains { directory in
            FileManager.default.isExecutableFile(
                atPath: URL(fileURLWithPath: String(directory), isDirectory: true)
                    .appendingPathComponent(command).path
            )
        }
    }

    private static func removingMatchingQuotes(from command: String) -> String {
        guard command.count >= 2,
              let first = command.first,
              let last = command.last,
              (first == "'" || first == "\"") && first == last
        else { return command }
        return String(command.dropFirst().dropLast())
    }

    private static func containsShellSyntax(_ command: String) -> Bool {
        command.rangeOfCharacter(from: CharacterSet(charactersIn: ";&|<>`$\n\r")) != nil
    }

    private static let sourceExtensions: Set<String> = [
        "csv", "html", "json", "md", "markdown", "txt", "tsv", "yaml", "yml",
    ]

    private static let shellBuiltins: Set<String> = [
        ":", "break", "cd", "command", "continue", "echo", "eval", "exec", "exit", "export",
        "false", "printf", "pwd", "read", "readonly", "return", "set", "shift", "test", "times",
        "trap", "true", "type", "ulimit", "umask", "unset", "wait",
    ]
}
