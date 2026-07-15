import Foundation

extension QuillCodeNativeHitTargetAudit {
    public static var requiredCommandIDs: [String] {
        [
            "add-project",
            "new-chat",
            "search",
            "toggle-extensions",
            "toggle-automations",
            "toggle-terminal",
            "toggle-browser",
            "toggle-memories",
            "toggle-activity",
            "command-palette",
            "keyboard-shortcuts",
            "settings"
        ]
    }

    public static var requiredSurfaceFamilies: [QuillCodeInteractionSurfaceFamily] {
        QuillCodeInteractionSurfaceFamily.allCases
    }

    public static var requiredFocusTargets: [QuillCodeNativeFocusTarget] {
        QuillCodeNativeFocusTarget.allCases
    }

    public static var requiredSurfacePolicies: [QuillCodeNativeSurfaceTargetPolicy] {
        [
            policy(
                .designSystem,
                kinds: QuillCodeNativeHitTargetKind.allCases,
                actions: QuillCodeNativeHitTargetAction.allCases
            ),
            policy(.workspaceChrome, kinds: [.fullRow], actions: [.press]),
            policy(.sidebar, kinds: [.fullRow], actions: [.press], allowedKinds: [.fullRow, .icon]),
            policy(.sidebarThreadList, kinds: [.fullRow, .icon], actions: [.press]),
            policy(.topBar, kinds: [.icon, .fullRow], actions: [.press]),
            policy(
                .composer,
                kinds: [.textEntry, .icon, .capsule],
                actions: [.textInput, .press],
                focusTargets: [.composerMessage]
            ),
            policy(
                .transcript,
                kinds: [.icon, .link],
                actions: [.press, .link],
                allowedKinds: [.icon, .link, .capsule]
            ),
            policy(.toolCard, kinds: [.fullRow, .textButton], actions: [.press]),
            policy(.contextBanner, kinds: [.textButton], actions: [.press]),
            policy(
                .commandPalette,
                kinds: [.textEntry, .fullRow],
                actions: [.textInput, .press],
                focusTargets: [.commandPaletteSearch]
            ),
            policy(
                .search,
                kinds: [.textEntry, .fullRow],
                actions: [.textInput, .press],
                focusTargets: [.searchChats, .shortcutsSearch]
            ),
            policy(
                .settings,
                kinds: [.textEntry, .formAction],
                actions: [.textInput, .press],
                focusTargets: [.settingsTrustedRouterBaseURL]
            ),
            policy(
                .modelPicker,
                kinds: [.textEntry, .fullRow, .icon],
                actions: [.textInput, .press],
                focusTargets: [.modelPickerSearch]
            ),
            policy(
                .review,
                kinds: [.textEntry, .segmentedControl, .fullRow, .formAction],
                actions: [.textInput, .press],
                focusTargets: [.reviewBody, .reviewThreadReply]
            ),
            policy(
                .secondaryPane,
                kinds: [.capsule],
                actions: [.press],
                allowedKinds: [.capsule, .icon]
            ),
            policy(
                .terminal,
                kinds: [.textEntry, .textButton],
                actions: [.textInput, .press],
                focusTargets: [.terminalCommand]
            ),
            policy(
                .browser,
                kinds: [.textEntry, .textButton, .icon],
                actions: [.textInput, .press],
                focusTargets: [.browserAddress, .browserComment]
            ),
            policy(
                .extensions,
                kinds: [.formAction, .capsule],
                actions: [.press],
                allowedKinds: [.formAction, .capsule, .icon]
            ),
            policy(.memories, kinds: [.formAction, .icon], actions: [.press]),
            policy(
                .automations,
                kinds: [.formAction],
                actions: [.press],
                allowedKinds: [.formAction, .icon]
            ),
            policy(.menuBar, kinds: [.fullRow], actions: [.press])
        ]
    }

    static func policy(
        _ family: QuillCodeInteractionSurfaceFamily,
        kinds: [QuillCodeNativeHitTargetKind],
        actions: [QuillCodeNativeHitTargetAction] = [],
        focusTargets: [QuillCodeNativeFocusTarget] = [],
        allowedKinds: [QuillCodeNativeHitTargetKind]? = nil,
        allowedActions: [QuillCodeNativeHitTargetAction]? = nil,
        allowedFocusTargets: [QuillCodeNativeFocusTarget]? = nil
    ) -> QuillCodeNativeSurfaceTargetPolicy {
        QuillCodeNativeSurfaceTargetPolicy(
            family: family,
            requiredKinds: kinds,
            requiredActions: actions,
            requiredFocusTargets: focusTargets,
            allowedKinds: allowedKinds,
            allowedActions: allowedActions,
            allowedFocusTargets: allowedFocusTargets
        )
    }
}
