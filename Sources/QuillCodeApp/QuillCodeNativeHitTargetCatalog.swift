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
        policy(.designSystem, kinds: QuillCodeNativeHitTargetKind.allCases, actions: QuillCodeNativeHitTargetAction.allCases),
        policy(.workspaceChrome, kinds: [.fullRow], actions: [.press]),
        policy(.sidebar, kinds: [.fullRow], actions: [.press], allowedKinds: [.fullRow, .icon]),
        policy(.sidebarThreadList, kinds: [.fullRow, .icon], actions: [.press]),
        policy(.topBar, kinds: [.icon, .fullRow], actions: [.press]),
        policy(.composer, kinds: [.textEntry, .icon, .capsule], actions: [.textInput, .press], focusTargets: [.composerMessage]),
        policy(.transcript, kinds: [.icon, .link], actions: [.press, .link], allowedKinds: [.icon, .link, .capsule]),
        policy(.toolCard, kinds: [.fullRow, .textButton], actions: [.press]),
        policy(.contextBanner, kinds: [.textButton], actions: [.press]),
        policy(.commandPalette, kinds: [.textEntry, .fullRow], actions: [.textInput, .press], focusTargets: [.commandPaletteSearch]),
        policy(.search, kinds: [.textEntry, .fullRow], actions: [.textInput, .press], focusTargets: [.searchChats]),
        policy(.settings, kinds: [.textEntry, .formAction], actions: [.textInput, .press], focusTargets: [.settingsTrustedRouterBaseURL]),
        policy(.modelPicker, kinds: [.textEntry, .fullRow, .icon], actions: [.textInput, .press], focusTargets: [.modelPickerSearch]),
        policy(.review, kinds: [.textEntry, .segmentedControl, .fullRow, .formAction], actions: [.textInput, .press], focusTargets: [.reviewBody, .reviewThreadReply]),
        policy(.secondaryPane, kinds: [.capsule], actions: [.press]),
        policy(.terminal, kinds: [.textEntry, .textButton], actions: [.textInput, .press], focusTargets: [.terminalCommand]),
        policy(.browser, kinds: [.textEntry, .textButton, .icon], actions: [.textInput, .press], focusTargets: [.browserAddress, .browserComment]),
        policy(.extensions, kinds: [.formAction, .capsule], actions: [.press]),
        policy(.memories, kinds: [.formAction, .icon], actions: [.press]),
        policy(.automations, kinds: [.formAction], actions: [.press]),
        policy(.menuBar, kinds: [.fullRow], actions: [.press])
        ]
    }

    public static var designSystemContracts: [QuillCodeNativeHitTargetContract] {
        [
            contract("design.icon", family: .designSystem, surface: "Design system", label: "Icon button", kind: .icon, minWidth: 44),
            contract("design.text-button", family: .designSystem, surface: "Design system", label: "Text button", kind: .textButton, minWidth: 72),
            contract("design.form-action", family: .designSystem, surface: "Design system", label: "Form action", kind: .formAction, minWidth: 56),
            contract("design.link", family: .designSystem, surface: "Design system", label: "Link", kind: .link, minWidth: 72),
            contract("design.text-entry", family: .designSystem, surface: "Design system", label: "Text entry", kind: .textEntry, minWidth: nil),
            contract("design.segmented-control", family: .designSystem, surface: "Design system", label: "Segmented control", kind: .segmentedControl, minWidth: nil),
            contract("design.adjustable-control", family: .designSystem, surface: "Design system", label: "Adjustable control", kind: .adjustableControl, minWidth: nil),
            contract("design.switch-row", family: .designSystem, surface: "Design system", label: "Switch row", kind: .switchRow, minWidth: nil),
            contract("design.owned-gesture", family: .designSystem, surface: "Design system", label: "Owned gesture target", kind: .ownedGesture, minWidth: nil),
            contract("design.full-row", family: .designSystem, surface: "Design system", label: "Full row button", kind: .fullRow, minWidth: nil),
            contract("design.capsule", family: .designSystem, surface: "Design system", label: "Capsule button", kind: .capsule, minWidth: nil)
        ]
    }

    private static func policy(
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

    static func surfaceContracts(for surface: WorkspaceSurface) -> [QuillCodeNativeHitTargetContract] {
        var contracts = persistentSurfaceContracts()
        contracts.append(contentsOf: canonicalTransientSurfaceContracts())
        contracts.append(contentsOf: commandContracts(from: surface.commands))
        contracts.append(contentsOf: conditionalPaneContracts(for: surface))
        return contracts
    }

    private static func persistentSurfaceContracts() -> [QuillCodeNativeHitTargetContract] {
        [
            contract("composer.input", family: .composer, surface: "Composer", label: "Message", kind: .textEntry, minWidth: nil, focusTarget: .composerMessage, testID: "composer-input"),
            contract("composer.send", family: .composer, surface: "Composer", label: "Send message", kind: .icon, minWidth: 44, testID: "send-button"),
            contract("composer.model-picker", family: .composer, surface: "Composer", label: "Model picker", kind: .capsule, minWidth: nil, testID: "model-picker-button"),
            contract("composer.mode-picker", family: .composer, surface: "Composer", label: "Mode picker", kind: .capsule, minWidth: nil, testID: "mode-picker-button"),
            contract("top-bar.overflow", family: .topBar, surface: "Top bar", label: "More workspace actions", kind: .icon, minWidth: 44, testID: "top-bar-overflow"),
            contract("sidebar.tools-menu", family: .sidebar, surface: "Sidebar", label: "Tools", kind: .fullRow, minWidth: nil, testID: "sidebar-tools-button"),
            contract("project.clear", family: .sidebar, surface: "Project header", label: "Clear project", kind: .icon, minWidth: 44, testID: "project-clear-button"),
            contract("workspace.chrome", family: .workspaceChrome, surface: "Workspace chrome", label: "Workspace command", kind: .fullRow, minWidth: nil, testID: "workspace-command")
        ]
    }

    private static func canonicalTransientSurfaceContracts() -> [QuillCodeNativeHitTargetContract] {
        [
            contract("sidebar.thread-row", family: .sidebarThreadList, surface: "Sidebar thread list", label: "Thread row", kind: .fullRow, minWidth: nil, testID: "sidebar-item"),
            contract("sidebar.thread-action", family: .sidebarThreadList, surface: "Sidebar thread list", label: "Thread row action", kind: .icon, minWidth: 44, testID: "sidebar-thread-action"),
            contract("transcript.message-action", family: .transcript, surface: "Transcript", label: "Message action", kind: .icon, minWidth: 44, testID: "message-action"),
            contract("transcript.artifact-link", family: .transcript, surface: "Transcript", label: "Artifact link", kind: .link, minWidth: 96, testID: "tool-card-artifact"),
            contract("transcript.tool-card", family: .toolCard, surface: "Tool card", label: "Tool details", kind: .fullRow, minWidth: nil, testID: "tool-card-details"),
            contract("transcript.tool-card-action", family: .toolCard, surface: "Tool card", label: "Tool action", kind: .textButton, minWidth: 72, testID: "tool-card-action"),
            contract("transcript.context-banner-action", family: .contextBanner, surface: "Context banner", label: "Context action", kind: .textButton, minWidth: 72, testID: "context-banner-action"),
            contract("command-palette.input", family: .commandPalette, surface: "Command palette", label: "Command search", kind: .textEntry, minWidth: nil, focusTarget: .commandPaletteSearch, testID: "command-palette-input"),
            contract("command-palette.result", family: .commandPalette, surface: "Command palette", label: "Command result", kind: .fullRow, minWidth: nil, testID: "command-palette-result"),
            contract("search.input", family: .search, surface: "Search", label: "Search chats", kind: .textEntry, minWidth: nil, focusTarget: .searchChats, testID: "search-input"),
            contract("search.result", family: .search, surface: "Search", label: "Search result", kind: .fullRow, minWidth: nil, testID: "search-result"),
            contract("settings.text-entry", family: .settings, surface: "Settings", label: "Settings text entry", kind: .textEntry, minWidth: nil, focusTarget: .settingsTrustedRouterBaseURL, testID: "settings-text-entry"),
            contract("settings.action", family: .settings, surface: "Settings", label: "Settings action", kind: .formAction, minWidth: 72, testID: "settings-action"),
            contract("model-picker.search", family: .modelPicker, surface: "Model picker", label: "Model search", kind: .textEntry, minWidth: nil, focusTarget: .modelPickerSearch, testID: "model-picker-search"),
            contract("model-picker.option", family: .modelPicker, surface: "Model picker", label: "Model option", kind: .fullRow, minWidth: nil, testID: "model-picker-option"),
            contract("model-picker.option-action", family: .modelPicker, surface: "Model picker", label: "Model option action", kind: .icon, minWidth: 44, testID: "model-picker-option-action"),
            contract("review.body", family: .review, surface: "Review", label: "Review body", kind: .textEntry, minWidth: nil, focusTarget: .reviewBody, testID: "review-body"),
            contract("review.thread-reply", family: .review, surface: "Review", label: "Review thread reply", kind: .textEntry, minWidth: nil, focusTarget: .reviewThreadReply, testID: "pr-review-thread-reply-input"),
            contract("review.mode", family: .review, surface: "Review", label: "Review mode", kind: .segmentedControl, minWidth: nil, testID: "review-mode"),
            contract("review.file-row", family: .review, surface: "Review", label: "Review file", kind: .fullRow, minWidth: nil, testID: "review-file"),
            contract("review.action", family: .review, surface: "Review", label: "Review action", kind: .formAction, minWidth: 72, testID: "review-action"),
            contract("secondary-pane.tab", family: .secondaryPane, surface: "Secondary pane", label: "Pane tab", kind: .capsule, minWidth: 72, testID: "secondary-pane-tab"),
            contract("terminal.family-entry", family: .terminal, surface: "Terminal", label: "Terminal command", kind: .textEntry, minWidth: nil, focusTarget: .terminalCommand, testID: "terminal-command"),
            contract("terminal.family-action", family: .terminal, surface: "Terminal", label: "Terminal action", kind: .textButton, minWidth: 64, testID: "terminal-action"),
            contract("browser.family-entry", family: .browser, surface: "Browser", label: "Browser address", kind: .textEntry, minWidth: nil, focusTarget: .browserAddress, testID: "browser-address"),
            contract("browser.family-action", family: .browser, surface: "Browser", label: "Browser action", kind: .textButton, minWidth: 64, testID: "browser-action"),
            contract("browser.family-icon", family: .browser, surface: "Browser", label: "Browser icon action", kind: .icon, minWidth: 44, testID: "browser-icon-action"),
            contract("browser.comment-entry", family: .browser, surface: "Browser", label: "Browser comment", kind: .textEntry, minWidth: nil, focusTarget: .browserComment, testID: "browser-comment-input"),
            contract("extensions.family-entry", family: .extensions, surface: "Extensions", label: "Extension action", kind: .formAction, minWidth: 74, testID: "extension-action"),
            contract("extensions.reference-action", family: .extensions, surface: "Extensions", label: "MCP resource or prompt action", kind: .capsule, minWidth: 96, testID: "extension-reference-action"),
            contract("memories.family-entry", family: .memories, surface: "Memories", label: "Add memory", kind: .formAction, minWidth: 56, testID: "memory-add"),
            contract("memories.item-action", family: .memories, surface: "Memories", label: "Memory row action", kind: .icon, minWidth: 44, testID: "memory-row-action"),
            contract("automations.family-entry", family: .automations, surface: "Automations", label: "Create automation", kind: .formAction, minWidth: 90, testID: "automation-create"),
            contract("menu-bar.action", family: .menuBar, surface: "Menu bar", label: "Menu bar action", kind: .fullRow, minWidth: nil, testID: "menu-bar-action")
        ]
    }

    private static func commandContracts(from commands: [WorkspaceCommandSurface]) -> [QuillCodeNativeHitTargetContract] {
        commands.map { command in
            commandContract(command)
        }
    }

    private static func commandContract(_ command: WorkspaceCommandSurface) -> QuillCodeNativeHitTargetContract {
        let kind: QuillCodeNativeHitTargetKind
        let surface: String
        let minWidth: Double?
        switch command.id {
        case "add-project":
            kind = .icon
            surface = "Project header"
            minWidth = 44
        case "new-chat", "search", "toggle-extensions", "toggle-automations":
            kind = .fullRow
            surface = "Sidebar primary"
            minWidth = nil
        case "toggle-terminal", "toggle-browser", "toggle-memories", "toggle-activity", "command-palette":
            kind = .fullRow
            surface = "Sidebar tools"
            minWidth = nil
        case "computer-use-setup", "keyboard-shortcuts", "settings", "disconnect-all":
            kind = .fullRow
            surface = "Top bar overflow"
            minWidth = nil
        default:
            kind = .fullRow
            surface = "Command palette"
            minWidth = nil
        }
        return contract(
            "command.\(command.id)",
            family: commandFamily(command.id),
            surface: surface,
            label: command.title,
            kind: kind,
            minWidth: minWidth,
            commandID: command.id,
            source: "WorkspaceCommandSurface"
        )
    }

    private static func commandFamily(_ commandID: String) -> QuillCodeInteractionSurfaceFamily {
        switch commandID {
        case "add-project", "new-chat", "search", "toggle-extensions", "toggle-automations",
            "toggle-terminal", "toggle-browser", "toggle-memories", "toggle-activity":
            return .sidebar
        case "computer-use-setup", "keyboard-shortcuts", "settings", "disconnect-all":
            return .topBar
        default:
            return .commandPalette
        }
    }

    private static func conditionalPaneContracts(for surface: WorkspaceSurface) -> [QuillCodeNativeHitTargetContract] {
        var contracts: [QuillCodeNativeHitTargetContract] = []

        if surface.terminal.isVisible {
            contracts.append(contract("terminal.command", family: .terminal, surface: "Terminal", label: "Terminal command", kind: .textEntry, minWidth: nil, focusTarget: .terminalCommand, testID: "terminal-command"))
            contracts.append(contract("terminal.run", family: .terminal, surface: "Terminal", label: surface.terminal.commandActionTitle, kind: .textButton, minWidth: 64, testID: "terminal-run"))
            contracts.append(contract("terminal.clear", family: .terminal, surface: "Terminal", label: "Clear", kind: .textButton, minWidth: 56, testID: "terminal-clear"))
        }

        if surface.browser.isVisible {
            contracts.append(contract("browser.address", family: .browser, surface: "Browser", label: "Browser address", kind: .textEntry, minWidth: nil, focusTarget: .browserAddress, testID: "browser-address"))
            contracts.append(contract("browser.open", family: .browser, surface: "Browser", label: "Open", kind: .textButton, minWidth: 64, testID: "browser-open"))
            contracts.append(contract("browser.new-tab", family: .browser, surface: "Browser", label: "New tab", kind: .icon, minWidth: 44, testID: "browser-new-tab"))
            contracts.append(contract("browser.comment", family: .browser, surface: "Browser", label: "Browser comment", kind: .textEntry, minWidth: nil, focusTarget: .browserComment, testID: "browser-comment-input"))
            contracts.append(contract("browser.add-comment", family: .browser, surface: "Browser", label: "Add comment", kind: .textButton, minWidth: 92, testID: "browser-add-comment"))
        }

        if surface.extensions.isVisible {
            if surface.extensions.items.contains(where: { item in
                item.installCommandID != nil || item.updateCommandID != nil || item.startCommandID != nil || item.stopCommandID != nil
            }) {
                contracts.append(contract("extensions.action", family: .extensions, surface: "Extensions", label: "Extension action", kind: .formAction, minWidth: 74, testID: "extension-action"))
            }
            if surface.extensions.items.contains(where: { !$0.resourceActions.isEmpty || !$0.promptActions.isEmpty }) {
                contracts.append(contract("extensions.mcp-reference", family: .extensions, surface: "Extensions", label: "MCP resource or prompt action", kind: .capsule, minWidth: 96, testID: "extension-reference-action"))
            }
        }

        if surface.memories.isVisible {
            contracts.append(contract("memories.add", family: .memories, surface: "Memories", label: "Add memory", kind: .formAction, minWidth: 56, testID: "memory-add"))
            if surface.memories.items.contains(where: { $0.canEdit }) {
                contracts.append(contract("memories.edit", family: .memories, surface: "Memories", label: "Edit memory", kind: .icon, minWidth: 44, testID: "memory-edit"))
            }
            if surface.memories.items.contains(where: { $0.canDelete }) {
                contracts.append(contract("memories.delete", family: .memories, surface: "Memories", label: "Forget memory", kind: .icon, minWidth: 44, testID: "memory-delete"))
            }
        }

        if surface.automations.isVisible {
            if surface.automations.createThreadFollowUpCommand != nil || surface.automations.createWorkspaceScheduleCommand != nil {
                contracts.append(contract("automations.create", family: .automations, surface: "Automations", label: "Create automation", kind: .formAction, minWidth: 90, testID: "automation-create"))
            }
            if surface.automations.workflows.contains(where: { $0.runCommandID != nil }) {
                contracts.append(contract("automations.run", family: .automations, surface: "Automations", label: "Run automation", kind: .formAction, minWidth: 56, testID: "automation-run"))
            }
            if surface.automations.workflows.contains(where: { $0.primaryCommandID != nil }) {
                contracts.append(contract("automations.primary", family: .automations, surface: "Automations", label: "Pause or resume automation", kind: .formAction, minWidth: 56, testID: "automation-primary-action"))
            }
            if surface.automations.workflows.contains(where: { $0.deleteCommandID != nil }) {
                contracts.append(contract("automations.delete", family: .automations, surface: "Automations", label: "Delete automation", kind: .formAction, minWidth: 56, testID: "automation-delete"))
            }
        }

        if surface.transcript.thinking?.traceLines.isEmpty == false {
            contracts.append(contract("transcript.thinking-trace", family: .transcript, surface: "Transcript", label: "Thinking trace", kind: .capsule, minWidth: 96, testID: "thinking-trace"))
        }

        return contracts
    }

    private static func contract(
        _ id: String,
        family: QuillCodeInteractionSurfaceFamily,
        surface: String,
        label: String,
        kind: QuillCodeNativeHitTargetKind,
        minWidth: Double?,
        minHeight: Double = Double(QuillCodeMetrics.minimumHitTarget),
        focusTarget: QuillCodeNativeFocusTarget? = nil,
        testID: String? = nil,
        commandID: String? = nil,
        source: String = "SwiftUI"
    ) -> QuillCodeNativeHitTargetContract {
        QuillCodeNativeHitTargetContract(
            id: id,
            family: family,
            surface: surface,
            label: label,
            kind: kind,
            minWidth: minWidth,
            minHeight: minHeight,
            focusTarget: focusTarget,
            testID: normalizedNativeTestID(testID),
            commandID: commandID,
            source: source
        )
    }

    private static func normalizedNativeTestID(_ testID: String?) -> String? {
        guard let testID else { return nil }
        let trimmed = testID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return testID }
        return trimmed.hasPrefix("quillcode-") ? trimmed : "quillcode-\(trimmed)"
    }
}
