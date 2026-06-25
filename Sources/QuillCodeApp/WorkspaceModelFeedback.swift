import Foundation
import QuillCodeCore

@MainActor
extension QuillCodeWorkspaceModel {
    @discardableResult
    public func setMessageFeedback(messageID: UUID, value: MessageFeedbackValue) -> Bool {
        guard selectedThread?.messages.contains(where: { $0.id == messageID && $0.role == .assistant }) == true,
              let event = try? WorkspaceMessageFeedbackPlanner.event(messageID: messageID, value: value)
        else {
            return false
        }
        mutateSelectedThread { thread in
            thread.events.append(event)
        }
        return true
    }
}
