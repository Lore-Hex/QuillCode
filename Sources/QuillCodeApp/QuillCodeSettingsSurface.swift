import Foundation
import QuillCodeCore
import QuillComputerUseKit

public struct ComputerUseRequirementSurface: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var title: String
    public var detail: String
    public var statusLabel: String
    public var isGranted: Bool
    public var command: WorkspaceCommandSurface

    public init(
        id: String,
        title: String,
        detail: String,
        statusLabel: String,
        isGranted: Bool,
        command: WorkspaceCommandSurface
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.statusLabel = statusLabel
        self.isGranted = isGranted
        self.command = command
    }
}

public struct WorkspaceSettingsSurface: Codable, Sendable, Hashable {
    public var apiBaseURL: String
    public var authMode: TrustedRouterAuthMode
    public var developerOverrideEnabled: Bool
    public var hasStoredAPIKey: Bool
    public var signInURL: String
    public var apiKeyStatusLabel: String
    public var loginStatusLabel: String
    public var accountLabel: String?
    public var runtimeIssue: RuntimeIssueSurface?
    public var computerUseStatus: ComputerUseStatus
    public var computerUseSetupCommand: WorkspaceCommandSurface
    public var computerUseScreenRecordingCommand: WorkspaceCommandSurface
    public var computerUseAccessibilityCommand: WorkspaceCommandSurface
    public var computerUseRefreshCommand: WorkspaceCommandSurface
    public var computerUseStatusLabel: String
    public var computerUseSetupSummary: String
    public var computerUseNextAction: String
    public var computerUseRequirements: [ComputerUseRequirementSurface]

    public init(
        config: AppConfig,
        hasStoredAPIKey: Bool,
        runtimeIssue: RuntimeIssueSurface? = nil,
        computerUseStatus: ComputerUseStatus = .permissionStatus(
            screenRecordingGranted: false,
            accessibilityGranted: false
        )
    ) {
        self.apiBaseURL = config.apiBaseURL
        self.authMode = config.authMode
        self.developerOverrideEnabled = config.developerOverrideEnabled
        self.hasStoredAPIKey = hasStoredAPIKey
        self.signInURL = TrustedRouterDefaults.loopbackCallbackURL
        self.accountLabel = config.trustedRouterAccount?.displayLabel
        self.runtimeIssue = runtimeIssue
        self.computerUseStatus = computerUseStatus
        self.computerUseSetupCommand = WorkspaceCommandSurface.computerUseSetup(isEnabled: !computerUseStatus.available)
        self.computerUseScreenRecordingCommand = WorkspaceCommandSurface.computerUseScreenRecordingSettings(
            isEnabled: !computerUseStatus.screenRecordingGranted
        )
        self.computerUseAccessibilityCommand = WorkspaceCommandSurface.computerUseAccessibilitySettings(
            isEnabled: !computerUseStatus.accessibilityGranted
        )
        self.computerUseRefreshCommand = WorkspaceCommandSurface.computerUseRefresh
        self.computerUseStatusLabel = Self.computerUseStatusLabel(computerUseStatus)
        self.computerUseSetupSummary = Self.computerUseSetupSummary(computerUseStatus)
        self.computerUseNextAction = Self.computerUseNextAction(computerUseStatus)
        self.computerUseRequirements = Self.computerUseRequirements(
            status: computerUseStatus,
            screenRecordingCommand: computerUseScreenRecordingCommand,
            accessibilityCommand: computerUseAccessibilityCommand
        )
        switch config.authMode {
        case .oauth:
            self.apiKeyStatusLabel = hasStoredAPIKey ? "Signed in" : "Not signed in"
            if hasStoredAPIKey, let accountLabel {
                self.loginStatusLabel = "Signed in as \(accountLabel)"
            } else {
                self.loginStatusLabel = hasStoredAPIKey ? "TrustedRouter OAuth ready" : "TrustedRouter login required"
            }
        case .developerOverride:
            self.apiKeyStatusLabel = hasStoredAPIKey ? "API key configured" : "No API key saved"
            self.loginStatusLabel = hasStoredAPIKey
                ? "TrustedRouter developer override ready"
                : "Developer override needs an API key"
        }
    }

