import Foundation

public enum QuillCodeNativeHitTargetKind: String, Codable, Sendable, Hashable, CaseIterable {
    case icon
    case textButton
    case formAction
    case link
    case textEntry
    case segmentedControl
    case adjustableControl
    case switchRow
    case ownedGesture
    case fullRow
    case capsule
}
public enum QuillCodeNativeHitTargetAction: String, Codable, Sendable, Hashable, CaseIterable {
    case adjust
    case link
    case ownedGesture = "owned-gesture"
    case press
    case textInput = "text-input"
}

public enum QuillCodeNativeFocusTarget: String, Codable, Sendable, Hashable, CaseIterable {
    case browserAddress = "browser.address"
    case browserComment = "browser.comment"
    case commandPaletteSearch = "command-palette.search"
    case composerMessage = "composer.message"
    case modelPickerSearch = "model-picker.search"
    case reviewBody = "review.body"
    case reviewThreadReply = "review.thread-reply"
    case searchChats = "search.chats"
    case settingsTrustedRouterBaseURL = "settings.trustedrouter-base-url"
    case terminalCommand = "terminal.command"
}

extension QuillCodeNativeHitTargetKind {
    public var renderedKind: String {
        switch self {
        case .icon:
            return "icon"
        case .textButton:
            return "text"
        case .formAction:
            return "form-action"
        case .link:
            return "link"
        case .textEntry:
            return "text-entry"
        case .segmentedControl:
            return "segmented"
        case .adjustableControl:
            return "adjustable"
        case .switchRow:
            return "switch-row"
        case .ownedGesture:
            return "owned"
        case .fullRow:
            return "row"
        case .capsule:
            return "capsule"
        }
    }

    public var renderedClassName: String {
        "hit-target-\(renderedKind)"
    }

    var action: QuillCodeNativeHitTargetAction {
        switch self {
        case .textEntry:
            return .textInput
        case .adjustableControl:
            return .adjust
        case .link:
            return .link
        case .ownedGesture:
            return .ownedGesture
        case .icon, .textButton, .formAction, .segmentedControl, .switchRow, .fullRow, .capsule:
            return .press
        }
    }

    var allowsNestedInteractiveChildren: Bool { false }

    var requiresUnblockedInterior: Bool { true }

    var requiresTactileFeedback: Bool {
        self != .textEntry
    }

    var allowsTextSelection: Bool {
        self == .textEntry
    }
}

public enum QuillCodeInteractionSurfaceFamily: String, Codable, Sendable, Hashable, CaseIterable {
    case designSystem = "design-system"
    case workspaceChrome = "workspace-chrome"
    case sidebar
    case sidebarThreadList = "sidebar-thread-list"
    case topBar = "top-bar"
    case composer
    case transcript
    case toolCard = "tool-card"
    case contextBanner = "context-banner"
    case commandPalette = "command-palette"
    case search
    case settings
    case modelPicker = "model-picker"
    case review
    case secondaryPane = "secondary-pane"
    case terminal
    case browser
    case extensions
    case memories
    case automations
    case menuBar = "menu-bar"
}
