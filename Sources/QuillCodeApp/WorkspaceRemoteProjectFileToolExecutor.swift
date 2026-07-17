import Foundation
import QuillCodeAgent
import QuillCodeCore
import QuillCodeTools

enum WorkspaceRemoteProjectFileToolExecutor {
    static func plan(
        _ call: ToolCall,
        context: WorkspaceRemoteProjectToolExecutionContext
    ) throws -> WorkspaceRemoteProjectCommandPlan {
        let args = try ToolArguments(call.argumentsJSON)
        let relativePath = try remoteFilePath(for: call, arguments: args)
        let command = try remoteCommand(for: call, path: relativePath, arguments: args)
        let connection = context.connection
        if call.name == ToolDefinition.fileList.name {
            let includeHidden = args.bool("includeHidden") ?? false
            let maxEntries = args.int("maxEntries")
            return WorkspaceRemoteProjectCommandPlan(
                command: command,
                connection: connection
            ) { result in
                remoteFileListResult(
                    result,
                    connection: connection,
                    path: relativePath,
                    includeHidden: includeHidden,
                    maxEntries: maxEntries
                )
            }
        }
        return WorkspaceRemoteProjectCommandPlan(
            command: command,
            connection: connection
        ) { result in
            remoteFileResult(result, connection: connection, path: relativePath)
        }
    }

    private static func remoteCommand(
        for call: ToolCall,
        path: String,
        arguments: ToolArguments
    ) throws -> String {
        switch call.name {
        case ToolDefinition.fileRead.name:
            return "cat -- \(shellSingleQuoted(path))"
        case ToolDefinition.fileList.name:
            return remoteFileListCommand(
                path: path,
                includeHidden: arguments.bool("includeHidden") ?? false
            )
        case ToolDefinition.fileWrite.name:
            return try remoteFileWriteCommand(path: path, arguments: arguments)
        default:
            throw WorkspaceRemoteProjectFileToolError.unsupportedTool(call.name)
        }
    }

    private static func remoteFileWriteCommand(
        path: String,
        arguments: ToolArguments
    ) throws -> String {
        let content = try arguments.requiredString("content")
        let encoded = Data(content.utf8).base64EncodedString()
        let directory = WorkspaceRemoteProjectPath.directory(for: path)
        return [
            "mkdir -p -- \(shellSingleQuoted(directory))",
            "printf %s \(shellSingleQuoted(encoded)) | base64 --decode > \(shellSingleQuoted(path))",
            "printf 'Wrote %s\\n' \(shellSingleQuoted(path))"
        ].joined(separator: " && ")
    }

    private static func remoteFileResult(
        _ result: ToolResult,
        connection: ProjectConnection,
        path: String
    ) -> ToolResult {
        guard result.ok else { return result }
        var result = result
        result.artifacts = [WorkspaceRemoteProjectPath.artifactPath(connection: connection, relativePath: path)]
        return result
    }

    private static func remoteFilePath(for call: ToolCall, arguments: ToolArguments) throws -> String {
        if call.name == ToolDefinition.fileList.name {
            let path = arguments.string("path")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "."
            guard !path.isEmpty, path != "." else { return "." }
            return try WorkspaceRemoteProjectPath.relativePath(path)
        }
        return try WorkspaceRemoteProjectPath.relativePath(try arguments.requiredString("path"))
    }

    private static func remoteFileListCommand(path: String, includeHidden: Bool) -> String {
        let quotedPath = shellSingleQuoted(path)
        let globSetup = includeHidden
            ? #"set -- "$dir"/* "$dir"/.[!.]* "$dir"/..?*"#
            : #"set -- "$dir"/*"#
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
        guard result.ok else { return result }

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
        guard lhsRank == rhsRank else { return lhsRank < rhsRank }
        let nameOrder = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
        guard nameOrder == .orderedSame else { return nameOrder == .orderedAscending }
        return lhs.name < rhs.name
    }

    private static func remoteFileListKindRank(_ kind: String) -> Int {
        switch kind {
        case "directory": 0
        case "file": 1
        case "symlink": 2
        case "other": 3
        default: 4
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
        guard let data = try? encoder.encode(output) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    private static func shellSingleQuoted(_ value: String) -> String {
        WorkspaceTerminalSessionAdapter.shellSingleQuoted(value)
    }
}

private enum WorkspaceRemoteProjectFileToolError: Error, CustomStringConvertible {
    case unsupportedTool(String)

    var description: String {
        switch self {
        case let .unsupportedTool(name):
            "Tool is not available for SSH Remote projects: \(name)"
        }
    }
}
