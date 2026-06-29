import Foundation
import QuillCodeAgent
import QuillCodeCore
import QuillCodeTools

struct WorkspaceRemoteProjectToolExecutor: Sendable, Hashable {
    static let toolDefinitions: [ToolDefinition] = [
        .shellRun,
        .fileRead,
        .fileList,
        .fileWrite,
        .applyPatch,
        .gitStatus,
        .gitDiff,
        .gitStage,
        .gitRestore,
        .gitStageHunk,
        .gitRestoreHunk,
        .gitCommit,
        .gitPush,
        .gitPullRequestCreate,
        .gitPullRequestView,
        .gitPullRequestChecks,
        .gitPullRequestDiff,
        .gitPullRequestCheckout,
        .gitPullRequestReviewers,
        .gitPullRequestLabels,
        .gitPullRequestComment,
        .gitPullRequestReview,
        .gitPullRequestReviewComment,
        .gitPullRequestReviewReply,
        .gitPullRequestReviewThreads,
        .gitPullRequestReviewThread,
        .gitPullRequestMerge,
        .gitWorktreeList,
        .gitWorktreeCreate,
        .gitWorktreeOpen,
        .gitWorktreeRemove,
        .gitWorktreePrune
    ]

    static let gitToolNames: Set<String> = [
        ToolDefinition.gitStatus.name,
        ToolDefinition.gitDiff.name,
        ToolDefinition.gitStage.name,
        ToolDefinition.gitRestore.name,
        ToolDefinition.gitStageHunk.name,
        ToolDefinition.gitRestoreHunk.name,
        ToolDefinition.gitCommit.name,
        ToolDefinition.gitPush.name,
        ToolDefinition.gitPullRequestCreate.name,
        ToolDefinition.gitPullRequestView.name,
        ToolDefinition.gitPullRequestChecks.name,
        ToolDefinition.gitPullRequestDiff.name,
        ToolDefinition.gitPullRequestCheckout.name,
        ToolDefinition.gitPullRequestReviewers.name,
        ToolDefinition.gitPullRequestLabels.name,
        ToolDefinition.gitPullRequestComment.name,
        ToolDefinition.gitPullRequestReview.name,
        ToolDefinition.gitPullRequestReviewComment.name,
        ToolDefinition.gitPullRequestReviewReply.name,
        ToolDefinition.gitPullRequestReviewThreads.name,
        ToolDefinition.gitPullRequestReviewThread.name,
        ToolDefinition.gitPullRequestMerge.name,
        ToolDefinition.gitWorktreeList.name,
        ToolDefinition.gitWorktreeCreate.name,
        ToolDefinition.gitWorktreeOpen.name,
        ToolDefinition.gitWorktreeRemove.name,
        ToolDefinition.gitWorktreePrune.name
    ]

    static func executionOverride(
        project: ProjectRef?,
        executor: SSHRemoteShellExecutor
    ) -> AgentToolExecutionOverride? {
        guard let project, project.isRemote else { return nil }
        return { call, _ in
            executeIfSupported(
                call,
                connection: project.connection,
                executor: executor
            )
        }
    }

    static func execute(
        _ call: ToolCall,
        project: ProjectRef,
        executor: SSHRemoteShellExecutor
    ) -> ToolResult {
        guard project.isRemote else {
            return unavailableToolResult(call.name)
        }
        return execute(call, connection: project.connection, executor: executor)
    }

    static func execute(
        _ call: ToolCall,
        connection: ProjectConnection,
        executor: SSHRemoteShellExecutor
    ) -> ToolResult {
        executeIfSupported(call, connection: connection, executor: executor)
            ?? unavailableToolResult(call.name)
    }

    static func executeIfSupported(
        _ call: ToolCall,
        connection: ProjectConnection,
        executor: SSHRemoteShellExecutor
    ) -> ToolResult? {
        switch call.name {
        case ToolDefinition.shellRun.name:
            return executeRemoteShellToolCall(
                call,
                connection: connection,
                executor: executor
            )
        case ToolDefinition.fileRead.name, ToolDefinition.fileList.name, ToolDefinition.fileWrite.name:
            return executeRemoteFileToolCall(
                call,
                connection: connection,
                executor: executor
            )
        case ToolDefinition.applyPatch.name:
            return executeRemotePatchToolCall(
                call,
                connection: connection,
                executor: executor
            )
        case let name where Self.gitToolNames.contains(name):
            return executeRemoteGitToolCall(
                call,
                connection: connection,
                executor: executor
            )
        default:
            return nil
        }
    }

    private static func unavailableToolResult(_ toolName: String) -> ToolResult {
        ToolResult(ok: false, error: "Tool is not available for SSH Remote projects: \(toolName)")
    }

