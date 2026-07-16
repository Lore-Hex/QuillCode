import XCTest
import QuillCodeCore
import QuillComputerUseKit
@testable import QuillCodeApp

@MainActor
final class WorkspaceSettingsRuntimeSurfaceTests: XCTestCase {
    func testWorkspaceSurfaceBuildsDefaultSettingsAndComputerUseCommands() {
        let settings = QuillCodeWorkspaceModel().surface().settings

        XCTAssertEqual(settings.apiBaseURL, TrustedRouterDefaults.defaultAPIBaseURL)
        XCTAssertFalse(settings.developerOverrideEnabled)
        XCTAssertFalse(settings.hasStoredAPIKey)
        XCTAssertEqual(settings.authMode, .oauth)
        XCTAssertEqual(settings.signInURL, TrustedRouterDefaults.loopbackCallbackURL)
        XCTAssertEqual(settings.apiKeyStatusLabel, "Not signed in")
        XCTAssertNil(settings.trustedRouterAccountBalance)
        XCTAssertFalse(settings.trustedRouterCreditsRefreshCommand.isEnabled)
        XCTAssertEqual(settings.modelCatalogStatusLabel, "Bundled catalog")
        XCTAssertEqual(settings.modelProviderHealthLabel, "Provider health unavailable")
        XCTAssertNil(settings.reviewModel)
        XCTAssertEqual(settings.reviewDelivery, .current)
        XCTAssertEqual(settings.computerUseStatus.message, "Needs Screen Recording + Accessibility")
        XCTAssertEqual(settings.computerUseSetupCommand.id, "computer-use-setup")
        XCTAssertEqual(settings.computerUseScreenRecordingCommand.id, "computer-use-open-screen-recording")
        XCTAssertEqual(settings.computerUseAccessibilityCommand.id, "computer-use-open-accessibility")
        XCTAssertEqual(settings.computerUseRefreshCommand.id, "computer-use-refresh")
        XCTAssertEqual(settings.computerUseStatusLabel, "Setup needed")
        XCTAssertEqual(
            settings.computerUseSetupSummary,
            "Computer Use needs desktop permissions before QuillCode can inspect or control the screen."
        )
        XCTAssertEqual(
            settings.computerUseNextAction,
            "Open Screen Recording first, enable QuillCode, then open Accessibility."
        )
        XCTAssertEqual(settings.computerUseOnboardingSteps, [
            "Enable Screen Recording so QuillCode can see screenshots and verify visual state.",
            "Enable Accessibility so QuillCode can click, type, scroll, move the cursor, and send shortcuts.",
            "Return to QuillCode and refresh status after macOS accepts the permission changes.",
            "Add foreground app approvals when you want Computer Use limited to specific apps."
        ])
        XCTAssertEqual(settings.computerUseRequirements.map(\.title), ["Screen Recording", "Accessibility"])
        XCTAssertEqual(settings.computerUseRequirements.map(\.statusLabel), ["Required", "Required"])
        XCTAssertEqual(settings.computerUseRequirements.map(\.isGranted), [false, false])
        XCTAssertEqual(settings.computerUseRequirements.first?.command.id, "computer-use-open-screen-recording")
        XCTAssertEqual(settings.computerUseApprovedBundleIdentifiers, [])
        XCTAssertEqual(settings.computerUseApprovedAppNames, [])
        XCTAssertEqual(settings.computerUseApprovalStatusLabel, "Unrestricted")
        XCTAssertEqual(settings.browserAllowedDomains, [])
        XCTAssertEqual(settings.browserBlockedDomains, [])
        XCTAssertEqual(settings.browserDomainPolicyStatusLabel, "Unrestricted")
        XCTAssertEqual(settings.notificationPreferences, QuillCodeNotificationPreferences())
        XCTAssertEqual(settings.notificationStatusLabel, "Smart")
        XCTAssertEqual(settings.runSpendFuseUSD, 1.0)
        XCTAssertFalse(settings.runSpendPeriodLimits.hasAnyLimit)
        XCTAssertEqual(settings.runSpendLimitStatusLabel, "Fuse")
        XCTAssertEqual(
            settings.computerUseApprovalSummary,
            "Computer Use may operate whichever app is in front. Add approvals to restrict control to named apps."
        )
        XCTAssertEqual(
            settings.browserDomainPolicySummary,
            "Browser can open any http or https domain. Local files still stay workspace-scoped by the browser resolver."
        )
        XCTAssertEqual(
            settings.notificationSummary,
            "Agent runs notify only when QuillCode is in the background. Automation runs post completion alerts."
        )
        XCTAssertEqual(
            settings.runSpendLimitSummary,
            "Local spend controls review each thread after $1.00. These do not replace TrustedRouter account limits."
        )
    }

