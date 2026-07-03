import Foundation
import QuillCodeCore

public struct MessageSurface: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var role: ChatRole
    public var text: String
    public var accessibilityLabel: String
    public var feedback: MessageFeedbackValue?
    public var revert: MessageRevertSurface?

    public init(
        message: ChatMessage,
        feedback: MessageFeedbackValue? = nil,
        revert: MessageRevertSurface? = nil
    ) {
        self.id = message.id
        self.role = message.role
        self.text = message.content
        self.accessibilityLabel = "\(message.role.rawValue): \(message.content)"
        self.feedback = feedback
        self.revert = revert
    }
}

public struct MessageRevertSurface: Codable, Sendable, Hashable {
    public var turnMessageID: UUID
    public var hasNonApplyPatchEdits: Bool

    public init(turnMessageID: UUID, hasNonApplyPatchEdits: Bool) {
        self.turnMessageID = turnMessageID
        self.hasNonApplyPatchEdits = hasNonApplyPatchEdits
    }
}

public enum TurnRevertCopy {
    public static let buttonTitle = "Revert this turn's edits"

    public static func scope(hasNonApplyPatchEdits: Bool) -> String {
        var text = [
            "Reverses the file edits this turn applied, including files it created.",
            "It does not undo your own earlier edits, shell commands the turn ran, or git commits."
        ].joined(separator: " ")
        if hasNonApplyPatchEdits {
            text += " This turn also changed files outside apply_patch, which can't be reverted automatically."
        }
        return text
    }
}
