import Foundation
import QuillCodeCore
import QuillCodeTools

/// Rejects one predictable no-op before it becomes a failed UI tool card: models often try to list
/// `outputs/` before their first write even though the file writer creates parent directories.
enum AgentMissingDirectoryListPreflight {
    static func missingPath(in call: ToolCall, workspaceRoot: URL) -> String? {
        guard call.name == ToolDefinition.fileList.name,
              let arguments = try? ToolArguments(call.argumentsJSON),
              let rawPath = arguments.string("path")?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawPath.isEmpty,
              rawPath != "."
        else { return nil }

        let normalized = AgentArtifactVerificationGate.normalizedPath(rawPath)
        let root = workspaceRoot.standardizedFileURL
        let candidate = root.appendingPathComponent(normalized).standardizedFileURL
        guard candidate.path == root.path || candidate.path.hasPrefix(root.path + "/") else {
            return nil
        }

        var isDirectory = ObjCBool(false)
        guard !FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory) else {
            return nil
        }
        return normalized
    }
}
