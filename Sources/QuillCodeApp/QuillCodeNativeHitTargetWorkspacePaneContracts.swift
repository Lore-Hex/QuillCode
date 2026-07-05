import Foundation

extension QuillCodeNativeHitTargetAudit {
    static func reviewTransientContracts() -> [QuillCodeNativeHitTargetContract] {
        [
            contract(
                "review.body",
                family: .review,
                surface: "Review",
                label: "Review body",
                kind: .textEntry,
                minWidth: nil,
                focusTarget: .reviewBody,
                testID: "review-body"
            ),
            contract(
                "review.thread-reply",
                family: .review,
                surface: "Review",
                label: "Review thread reply",
                kind: .textEntry,
                minWidth: nil,
                focusTarget: .reviewThreadReply,
                testID: "pr-review-thread-reply-input"
            ),
            contract(
                "review.mode",
                family: .review,
                surface: "Review",
                label: "Review mode",
                kind: .segmentedControl,
                minWidth: nil,
                testID: "review-mode"
            ),
            contract(
                "review.file-row",
                family: .review,
                surface: "Review",
                label: "Review file",
                kind: .fullRow,
                minWidth: nil,
                testID: "review-file"
            ),
            contract(
                "review.action",
                family: .review,
                surface: "Review",
                label: "Review action",
                kind: .formAction,
                minWidth: 72,
                testID: "review-action"
            )
        ]
    }

    static func secondaryPaneTransientContracts() -> [QuillCodeNativeHitTargetContract] {
        [
            contract(
                "secondary-pane.tab",
                family: .secondaryPane,
                surface: "Secondary pane",
                label: "Pane tab",
                kind: .capsule,
                minWidth: 72,
                testID: "secondary-pane-tab"
            )
        ]
    }

    static func terminalTransientContracts() -> [QuillCodeNativeHitTargetContract] {
        [
            contract(
                "terminal.family-entry",
                family: .terminal,
                surface: "Terminal",
                label: "Terminal command",
                kind: .textEntry,
                minWidth: nil,
                focusTarget: .terminalCommand,
                testID: "terminal-command"
            ),
            contract(
                "terminal.family-action",
                family: .terminal,
                surface: "Terminal",
                label: "Terminal action",
                kind: .textButton,
                minWidth: 64,
                testID: "terminal-action"
            )
        ]
    }

    static func browserTransientContracts() -> [QuillCodeNativeHitTargetContract] {
        [
            contract(
                "browser.family-entry",
                family: .browser,
                surface: "Browser",
                label: "Browser address",
                kind: .textEntry,
                minWidth: nil,
                focusTarget: .browserAddress,
                testID: "browser-address"
            ),
            contract(
                "browser.family-action",
                family: .browser,
                surface: "Browser",
                label: "Browser action",
                kind: .textButton,
                minWidth: 64,
                testID: "browser-action"
            ),
            contract(
                "browser.family-icon",
                family: .browser,
                surface: "Browser",
                label: "Browser icon action",
                kind: .icon,
                minWidth: Double(QuillCodeMetrics.minimumHitTarget),
                testID: "browser-icon-action"
            ),
            contract(
                "browser.comment-entry",
                family: .browser,
                surface: "Browser",
                label: "Browser comment",
                kind: .textEntry,
                minWidth: nil,
                focusTarget: .browserComment,
                testID: "browser-comment-input"
            )
        ]
    }
}
