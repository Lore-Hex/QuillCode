import Foundation
import QuillCodeCore

public struct MessageSurface: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var role: ChatRole
    public var text: String
    public var attachments: [ImageAttachmentSurface]
    public var accessibilityLabel: String
    /// Present on the user message that began a turn whose `apply_patch` edits can be
    /// reverted, so the UI can offer a "Revert this turn's edits" affordance there.
    public var revert: MessageRevertSurface?

    public init(
        message: ChatMessage,
        revert: MessageRevertSurface? = nil
    ) {
        self.id = message.id
        self.role = message.role
        self.text = message.content
        self.attachments = message.attachments.map(ImageAttachmentSurface.init)
        let imageSummary = attachments.isEmpty ? "" : " \(attachments.count) attached image(s)."
        self.accessibilityLabel = "\(message.role.rawValue): \(message.content)\(imageSummary)"
        self.revert = revert
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case role
        case text
        case attachments
        case accessibilityLabel
        case revert
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.role = try container.decode(ChatRole.self, forKey: .role)
        self.text = try container.decode(String.self, forKey: .text)
        self.attachments = try container.decodeIfPresent(
            [ImageAttachmentSurface].self,
            forKey: .attachments
        ) ?? []
        self.accessibilityLabel = try container.decode(String.self, forKey: .accessibilityLabel)
        self.revert = try container.decodeIfPresent(MessageRevertSurface.self, forKey: .revert)
    }
}

/// The revert affordance for a turn: which turn to revert, and whether the turn also made
/// edits outside `apply_patch` (so the UI can disclose what the revert cannot undo).
public struct MessageRevertSurface: Codable, Sendable, Hashable {
    public var turnMessageID: UUID
    public var hasNonApplyPatchEdits: Bool

    public init(turnMessageID: UUID, hasNonApplyPatchEdits: Bool) {
        self.turnMessageID = turnMessageID
        self.hasNonApplyPatchEdits = hasNonApplyPatchEdits
    }
}

/// The single source of truth for the revert affordance's user-facing copy, so the native,
/// HTML, and harness surfaces make byte-identical, truthful claims about what a reverse-patch
/// revert does and does NOT undo.
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