    func testSettingsSurfaceShowsTrustedRouterAccount() {
        let config = AppConfig(
            authMode: .oauth,
            trustedRouterAccount: TrustedRouterAccountProfile(
                userID: "usr_123",
                email: "quill@example.com"
            )
        )
        let settings = WorkspaceSettingsSurface(config: config, hasStoredAPIKey: true)

        XCTAssertEqual(settings.apiKeyStatusLabel, "Signed in")
        XCTAssertEqual(settings.loginStatusLabel, "Signed in as quill@example.com")
        XCTAssertEqual(settings.accountLabel, "quill@example.com")
    }

    func testSettingsSurfaceShowsLiveTrustedRouterBalanceAndRefreshCommand() throws {
        let snapshot = try XCTUnwrap(TrustedRouterCreditsSnapshot(
            balance: 19.75,
            currency: "USD",
            fetchedAt: Date()
        ))
        let settings = WorkspaceSettingsSurface(
            config: AppConfig(),
            hasStoredAPIKey: true,
            trustedRouterCredits: .current(snapshot)
        )

        XCTAssertEqual(settings.trustedRouterAccountBalance?.amountLabel, "$19.75")
        XCTAssertEqual(settings.trustedRouterAccountBalance?.statusLabel, "Balance current")
        XCTAssertEqual(settings.trustedRouterCreditsRefreshCommand.id, "trustedrouter-credits-refresh")
        XCTAssertTrue(settings.trustedRouterCreditsRefreshCommand.isEnabled)
    }

    func testSettingsSurfaceShowsModelCatalogFallbackDiagnostics() {
        let settings = WorkspaceSettingsSurface(
            config: AppConfig(),
            hasStoredAPIKey: true,
            modelCatalogStatus: .fallbackAfterFailure("HTTP 503")
        )

        XCTAssertEqual(settings.modelCatalogStatusLabel, "Bundled fallback · refresh failed")
        XCTAssertEqual(
            settings.modelCatalogStatusDetail,
            "The latest TrustedRouter model refresh failed: HTTP 503"
        )
    }

    func testSettingsSurfaceCarriesCodeReviewSettings() {
        let settings = WorkspaceSettingsSurface(
            config: AppConfig(
                reviewModel: "/prometheus",
                reviewDelivery: .detached
            ),
            hasStoredAPIKey: true
        )

        XCTAssertEqual(settings.reviewModel, TrustedRouterDefaults.prometheusModel)
        XCTAssertEqual(settings.reviewDelivery, .detached)
    }

    func testSettingsSurfaceShowsProviderHealthDiagnostics() {
        let summary = ModelProviderHealthSummary.summarize([
            ModelInfo(
                id: "acme/code-pro",
                provider: "acme",
                displayName: "Code Pro",
                category: "Coding",
                capabilities: ModelCapabilities(status: "degraded")
            ),
            ModelInfo(
                id: "z-ai/glm-5.2",
                provider: "z-ai",
                displayName: "GLM 5.2",
                category: "Safety",
                capabilities: ModelCapabilities(status: "available")
            )
        ])
        let settings = WorkspaceSettingsSurface(
            config: AppConfig(),
            hasStoredAPIKey: true,
            modelProviderHealthSummary: summary
        )

        XCTAssertEqual(settings.modelProviderHealthLabel, "Provider health: 1 provider needs attention")
        XCTAssertTrue(settings.modelProviderHealthDetail?.contains("acme: degraded") == true)
    }

