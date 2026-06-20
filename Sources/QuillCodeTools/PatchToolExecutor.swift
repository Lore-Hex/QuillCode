import Foundation
import QuillCodeCore

public enum PatchToolError: Error, CustomStringConvertible {
    case unsafePath(String)
    case emptyPatch
    case temporaryFileFailed(String)

    public var description: String {
        switch self {
        case .unsafePath(let path):
            return "Patch touches an unsafe path outside the workspace: \(path)"
        case .emptyPatch:
            return "Patch is empty."
        case .temporaryFileFailed(let message):
            return "Failed to prepare temporary patch file: \(message)"
        }
    }
}

public struct PatchToolExecutor: Sendable {
    public var workspaceRoot: URL
    private let shell: ShellToolExecutor

    public init(workspaceRoot: URL, shell: ShellToolExecutor = ShellToolExecutor()) {
        self.workspaceRoot = workspaceRoot.standardizedFileURL
        self.shell = shell
    }

    public func apply(unifiedDiff patch: String) -> ToolResult {
        let trimmed = patch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ToolResult(ok: false, error: String(describing: PatchToolError.emptyPatch))
        }
        if let unsafe = unsafePath(in: patch) {
            return ToolResult(ok: false, error: String(describing: PatchToolError.unsafePath(unsafe)))
        }

        var normalizedPatch = patch
        if !normalizedPatch.hasSuffix("\n") {
            normalizedPatch.append("\n")
        }

        let patchURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("quillcode-\(UUID().uuidString).patch")
        do {
            try normalizedPatch.write(to: patchURL, atomically: true, encoding: .utf8)
        } catch {
            return ToolResult(ok: false, error: String(describing: PatchToolError.temporaryFileFailed(String(describing: error))))
        }
        defer { try? FileManager.default.removeItem(at: patchURL) }

        let quoted = shellQuote(patchURL.path)
        let check = shell.run(.init(command: "git apply --check \(quoted)", cwd: workspaceRoot, timeoutSeconds: 20))
        guard check.ok else {
            return ToolResult(
                ok: false,
                stdout: check.stdout,
                stderr: check.stderr,
                exitCode: check.exitCode,
                error: check.error ?? "Patch check failed."
            )
        }
        let apply = shell.run(.init(command: "git apply \(quoted)", cwd: workspaceRoot, timeoutSeconds: 20))
        if apply.ok {
            return ToolResult(
                ok: true,
                stdout: "Patch applied.\n",
                stderr: apply.stderr,
                exitCode: apply.exitCode
            )
        }
        return apply
    }

    public func unsafePath(in patch: String) -> String? {
        for line in patch.components(separatedBy: .newlines) {
            guard line.hasPrefix("--- ") || line.hasPrefix("+++ ") || line.hasPrefix("diff --git ") else {
                continue
            }
            let paths = pathsInDiffMetadataLine(line)
            for path in paths where isUnsafeDiffPath(path) {
                return path
            }
        }
        return nil
    }

    private func pathsInDiffMetadataLine(_ line: String) -> [String] {
        if line.hasPrefix("diff --git ") {
            return line
                .dropFirst("diff --git ".count)
                .split(separator: " ")
                .map(String.init)
        }
        return line
            .dropFirst(4)
            .split(separator: "\t")
            .first
            .map { [String($0)] } ?? []
    }

    private func isUnsafeDiffPath(_ rawPath: String) -> Bool {
        if rawPath == "/dev/null" { return false }
        var path = rawPath
        if path.hasPrefix("a/") || path.hasPrefix("b/") {
            path.removeFirst(2)
        }
        return path.hasPrefix("/") || path == ".." || path.hasPrefix("../") || path.contains("/../")
    }

    private func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

public extension ToolDefinition {
    static let applyPatch = ToolDefinition(
        name: "host.apply_patch",
        description: "Apply a unified diff patch inside the project workspace.",
        parametersJSON: #"{"type":"object","properties":{"patch":{"type":"string"}},"required":["patch"]}"#,
        host: .local,
        risk: .append
    )
}