    private static func executeRemoteGitToolCall(
        _ call: ToolCall,
        connection: ProjectConnection,
        executor: SSHRemoteShellExecutor
    ) -> ToolResult {
        do {
            let plannedRequest = try WorkspaceRemoteGitToolRequestPlanner.request(
                for: call,
                connection: connection
            )

            guard let request = executor.request(command: plannedRequest.command, connection: connection) else {
                return ToolResult(ok: false, error: "SSH Remote project is missing a usable host.")
            }
            var result = ShellToolExecutor().run(request)
            if plannedRequest.extractsPullRequestURLs, result.ok {
                result.artifacts = GitHubPullRequestOutputParser.extractURLs(from: result.stdout)
            } else if result.ok, !plannedRequest.artifacts.isEmpty {
                result.artifacts = plannedRequest.artifacts
            }
            return result
        } catch {
            return ToolResult(ok: false, error: String(describing: error))
        }
    }

    private static func executeRemoteFileToolCall(
        _ call: ToolCall,
        connection: ProjectConnection,
        executor: SSHRemoteShellExecutor
    ) -> ToolResult {
        do {
            let args = try ToolArguments(call.argumentsJSON)
            let relativePath = try remoteFilePath(for: call, arguments: args)
            let command: String
            switch call.name {
            case ToolDefinition.fileRead.name:
                command = "cat -- \(shellSingleQuoted(relativePath))"
            case ToolDefinition.fileList.name:
                command = remoteFileListCommand(
                    path: relativePath,
                    includeHidden: args.bool("includeHidden") ?? false
                )
            case ToolDefinition.fileWrite.name:
                let content = try args.requiredString("content")
                let encoded = Data(content.utf8).base64EncodedString()
                let directory = WorkspaceRemoteProjectPath.directory(for: relativePath)
                command = [
                    "mkdir -p -- \(shellSingleQuoted(directory))",
                    "printf %s \(shellSingleQuoted(encoded)) | base64 --decode > \(shellSingleQuoted(relativePath))",
                    "printf 'Wrote %s\\n' \(shellSingleQuoted(relativePath))"
                ].joined(separator: " && ")
            default:
                return ToolResult(ok: false, error: "Tool is not available for SSH Remote projects: \(call.name)")
            }

            guard let request = executor.request(command: command, connection: connection) else {
                return ToolResult(ok: false, error: "SSH Remote project is missing a usable host.")
            }
            var result = ShellToolExecutor().run(request)
            if call.name == ToolDefinition.fileList.name {
                return remoteFileListResult(
                    result,
                    connection: connection,
                    path: relativePath,
                    includeHidden: args.bool("includeHidden") ?? false,
                    maxEntries: args.int("maxEntries")
                )
            }
            if result.ok {
                result.artifacts = [WorkspaceRemoteProjectPath.artifactPath(connection: connection, relativePath: relativePath)]
            }
            return result
        } catch {
            return ToolResult(ok: false, error: String(describing: error))
        }
    }

    private static func remoteFilePath(for call: ToolCall, arguments: ToolArguments) throws -> String {
        if call.name == ToolDefinition.fileList.name {
            let path = arguments.string("path")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "."
            if path.isEmpty || path == "." {
                return "."
            }
            return try WorkspaceRemoteProjectPath.relativePath(path)
        }
        return try WorkspaceRemoteProjectPath.relativePath(try arguments.requiredString("path"))
    }

    private static func remoteFileListCommand(path: String, includeHidden: Bool) -> String {
        let quotedPath = shellSingleQuoted(path)
        let globSetup: String
        if includeHidden {
            globSetup = "set -- \"$dir\"/* \"$dir\"/.[!.]* \"$dir\"/..?*"
        } else {
            globSetup = "set -- \"$dir\"/*"
        }
        return [
            "dir=\(quotedPath)",
            "if [ ! -e \"$dir\" ]; then printf '__quillcode_file_list_error__\\tpath_not_found\\n'; exit 64; fi",
            "if [ ! -d \"$dir\" ]; then printf '__quillcode_file_list_error__\\tnot_directory\\n'; exit 65; fi",
            globSetup,
            """
            for p in "$@"; do
              [ -e "$p" ] || [ -L "$p" ] || continue
              name=${p##*/}
              case "$name" in .|..) continue ;; esac
              if [ -d "$p" ]; then kind=directory; size=''; elif [ -L "$p" ]; then kind=symlink; size=''; elif [ -f "$p" ]; then kind=file; size=$(wc -c < "$p" | tr -d '[:space:]'); else kind=other; size=''; fi
              encoded_name=$(printf '%s' "$name" | base64 | tr -d '\\n')
              printf '%s\\t%s\\t%s\\0' "$kind" "$size" "$encoded_name"
            done
            """
        ].joined(separator: "\n")
    }

    private static func remoteFileListResult(
        _ result: ToolResult,
        connection: ProjectConnection,
        path: String,
        includeHidden: Bool,
        maxEntries: Int?
    ) -> ToolResult {
        if let error = remoteFileListError(from: result.stdout, path: path) {
            return ToolResult(ok: false, error: error)
        }
        guard result.ok else {
            return result
        }

        let entries = parseRemoteFileList(stdout: result.stdout, path: path)
            .sorted(by: remoteFileListEntrySort)
        let limit = boundedRemoteListEntryLimit(maxEntries)
        let returnedEntries = Array(entries.prefix(limit))
        let output = FileListToolOutput(
            path: path,
            entries: returnedEntries,
            totalEntries: entries.count,
            includedHidden: includeHidden,
            truncated: entries.count > returnedEntries.count
        )
        return ToolResult(
            ok: true,
            stdout: encode(output),
            artifacts: returnedEntries.map {
                WorkspaceRemoteProjectPath.artifactPath(connection: connection, relativePath: $0.path)
            }
        )
    }