    func testSettingsSurfaceShowsComputerUseApprovalSummary() {
        let config = AppConfig(
            computerUseApprovedBundleIdentifiers: ["com.apple.Terminal", "com.google.Chrome"],
            computerUseApprovedAppNames: ["Terminal"],
            browserAllowedDomains: ["trustedrouter.com", "localhost"],
            browserBlockedDomains: ["example.com"]
        )

        let settings = WorkspaceSettingsSurface(config: config, hasStoredAPIKey: true)

        XCTAssertEqual(settings.computerUseApprovedBundleIdentifiers, [
            "com.apple.Terminal",
            "com.google.Chrome"
        ])
        XCTAssertEqual(settings.computerUseApprovedAppNames, ["Terminal"])
        XCTAssertEqual(settings.computerUseApprovalStatusLabel, "3 approved")
        XCTAssertEqual(
            settings.computerUseApprovalSummary,
            "Computer Use is restricted to 2 bundle IDs and 1 app name."
        )
        XCTAssertEqual(
            settings.computerUseOnboardingSteps.last,
            "Foreground app approvals are active; Computer Use will stop before controlling unapproved apps."
        )
        XCTAssertEqual(settings.browserAllowedDomains, ["trustedrouter.com", "localhost"])
        XCTAssertEqual(settings.browserBlockedDomains, ["example.com"])
        XCTAssertEqual(settings.browserDomainPolicyStatusLabel, "Allowlist + blocklist")
        XCTAssertEqual(settings.browserDomainPolicySummary, "Allowed: trustedrouter.com, localhost. Blocked: example.com")
    }

    func testSettingsSurfaceShowsNotificationSummary() {
        let settings = WorkspaceSettingsSurface(
            config: AppConfig(
                notificationPreferences: QuillCodeNotificationPreferences(
                    agentRunNotificationsEnabled: false,
                    automationNotificationsEnabled: true
                )
            ),
            hasStoredAPIKey: true
        )

        XCTAssertEqual(settings.notificationStatusLabel, "Automations")
        XCTAssertEqual(settings.notificationSummary, "Automation runs post completion alerts.")
    }

    func testSettingsSurfaceShowsRunSpendLimitSummary() {
        let settings = WorkspaceSettingsSurface(
            config: AppConfig(
                runSpendFuseUSD: nil,
                runSpendPeriodLimits: RunSpendPeriodLimits(dailyUSD: 5, weeklyUSD: 25, monthlyUSD: 100)
            ),
            hasStoredAPIKey: true
        )

        XCTAssertNil(settings.runSpendFuseUSD)
        XCTAssertEqual(settings.runSpendPeriodLimits.dailyUSD, 5)
        XCTAssertEqual(settings.runSpendPeriodLimits.weeklyUSD, 25)
        XCTAssertEqual(settings.runSpendPeriodLimits.monthlyUSD, 100)
        XCTAssertEqual(settings.runSpendLimitStatusLabel, "Caps")
        XCTAssertEqual(
            settings.runSpendLimitSummary,
            "Local spend controls show local day, week, and month cap rows in the top bar. " +
                "These do not replace TrustedRouter account limits."
        )
    }

