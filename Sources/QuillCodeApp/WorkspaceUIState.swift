public struct ComposerState: Sendable, Hashable {
    public var draft: String
    public var isSending: Bool
    public var placeholder: String

    public init(
        draft: String = "",
        isSending: Bool = false,
        placeholder: String = "Message QuillCode"
    ) {
        self.draft = draft
        self.isSending = isSending
        self.placeholder = placeholder
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
