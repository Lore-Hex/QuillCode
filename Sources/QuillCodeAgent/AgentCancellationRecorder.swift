import Foundation
import QuillCodeCore

enum AgentCancellationRecorder {
    static let stoppedSummary = "Stopped by user"
    static let stoppedPayloadJSON = #"{"ok":false,"error":"Stopped by user"}"#

    static func recordCancelledRun(in thread: inout ChatThread) {
        if shouldMarkActiveToolStopped(thread.events.last) {
            thread.events.append(ThreadEvent(
                kind: .toolFailed,
                summary: stoppedSummary,
                payloadJSON: stoppedPayloadJSON
            ))
        }
        if shouldAppendStoppedNotice(thread.events.last) {
            thread.events.append(ThreadEvent(kind: .notice, summary: stoppedSummary))
        }
        thread.updatedAt = Date()
    }

    private static func shouldMarkActiveToolStopped(_ event: ThreadEvent?) -> Bool {
        event?.kind == .toolQueued || event?.kind == .toolRunning || event?.kind == .toolProgress
    }

    private static func shouldAppendStoppedNotice(_ event: ThreadEvent?) -> Bool {
        event?.kind != .notice || event?.summary != stoppedSummary
    }
}
