import QuillCodeCore

struct WorkspaceToolEventRecorder {
    static func events(call: ToolCall, result: ToolResult) -> [ThreadEvent] {
        let transcriptCall = call.redactedForTranscript()
        let callJSON = (try? JSONHelpers.encodePretty(transcriptCall)) ?? transcriptCall.argumentsJSON
        let resultJSON = (try? JSONHelpers.encodePretty(result)) ?? "{}"
        let completionKind: ThreadEventKind = result.ok ? .toolCompleted : .toolFailed
        let completionLabel = result.ok ? "completed" : "failed"

        return [
            ThreadEvent(
                kind: .toolQueued,
                summary: "\(call.name) queued",
                payloadJSON: callJSON
            ),
            ThreadEvent(
                kind: .toolRunning,
                summary: "\(call.name) running"
            ),
            ThreadEvent(
                kind: completionKind,
                summary: "\(call.name) \(completionLabel)",
                payloadJSON: resultJSON
            )
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
