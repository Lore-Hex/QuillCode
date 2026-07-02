import Foundation
import QuillCodeCore
import QuillCodeAgent

enum WorkspaceMemoryRememberToolExecutor {
    static func executionOverride(directory: URL?) -> AgentToolExecutionOverride? {
        guard let directory else { return nil }
        return { call, _ in
            guard call.name == ToolDefinition.memoryRemember.name else { return nil }
            return execute(call, directory: directory)
        }
    }

    static func execute(_ call: ToolCall, directory: URL) -> ToolResult {
        do {
            let args = try ToolArguments(call.argumentsJSON)
            let content = try args.requiredString("content")
            let saved = try saveGlobal(content: content, to: directory)
            return ToolResult(
                ok: true,
                stdout: try JSONHelpers.encodePretty(saved.output),
                artifacts: [saved.note.relativePath]
            )
        } catch {
            return ToolResult(
                ok: false,
                error: WorkspaceMemoryErrorMessageBuilder.userFacingMessage(for: error)
            )
        }
    }

    static func saveGlobal(
        content: String,
        to directory: URL
    ) throws -> (note: MemoryNote, output: MemoryRememberToolOutput) {
        let note = try MemoryNoteLoader.saveGlobal(content: content, to: directory)
        let output = MemoryRememberToolOutput(
            title: note.title,
            relativePath: note.relativePath,
            content: ToolCall.redactedMemoryContentValue
        )
        return (note, output)
    }

    static func didSaveMemory(in thread: ChatThread) -> Bool {
        thread.events.contains { event in
            guard event.kind == .toolCompleted,
                  event.summary == "\(ToolDefinition.memoryRemember.name) completed",
                  let result = decode(ToolResult.self, event.payloadJSON),
                  result.ok
            else {
                return false
            }
            return result.artifacts.contains { $0.hasPrefix("memories/") }
        }
    }

    private static func decode<T: Decodable>(_ type: T.Type, _ payloadJSON: String?) -> T? {
        guard let payloadJSON else { return nil }
        return try? JSONHelpers.decode(type, from: payloadJSON)
    }
}