    func testSettingsSurfaceDecodesOlderComputerUsePayload() throws {
        let data = """
        {
          "apiBaseURL": "https://api.trustedrouter.com/v1",
          "authMode": "oauth",
          "developerOverrideEnabled": false,
          "hasStoredAPIKey": false,
          "signInURL": "http://localhost:3000/callback",
          "apiKeyStatusLabel": "Not signed in",
          "loginStatusLabel": "TrustedRouter login required",
          "computerUseStatus": {
            "available": false,
            "screenRecordingGranted": true,
            "accessibilityGranted": false,
            "message": "Needs Accessibility"
          },
          "computerUseSetupCommand": {
            "id": "computer-use-setup",
            "title": "Computer Use setup",
            "isEnabled": true
          },
          "computerUseScreenRecordingCommand": {
            "id": "computer-use-open-screen-recording",
            "title": "Open Screen Recording settings",
            "isEnabled": false
          },
          "computerUseAccessibilityCommand": {
            "id": "computer-use-open-accessibility",
            "title": "Open Accessibility settings",
            "isEnabled": true
          },
          "computerUseRefreshCommand": {
            "id": "computer-use-refresh",
            "title": "Refresh Computer Use status",
            "isEnabled": true
          },
          "computerUseApprovedBundleIdentifiers": [
            " com.apple.Terminal ",
            "com.apple.Terminal"
          ],
          "computerUseApprovedAppNames": [
            "Terminal",
            "terminal"
          ]
        }
        """.data(using: .utf8)!

        let settings = try JSONDecoder().decode(WorkspaceSettingsSurface.self, from: data)

        XCTAssertNil(settings.modelProviderHealthLabel)
        XCTAssertNil(settings.modelProviderHealthDetail)
        XCTAssertNil(settings.trustedRouterAccountBalance)
        XCTAssertFalse(settings.trustedRouterCreditsRefreshCommand.isEnabled)
        XCTAssertNil(settings.reviewModel)
        XCTAssertEqual(settings.reviewDelivery, .current)
        XCTAssertEqual(settings.computerUseStatusLabel, "Accessibility needed")
        XCTAssertEqual(
            settings.computerUseNextAction,
            "Open Accessibility, enable QuillCode, then refresh status."
        )
        XCTAssertEqual(settings.computerUseRequirements.map(\.title), ["Screen Recording", "Accessibility"])
        XCTAssertEqual(settings.computerUseRequirements.map(\.statusLabel), ["Granted", "Required"])
        XCTAssertEqual(settings.computerUseRequirements.map(\.command.isEnabled), [false, true])
        XCTAssertTrue(settings.computerUseOnboardingSteps.contains(
            "Enable Accessibility so QuillCode can click, type, scroll, move the cursor, and send shortcuts."
        ))
        XCTAssertNil(settings.computerUseForegroundApplication)
        XCTAssertEqual(settings.computerUseApprovedBundleIdentifiers, ["com.apple.Terminal"])
        XCTAssertEqual(settings.computerUseApprovedAppNames, ["Terminal"])
        XCTAssertEqual(settings.computerUseApprovalStatusLabel, "2 approved")
        XCTAssertEqual(settings.browserAllowedDomains, [])
        XCTAssertEqual(settings.browserBlockedDomains, [])
        XCTAssertEqual(settings.browserDomainPolicyStatusLabel, "Unrestricted")
        XCTAssertEqual(settings.runSpendFuseUSD, 1.0)
        XCTAssertFalse(settings.runSpendPeriodLimits.hasAnyLimit)
        XCTAssertEqual(settings.runSpendLimitStatusLabel, "Fuse")
    }

    func testSettingsSurfaceCarriesDetectedForegroundApplication() {
        let application = ComputerUseApplication(
            name: "Terminal",
            bundleIdentifier: "com.apple.Terminal"
        )

        let settings = WorkspaceSettingsSurface(
            config: AppConfig(),
            hasStoredAPIKey: true,
            computerUseRuntime: ComputerUseSettingsRuntime(foregroundApplication: application)
        )

        XCTAssertEqual(settings.computerUseForegroundApplication, application)
    }

    func testSettingsSurfaceUsesUnavailableComputerUseReasonWithoutPermissionRows() {
        let status = ComputerUseStatus.unavailable(
            "Linux Computer Use detected Wayland but needs helper tools: ydotool, wtype."
        )
        let settings = WorkspaceSettingsSurface(
            config: AppConfig(),
            hasStoredAPIKey: false,
            computerUseRuntime: ComputerUseSettingsRuntime(status: status)
        )

        XCTAssertEqual(settings.computerUseStatusLabel, "Unavailable")
        XCTAssertEqual(
            settings.computerUseSetupSummary,
            "Linux Computer Use detected Wayland but needs helper tools: ydotool, wtype."
        )
        XCTAssertEqual(
            settings.computerUseNextAction,
            "Install or enable the required desktop backend, then refresh status."
        )
        XCTAssertEqual(settings.computerUseOnboardingSteps, [
            "Linux Computer Use detected Wayland but needs helper tools: ydotool, wtype.",
            "After installing the missing backend or helper tools, refresh status before asking QuillCode to use the screen."
        ])
        XCTAssertTrue(settings.computerUseRequirements.isEmpty)
        XCTAssertTrue(settings.computerUseSetupCommand.isEnabled)
    }

    func testRuntimeIssueDecodesOlderPayloadWithoutDiagnostics() throws {
        let data = """
        {
          "severity": "warning",
          "title": "Old issue",
          "message": "Older renderer payload",
          "actionLabel": "Retry"
        }
        """.data(using: .utf8)!

        let issue = try JSONDecoder().decode(RuntimeIssueSurface.self, from: data)

        XCTAssertEqual(issue.title, "Old issue")
        XCTAssertEqual(issue.actionLabel, "Retry")
        XCTAssertTrue(issue.diagnostics.isEmpty)
    }
}
