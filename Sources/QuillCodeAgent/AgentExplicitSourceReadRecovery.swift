import Foundation
import QuillCodeCore

/// A narrow local recovery for a provider that repeatedly returns an empty action after source
/// work. It may advance only existing, workspace-relative files named on an affirmative
/// "file read tool" instruction line. Writes, commands, inferred paths, and named deliverables are
/// deliberately outside its authority.
enum AgentExplicitSourceReadRecovery {
    static func nextAction(
        userMessage: String,
        workspaceRoot: URL,
        tools: [ToolDefinition],
        successfullyReadPaths: Set<String>
    ) -> AgentAction? {
        guard tools.contains(where: { $0.name == ToolDefinition.fileRead.name }) else { return nil }

        let deliverables = AgentDeliverableGate.requiredDeliverables(in: userMessage)
        for line in userMessage.split(whereSeparator: \Character.isNewline) {
            let text = String(line)
            let lower = text.lowercased()
            guard lower.contains("file read tool"), !isNegatedReadInstruction(lower) else { continue }

            for rawPath in AgentRequestTextScanner.backtickQuotedValues(in: text) {
                let path = AgentArtifactVerificationGate.normalizedPath(rawPath)
                guard AgentRequestPathGuard.isSafeWorkspaceRelativePath(path),
                      !deliverables.contains(where: {
                          AgentArtifactVerificationGate.pathsMatch($0, path)
                      }),
                      !successfullyReadPaths.contains(where: {
                          AgentArtifactVerificationGate.pathsMatch($0, path)
                      }),
                      isExistingRegularWorkspaceFile(path, workspaceRoot: workspaceRoot)
                else { continue }

                return .tool(ToolCall(
                    name: ToolDefinition.fileRead.name,
                    argumentsJSON: ToolArguments.json(["path": path])
                ))
            }
        }
        return nil
    }

    private static func isNegatedReadInstruction(_ lower: String) -> Bool {
        [
            "do not use the file read tool",
            "don't use the file read tool",
            "dont use the file read tool",
            "never use the file read tool",
        ].contains(where: lower.contains)
    }

    private static func isExistingRegularWorkspaceFile(_ path: String, workspaceRoot: URL) -> Bool {
        let root = workspaceRoot.standardizedFileURL
        let candidate = root.appendingPathComponent(path).standardizedFileURL
        guard candidate.path.hasPrefix(root.path + "/") else { return false }

        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory)
            && !isDirectory.boolValue
    }
}
