enum WorkspaceHTMLSecondaryPanePrimitives {
    static func countLabel(_ count: Int, singular: String) -> String {
        if count == 1 { return "1 \(singular)" }
        if singular.hasSuffix("memory") {
            return "\(count) \(singular.dropLast("memory".count))memories"
        }
        return "\(count) \(singular)s"
    }

    static func escape(_ text: String) -> String {
        WorkspaceHTMLPrimitives.escape(text)
    }

    static func commandButton(
        _ label: String,
        testID: String,
        commandID: String,
        hitTargetKind: WorkspaceHTMLHitTargetKind,
        classes: [String] = [],
        disabled: Bool = false
    ) -> String {
        WorkspaceHTMLPrimitives.commandButton(
            label,
            testID: testID,
            commandID: commandID,
            hitTargetKind: hitTargetKind,
            classes: classes,
            disabled: disabled
        )
    }
}