    private enum CodingKeys: String, CodingKey {
        case apiBaseURL
        case authMode
        case developerOverrideEnabled
        case hasStoredAPIKey
        case signInURL
        case apiKeyStatusLabel
        case loginStatusLabel
        case accountLabel
        case runtimeIssue
        case computerUseStatus
        case computerUseSetupCommand
        case computerUseScreenRecordingCommand
        case computerUseAccessibilityCommand
        case computerUseRefreshCommand
        case computerUseStatusLabel
        case computerUseSetupSummary
        case computerUseNextAction
        case computerUseRequirements
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.apiBaseURL = try container.decode(String.self, forKey: .apiBaseURL)
        self.authMode = try container.decode(TrustedRouterAuthMode.self, forKey: .authMode)
        self.developerOverrideEnabled = try container.decode(Bool.self, forKey: .developerOverrideEnabled)
        self.hasStoredAPIKey = try container.decode(Bool.self, forKey: .hasStoredAPIKey)
        self.signInURL = try container.decode(String.self, forKey: .signInURL)
        self.apiKeyStatusLabel = try container.decode(String.self, forKey: .apiKeyStatusLabel)
        self.loginStatusLabel = try container.decode(String.self, forKey: .loginStatusLabel)
        self.accountLabel = try container.decodeIfPresent(String.self, forKey: .accountLabel)
        self.runtimeIssue = try container.decodeIfPresent(RuntimeIssueSurface.self, forKey: .runtimeIssue)
        let decodedComputerUseStatus = try container.decodeIfPresent(
            ComputerUseStatus.self,
            forKey: .computerUseStatus
        ) ?? .permissionStatus(screenRecordingGranted: false, accessibilityGranted: false)
        self.computerUseStatus = decodedComputerUseStatus
        self.computerUseSetupCommand = try container.decodeIfPresent(
            WorkspaceCommandSurface.self,
            forKey: .computerUseSetupCommand
        ) ?? .computerUseSetup(isEnabled: !decodedComputerUseStatus.available)
        self.computerUseScreenRecordingCommand = try container.decodeIfPresent(
            WorkspaceCommandSurface.self,
            forKey: .computerUseScreenRecordingCommand
        ) ?? .computerUseScreenRecordingSettings(isEnabled: !decodedComputerUseStatus.screenRecordingGranted)
        self.computerUseAccessibilityCommand = try container.decodeIfPresent(
            WorkspaceCommandSurface.self,
            forKey: .computerUseAccessibilityCommand
        ) ?? .computerUseAccessibilitySettings(isEnabled: !decodedComputerUseStatus.accessibilityGranted)
        self.computerUseRefreshCommand = try container.decodeIfPresent(
            WorkspaceCommandSurface.self,
            forKey: .computerUseRefreshCommand
        ) ?? .computerUseRefresh
        self.computerUseStatusLabel = try container.decodeIfPresent(String.self, forKey: .computerUseStatusLabel)
            ?? Self.computerUseStatusLabel(decodedComputerUseStatus)
        self.computerUseSetupSummary = try container.decodeIfPresent(String.self, forKey: .computerUseSetupSummary)
            ?? Self.computerUseSetupSummary(decodedComputerUseStatus)
        self.computerUseNextAction = try container.decodeIfPresent(String.self, forKey: .computerUseNextAction)
            ?? Self.computerUseNextAction(decodedComputerUseStatus)
        self.computerUseRequirements = try container.decodeIfPresent(
            [ComputerUseRequirementSurface].self,
            forKey: .computerUseRequirements
        ) ?? Self.computerUseRequirements(
            status: decodedComputerUseStatus,
            screenRecordingCommand: computerUseScreenRecordingCommand,
            accessibilityCommand: computerUseAccessibilityCommand
        )
    }

    private static func computerUseStatusLabel(_ status: ComputerUseStatus) -> String {
        if status.available {
            return "Ready"
        }
        if status.unavailableReason != nil {
            return "Unavailable"
        }
        if !status.screenRecordingGranted && !status.accessibilityGranted {
            return "Setup needed"
        }
        if !status.screenRecordingGranted {
            return "Screen Recording needed"
        }
        return "Accessibility needed"
    }

    private static func computerUseSetupSummary(_ status: ComputerUseStatus) -> String {
        if status.available {
            return "Ready for screenshots, clicks, typing, scrolling, and keyboard shortcuts."
        }
        if let unavailableReason = status.unavailableReason {
            return unavailableReason
        }
        return "Computer Use needs desktop permissions before QuillCode can inspect or control the screen."
    }

    private static func computerUseNextAction(_ status: ComputerUseStatus) -> String {
        if status.available {
            return "Computer Use is enabled. Ask QuillCode to inspect the screen or operate an app."
        }
        if status.unavailableReason != nil {
            return "Install or enable the required desktop backend, then refresh status."
        }
        if !status.screenRecordingGranted && !status.accessibilityGranted {
            return "Open Screen Recording first, enable QuillCode, then open Accessibility."
        }
        if !status.screenRecordingGranted {
            return "Open Screen Recording, enable QuillCode, then refresh status."
        }
        return "Open Accessibility, enable QuillCode, then refresh status."
    }

    private static func computerUseRequirements(
        status: ComputerUseStatus,
        screenRecordingCommand: WorkspaceCommandSurface,
        accessibilityCommand: WorkspaceCommandSurface
    ) -> [ComputerUseRequirementSurface] {
        guard status.unavailableReason == nil else {
            return []
        }
        return [
            ComputerUseRequirementSurface(
                id: "screen-recording",
                title: "Screen Recording",
                detail: "Required for screenshots and visual inspection.",
                statusLabel: status.screenRecordingGranted ? "Granted" : "Required",
                isGranted: status.screenRecordingGranted,
                command: screenRecordingCommand
            ),
            ComputerUseRequirementSurface(
                id: "accessibility",
                title: "Accessibility",
                detail: "Required for clicks, typing, scrolling, cursor moves, and keyboard shortcuts.",
                statusLabel: status.accessibilityGranted ? "Granted" : "Required",
                isGranted: status.accessibilityGranted,
                command: accessibilityCommand
            )
        ]
    }
}

public struct WorkspaceSettingsUpdate: Sendable, Hashable {
    public var apiBaseURL: String
    public var authMode: TrustedRouterAuthMode
    public var developerOverrideEnabled: Bool
    public var replacementAPIKey: String?
    public var shouldClearAPIKey: Bool

    public init(
        apiBaseURL: String,
        authMode: TrustedRouterAuthMode = .oauth,
        developerOverrideEnabled: Bool,
        replacementAPIKey: String? = nil,
        shouldClearAPIKey: Bool = false
    ) {
        self.apiBaseURL = apiBaseURL
        self.authMode = developerOverrideEnabled ? .developerOverride : authMode
        self.developerOverrideEnabled = developerOverrideEnabled || authMode == .developerOverride
        self.replacementAPIKey = replacementAPIKey
        self.shouldClearAPIKey = shouldClearAPIKey
    }
}
