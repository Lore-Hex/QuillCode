import Foundation
import QuillCodeCore

enum ProjectHookStandardInput {
    static func payload(
        eventName: String,
        thread: ChatThread,
        workspaceRoot: URL
    ) -> [String: Any] {
        let turnID = thread.messages.last(where: { $0.role == .user })?.id ?? thread.id
        return [
            "session_id": stableID(thread.id),
            "transcript_path": NSNull(),
            "cwd": workspaceRoot.standardizedFileURL.resolvingSymlinksInPath().path,
            "hook_event_name": eventName,
            "model": thread.model,
            "turn_id": stableID(turnID),
            "permission_mode": permissionMode(for: thread.mode)
        ]
    }

    static func encoded(_ payload: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self) + "\n"
    }

    private static func permissionMode(for mode: AgentMode) -> String {
        switch mode {
        case .plan: return "plan"
        case .auto: return "dontAsk"
        case .review, .readOnly: return "default"
        }
    }

    private static func stableID(_ id: UUID) -> String {
        id.uuidString.lowercased()
    }
}
