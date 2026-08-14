import QuillCodeCore

struct WorkspaceToolEventRecorder {
    static func queuedEvent(for call: ToolCall) -> ThreadEvent {
        let transcriptCall = call.redactedForTranscript()
        let callJSON = (try? JSONHelpers.encodePretty(transcriptCall)) ?? transcriptCall.argumentsJSON
        return ThreadEvent(
            kind: .toolQueued,
            summary: "\(call.name) queued",
            payloadJSON: callJSON
        )
    }

    static func runningEvent(for call: ToolCall) -> ThreadEvent {
        ThreadEvent(
            kind: .toolRunning,
            summary: "\(call.name) running"
        )
    }

    static func completionEvent(for call: ToolCall, result: ToolResult) -> ThreadEvent {
        let resultJSON = (try? JSONHelpers.encodePretty(result)) ?? "{}"
        let completionKind: ThreadEventKind = result.ok ? .toolCompleted : .toolFailed
        let completionLabel = result.ok ? "completed" : "failed"
        return ThreadEvent(
            kind: completionKind,
            summary: "\(call.name) \(completionLabel)",
            payloadJSON: resultJSON
        )
    }

    static func events(call: ToolCall, result: ToolResult) -> [ThreadEvent] {
        return [
            queuedEvent(for: call),
            runningEvent(for: call),
            completionEvent(for: call, result: result)
        ]
    }

    static func append(call: ToolCall, result: ToolResult, to thread: inout ChatThread) {
        thread.events.append(contentsOf: events(call: call, result: result))
    }

    static func append(execution: WorkspaceToolCallExecution, to thread: inout ChatThread) {
        append(call: execution.primary.call, result: execution.primary.result, to: &thread)
        for followUp in execution.followUps {
            append(call: followUp.call, result: followUp.result, to: &thread)
        }
    }
}
