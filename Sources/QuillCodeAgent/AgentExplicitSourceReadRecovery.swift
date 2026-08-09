import Foundation
import QuillCodeCore

/// A narrow local recovery for explicitly required source reads. It may advance only existing,
/// workspace-relative regular files named on an affirmative read instruction line. Writes,
/// commands, inferred paths, directories, and named deliverables are outside its authority.
enum AgentExplicitSourceReadRecovery {
    static func nextAction(
        userMessage: String,
        workspaceRoot: URL,
        tools: [ToolDefinition],
        successfullyReadPaths: Set<String>
    ) -> AgentAction? {
        guard tools.contains(where: { $0.name == ToolDefinition.fileRead.name }) else { return nil }

        let deliverables = AgentDeliverableGate.requiredDeliverables(in: userMessage)
        let acceptsRequiredInputInventory = hasAffirmativeRequiredSourceInstruction(userMessage)
        for line in userMessage.split(whereSeparator: \Character.isNewline) {
            let text = String(line)
            let lower = text.lowercased()
            let isExplicitToolInstruction = lower.contains("file read tool")
            let isRequiredInputInventory = acceptsRequiredInputInventory
                && lower.contains("required inputs")
            guard (isExplicitToolInstruction || isRequiredInputInventory),
                  !isNegatedReadInstruction(lower)
            else { continue }

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

    private static func hasAffirmativeRequiredSourceInstruction(_ message: String) -> Bool {
        let lower = message.lowercased()
        return [
            "read every applicable source",
            "read all applicable sources",
            "read every required input",
            "read each required input",
            "read all required inputs",
        ].contains(where: lower.contains)
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
