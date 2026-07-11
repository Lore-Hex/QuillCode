import QuillCodeCore

public struct ComposerState: Sendable, Hashable {
    public var draft: String
    public var attachments: [ChatAttachment]
    public var isSending: Bool
    public var placeholder: String
    /// Bumped each time the composer should grab focus (e.g. the `focus-composer` command). The
    /// view observes this on the rendered surface and sets its `FocusState` when it changes —
    /// the bridge from a routed (model) command to view-layer focus.
    public var focusToken: Int

    public init(
        draft: String = "",
        attachments: [ChatAttachment] = [],
        isSending: Bool = false,
        placeholder: String = "Message QuillCode",
        focusToken: Int = 0
    ) {
        self.draft = draft
        self.attachments = Array(attachments.prefix(ChatAttachment.maximumCountPerTurn))
        self.isSending = isSending
        self.placeholder = placeholder
        self.focusToken = focusToken
    }
}

public struct MemoriesState: Sendable, Hashable {
    public var isVisible: Bool

    public init(isVisible: Bool = false) {
        self.isVisible = isVisible
    }
}

public struct ActivityState: Sendable, Hashable {
    public var isVisible: Bool
    public var collapsedSectionIDs: Set<ActivitySectionKind>
    public var dismissedInstructionDiagnosticIDs: Set<String>

    public init(
        isVisible: Bool = false,
        collapsedSectionIDs: Set<ActivitySectionKind> = [],
        dismissedInstructionDiagnosticIDs: Set<String> = []
    ) {
        self.isVisible = isVisible
        self.collapsedSectionIDs = collapsedSectionIDs
        self.dismissedInstructionDiagnosticIDs = dismissedInstructionDiagnosticIDs
    }
}
