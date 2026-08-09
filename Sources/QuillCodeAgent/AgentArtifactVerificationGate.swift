import Foundation
import QuillCodeCore

/// Mechanical enforcement for explicit write-then-read verification requests. Models sometimes
/// read the output path before creating it, or verify an early draft and then overwrite it. The
/// run loop tracks successful writes and reads, while this gate prevents either ordering error
/// from being mistaken for a completed task.
enum AgentArtifactVerificationGate {
    struct PreWriteCorrection: Equatable {
        var path: String
        var prompt: String
    }

    static func requiresReadback(in userMessage: String) -> Bool {
        let patterns = [
            #"(?is)\bafter\s+(?:writing|saving|creating|producing|generating)\b.{0,120}\bread\b.{0,80}\b(?:back|verify|confirm)\b"#,
            #"(?is)\bread\b.{0,80}\b(?:saved|written|created|output|deliverable|artifact|file)\b.{0,40}\b(?:back|verify|confirm)\b"#,
            #"(?is)\bverify\b.{0,80}\b(?:saved|written|created|output|deliverable|artifact|file)\b"#,
        ]
        let range = NSRange(userMessage.startIndex..., in: userMessage)
        return patterns.contains { pattern in
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
            return regex.firstMatch(in: userMessage, range: range) != nil
        }
    }

    static func preWriteCorrection(
        for call: ToolCall,
        userMessage: String,
        workspaceRoot: URL
    ) -> PreWriteCorrection? {
        guard call.name == ToolDefinition.fileRead.name,
              requiresReadback(in: userMessage),
              let path = pathArgument(from: call),
              AgentDeliverableGate.requiredDeliverables(in: userMessage).contains(where: {
                  pathsMatch($0, path)
              }),
              !FileManager.default.fileExists(atPath: workspaceRoot.appendingPathComponent(path).path)
        else { return nil }

        return PreWriteCorrection(
            path: normalizedPath(path),
            prompt: """
            The requested output ./\(normalizedPath(path)) does not exist yet, so it cannot be \
            verified. Create it now with host.file.write using the completed work, then read that \
            same path back only after the write succeeds.
            """
        )
    }

    static func actionByRequiringReadback(
        _ action: AgentAction,
        userMessage: String,
        tools: [ToolDefinition],
        unverifiedPaths: Set<String>
    ) -> AgentAction {
        guard case .say = action,
              requiresReadback(in: userMessage),
              tools.contains(where: { $0.name == ToolDefinition.fileRead.name }),
              let path = unverifiedPaths.sorted().first
        else { return action }
        return .tool(ToolCall(
            name: ToolDefinition.fileRead.name,
            argumentsJSON: ToolArguments.json(["path": path])
        ))
    }

    static func pathArgument(from call: ToolCall) -> String? {
        try? ToolArguments(call.argumentsJSON).requiredString("path")
    }

    static func isExistingWorkspaceFile(_ path: String, workspaceRoot: URL) -> Bool {
        let root = workspaceRoot.standardizedFileURL.resolvingSymlinksInPath()
        let normalized = normalizedPath(path)
        let unresolved = (normalized as NSString).isAbsolutePath
            ? URL(fileURLWithPath: normalized)
            : root.appendingPathComponent(normalized)
        let candidate = unresolved.standardizedFileURL.resolvingSymlinksInPath()
        guard candidate.path.hasPrefix(root.path + "/") else { return false }
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory)
            && !isDirectory.boolValue
    }

    static func pathsMatch(_ lhs: String, _ rhs: String) -> Bool {
        let left = normalizedPath(lhs)
        let right = normalizedPath(rhs)
        if left == right {
            return true
        }
        let leftIsAbsolute = (left as NSString).isAbsolutePath
        let rightIsAbsolute = (right as NSString).isAbsolutePath
        guard leftIsAbsolute != rightIsAbsolute else {
            return false
        }
        let absolute = leftIsAbsolute ? left : right
        let relative = leftIsAbsolute ? right : left
        return absolute.hasSuffix("/" + relative)
    }

    static func normalizedPath(_ path: String) -> String {
        var result = path.replacingOccurrences(of: "\\", with: "/")
        while result.hasPrefix("./") {
            result.removeFirst(2)
        }
        return result
    }
}
