import Foundation
import QuillCodeCore
import QuillComputerUseKit

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
    public var modelCatalogStatusLabel: String
    public var modelCatalogStatusDetail: String?
    public var modelProviderHealthLabel: String?
    public var modelProviderHealthDetail: String?
    public var computerUseStatus: ComputerUseStatus
    public var computerUseSetupCommand: WorkspaceCommandSurface
    public var computerUseScreenRecordingCommand: WorkspaceCommandSurface
    public var computerUseAccessibilityCommand: WorkspaceCommandSurface
    public var computerUseRefreshCommand: WorkspaceCommandSurface
    public var computerUseStatusLabel: String
    public var computerUseSetupSummary: String
    public var computerUseNextAction: String
    public var computerUseRequirements: [ComputerUseRequirementSurface]
    public var computerUseApprovedBundleIdentifiers: [String]
    public var computerUseApprovedAppNames: [String]
    public var computerUseApprovalStatusLabel: String
    public var computerUseApprovalSummary: String

    public init(
        config: AppConfig,
        hasStoredAPIKey: Bool,
        runtimeIssue: RuntimeIssueSurface? = nil,
        computerUseStatus: ComputerUseStatus = .permissionStatus(
            screenRecordingGranted: false,
            accessibilityGranted: false
        ),
        modelCatalogStatus: ModelCatalogStatus = .bundled,
        modelProviderHealthSummary: ModelProviderHealthSummary = .summarize([])
    ) {
        self.apiBaseURL = config.apiBaseURL
        self.authMode = config.authMode
        self.developerOverrideEnabled = config.developerOverrideEnabled
        self.hasStoredAPIKey = hasStoredAPIKey
        self.signInURL = TrustedRouterDefaults.loopbackCallbackURL
        self.accountLabel = config.trustedRouterAccount?.displayLabel
        self.runtimeIssue = runtimeIssue
        self.modelCatalogStatusLabel = modelCatalogStatus.statusLabel()
        self.modelCatalogStatusDetail = modelCatalogStatus.detailLabel()
        self.modelProviderHealthLabel = modelProviderHealthSummary.label
        self.modelProviderHealthDetail = modelProviderHealthSummary.detail
        self.computerUseStatus = computerUseStatus
        self.computerUseSetupCommand = WorkspaceCommandSurface.computerUseSetup(isEnabled: !computerUseStatus.available)
        self.computerUseScreenRecordingCommand = WorkspaceCommandSurface.computerUseScreenRecordingSettings(
            isEnabled: !computerUseStatus.screenRecordingGranted
        )
        self.computerUseAccessibilityCommand = WorkspaceCommandSurface.computerUseAccessibilitySettings(
            isEnabled: !computerUseStatus.accessibilityGranted
        )
        self.computerUseRefreshCommand = WorkspaceCommandSurface.computerUseRefresh
        self.computerUseStatusLabel = ComputerUseSettingsProjection.statusLabel(computerUseStatus)
        self.computerUseSetupSummary = ComputerUseSettingsProjection.setupSummary(computerUseStatus)
        self.computerUseNextAction = ComputerUseSettingsProjection.nextAction(computerUseStatus)
        self.computerUseRequirements = ComputerUseSettingsProjection.requirements(
            status: computerUseStatus,
            screenRecordingCommand: computerUseScreenRecordingCommand,
            accessibilityCommand: computerUseAccessibilityCommand
        )
        self.computerUseApprovedBundleIdentifiers = config.computerUseApprovedBundleIdentifiers
        self.computerUseApprovedAppNames = config.computerUseApprovedAppNames
        self.computerUseApprovalStatusLabel = ComputerUseSettingsProjection.approvalStatusLabel(config)
        self.computerUseApprovalSummary = ComputerUseSettingsProjection.approvalSummary(config)
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
        case modelCatalogStatusLabel
        case modelCatalogStatusDetail
        case modelProviderHealthLabel
        case modelProviderHealthDetail
        case computerUseStatus
        case computerUseSetupCommand
        case computerUseScreenRecordingCommand
        case computerUseAccessibilityCommand
        case computerUseRefreshCommand
        case computerUseStatusLabel
        case computerUseSetupSummary
        case computerUseNextAction
        case computerUseRequirements
        case computerUseApprovedBundleIdentifiers
        case computerUseApprovedAppNames
        case computerUseApprovalStatusLabel
        case computerUseApprovalSummary
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
        self.modelCatalogStatusLabel = try container.decodeIfPresent(String.self, forKey: .modelCatalogStatusLabel)
            ?? ModelCatalogStatus.bundled.statusLabel()
        self.modelCatalogStatusDetail = try container.decodeIfPresent(String.self, forKey: .modelCatalogStatusDetail)
            ?? ModelCatalogStatus.bundled.detailLabel()
        self.modelProviderHealthLabel = try container.decodeIfPresent(String.self, forKey: .modelProviderHealthLabel)
        self.modelProviderHealthDetail = try container.decodeIfPresent(String.self, forKey: .modelProviderHealthDetail)
        let decodedComputerUseStatus = try container.decodeIfPresent(
            ComputerUseStatus.self,
            forKey: .computerUseStatus
        ) ?? ComputerUseSettingsProjection.defaultStatus()
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
            ?? ComputerUseSettingsProjection.statusLabel(decodedComputerUseStatus)
        self.computerUseSetupSummary = try container.decodeIfPresent(String.self, forKey: .computerUseSetupSummary)
            ?? ComputerUseSettingsProjection.setupSummary(decodedComputerUseStatus)
        self.computerUseNextAction = try container.decodeIfPresent(String.self, forKey: .computerUseNextAction)
            ?? ComputerUseSettingsProjection.nextAction(decodedComputerUseStatus)
        self.computerUseRequirements = try container.decodeIfPresent(
            [ComputerUseRequirementSurface].self,
            forKey: .computerUseRequirements
        ) ?? ComputerUseSettingsProjection.requirements(
            status: decodedComputerUseStatus,
            screenRecordingCommand: computerUseScreenRecordingCommand,
            accessibilityCommand: computerUseAccessibilityCommand
        )
        let decodedBundleIdentifiers = try container.decodeIfPresent(
            [String].self,
            forKey: .computerUseApprovedBundleIdentifiers
        ) ?? []
        let decodedAppNames = try container.decodeIfPresent(
            [String].self,
            forKey: .computerUseApprovedAppNames
        ) ?? []
        let approvalConfig = AppConfig(
            computerUseApprovedBundleIdentifiers: decodedBundleIdentifiers,
            computerUseApprovedAppNames: decodedAppNames
        )
        self.computerUseApprovedBundleIdentifiers = approvalConfig.computerUseApprovedBundleIdentifiers
        self.computerUseApprovedAppNames = approvalConfig.computerUseApprovedAppNames
        self.computerUseApprovalStatusLabel = try container.decodeIfPresent(
            String.self,
            forKey: .computerUseApprovalStatusLabel
        ) ?? ComputerUseSettingsProjection.approvalStatusLabel(approvalConfig)
        self.computerUseApprovalSummary = try container.decodeIfPresent(
            String.self,
            forKey: .computerUseApprovalSummary
        ) ?? ComputerUseSettingsProjection.approvalSummary(approvalConfig)
    }
}