    private static func remoteFileListError(from stdout: String, path: String) -> String? {
        guard stdout.hasPrefix("__quillcode_file_list_error__\t") else { return nil }
        if stdout.contains("\tpath_not_found") {
            return String(describing: FileToolError.pathNotFound(path))
        }
        if stdout.contains("\tnot_directory") {
            return String(describing: FileToolError.notDirectory(path))
        }
        return "Remote file listing failed."
    }

    private static func parseRemoteFileList(stdout: String, path: String) -> [FileListEntry] {
        stdout.split(separator: "\0", omittingEmptySubsequences: true).compactMap { record in
            let fields = record.split(separator: "\t", omittingEmptySubsequences: false)
            guard fields.count == 3,
                  let nameData = Data(base64Encoded: String(fields[2])),
                  let name = String(data: nameData, encoding: .utf8),
                  !name.isEmpty
            else {
                return nil
            }
            let kind = String(fields[0])
            let bytes = Int(String(fields[1]))
            return FileListEntry(
                name: name,
                path: path == "." ? name : "\(path)/\(name)",
                kind: kind,
                bytes: kind == "file" ? bytes : nil,
                isHidden: name.hasPrefix(".")
            )
        }
    }

    private static func remoteFileListEntrySort(_ lhs: FileListEntry, _ rhs: FileListEntry) -> Bool {
        let lhsRank = remoteFileListKindRank(lhs.kind)
        let rhsRank = remoteFileListKindRank(rhs.kind)
        if lhsRank != rhsRank {
            return lhsRank < rhsRank
        }
        let nameOrder = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
        if nameOrder != .orderedSame {
            return nameOrder == .orderedAscending
        }
        return lhs.name < rhs.name
    }

    private static func remoteFileListKindRank(_ kind: String) -> Int {
        switch kind {
        case "directory":
            return 0
        case "file":
            return 1
        case "symlink":
            return 2
        case "other":
            return 3
        default:
            return 4
        }
    }

    private static func boundedRemoteListEntryLimit(_ requested: Int?) -> Int {
        let defaultLimit = 200
        let absoluteLimit = 500
        guard let requested else { return defaultLimit }
        return min(max(1, requested), absoluteLimit)
    }

    private static func encode<T: Encodable>(_ output: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(output) else {
            return "{}"
        }
        return String(decoding: data, as: UTF8.self)
    }

    private static func executeRemotePatchToolCall(
        _ call: ToolCall,
        connection: ProjectConnection,
        executor: SSHRemoteShellExecutor
    ) -> ToolResult {
        do {
            let args = try ToolArguments(call.argumentsJSON)
            var patch = try args.requiredString("patch")
            let trimmedPatch = patch.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedPatch.isEmpty else {
                return ToolResult(ok: false, error: String(describing: PatchToolError.emptyPatch))
            }
            if let unsafePath = PatchToolExecutor.unsafePath(in: patch) {
                return ToolResult(
                    ok: false,
                    error: String(describing: PatchToolError.unsafePath(unsafePath))
                )
            }
            if !patch.hasSuffix("\n") {
                patch.append("\n")
            }

            let encoded = Data(patch.utf8).base64EncodedString()
            let command = [
                "patch_file=\"${TMPDIR:-/tmp}/quillcode.$$.patch\"",
                "trap 'rm -f \"$patch_file\"' EXIT",
                "printf %s \(shellSingleQuoted(encoded)) | base64 --decode > \"$patch_file\"",
                "git apply --check \"$patch_file\"",
                "git apply \"$patch_file\"",
                "printf 'Patch applied.\\n'"
            ].joined(separator: " && ")

            guard let request = executor.request(command: command, connection: connection) else {
                return ToolResult(ok: false, error: "SSH Remote project is missing a usable host.")
            }
            return ShellToolExecutor().run(request)
        } catch {
            return ToolResult(ok: false, error: String(describing: error))
        }
    }

    private static func executeRemoteShellToolCall(
        _ call: ToolCall,
        connection: ProjectConnection,
        executor: SSHRemoteShellExecutor
    ) -> ToolResult {
        do {
            let args = try ToolArguments(call.argumentsJSON)
            let command = try args.requiredString("cmd")
            let requestConnection = WorkspaceRemoteProjectPath.shellConnection(
                connection,
                cwd: args.string("cwd")
            )
            guard let request = executor.request(command: command, connection: requestConnection) else {
                return ToolResult(ok: false, error: "SSH Remote project is missing a usable host.")
            }
            return ShellToolExecutor().run(request)
        } catch {
            return ToolResult(ok: false, error: String(describing: error))
        }
    }

    private static func shellSingleQuoted(_ value: String) -> String {
        WorkspaceTerminalSessionAdapter.shellSingleQuoted(value)
    }
}
