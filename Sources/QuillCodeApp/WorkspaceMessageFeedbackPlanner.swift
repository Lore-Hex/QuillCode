import Foundation
import QuillCodeCore

enum WorkspaceMessageFeedbackPlanner {
    static func event(messageID: UUID, value: MessageFeedbackValue) throws -> ThreadEvent {
        ThreadEvent(
            kind: .messageFeedback,
            summary: summary(for: value),
            payloadJSON: try JSONHelpers.encodePretty(MessageFeedback(
                messageID: messageID,
                value: value
            ))
        )
    }

    static func summary(for value: MessageFeedbackValue) -> String {
        switch value {
        case .helpful:
            return "Marked assistant response helpful"
        case .notHelpful:
            return "Marked assistant response not helpful"
        }
    }
}
