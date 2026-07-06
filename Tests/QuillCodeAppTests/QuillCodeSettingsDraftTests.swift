import XCTest
import QuillCodeCore
import QuillComputerUseKit
@testable import QuillCodeApp

final class QuillCodeSettingsDraftTests: XCTestCase {
    func testInitializesFromSettingsSurface() {
        let config = AppConfig(
            apiBaseURL: "https://api.example.test/v1",
            authMode: .developerOverride,
            developerOverrideEnabled: true
        )
        let surface = WorkspaceSettingsSurface(config: config, hasStoredAPIKey: true)

        let draft = QuillCodeSettingsDraft(settings: surface)

        XCTAssertEqual(draft.apiBaseURL, "https://api.example.test/v1")
        XCTAssertEqual(draft.authMode, .developerOverride)
        XCTAssertTrue(draft.developerOverrideEnabled)
        XCTAssertEqual(draft.replacementAPIKey, "")
        XCTAssertFalse(draft.shouldClearAPIKey)
        XCTAssertEqual(draft.computerUseApprovedBundleIdentifiersText, "")
        XCTAssertEqual(draft.computerUseApprovedAppNamesText, "")
        XCTAssertEqual(draft.browserAllowedDomainsText, "")
        XCTAssertEqual(draft.browserBlockedDomainsText, "")
        XCTAssertTrue(draft.agentRunNotificationsEnabled)
        XCTAssertTrue(draft.agentRunNotificationsOnlyWhenInactive)
        XCTAssertTrue(draft.automationNotificationsEnabled)
        XCTAssertEqual(draft.runSpendFuseUSDText, "1.00")
        XCTAssertEqual(draft.runSpendDailyLimitUSDText, "")
        XCTAssertEqual(draft.runSpendWeeklyLimitUSDText, "")
        XCTAssertEqual(draft.runSpendMonthlyLimitUSDText, "")
    }

    func testUpdateTrimsBaseURLAndReplacementKey() {
        var draft = QuillCodeSettingsDraft()
        draft.apiBaseURL = "  https://api.trustedrouter.test/v1  "
        draft.authMode = .developerOverride
        draft.developerOverrideEnabled = true
        draft.replacementAPIKey = "  sk-tr-v1-test  "

        let update = draft.update

        XCTAssertTrue(draft.canSave)
        XCTAssertEqual(update.apiBaseURL, "https://api.trustedrouter.test/v1")
        XCTAssertEqual(update.authMode, .developerOverride)
        XCTAssertTrue(update.developerOverrideEnabled)
        XCTAssertEqual(update.replacementAPIKey, "sk-tr-v1-test")
        XCTAssertFalse(update.shouldClearAPIKey)
        XCTAssertEqual(update.notificationPreferences, QuillCodeNotificationPreferences())
        XCTAssertNil(update.runSpendFuseUSD)
        XCTAssertFalse(update.runSpendPeriodLimits.hasAnyLimit)
    }

    func testSpendLimitsInitializeFromSurfaceAndUpdate() {
        let surface = WorkspaceSettingsSurface(
            config: AppConfig(
                runSpendFuseUSD: 2.5,
                runSpendPeriodLimits: RunSpendPeriodLimits(dailyUSD: 5, weeklyUSD: 12.5, monthlyUSD: 30)
            ),
            hasStoredAPIKey: false
        )

        var draft = QuillCodeSettingsDraft(settings: surface)
        draft.runSpendDailyLimitUSDText = " $6.75 "
        draft.runSpendWeeklyLimitUSDText = "0"
        draft.runSpendMonthlyLimitUSDText = "not a number"

        XCTAssertEqual(draft.runSpendFuseUSDText, "2.50")
        XCTAssertEqual(draft.runSpendWeeklyLimitUSDText, "0")
        XCTAssertEqual(draft.update.runSpendFuseUSD, 2.5)
        XCTAssertEqual(draft.update.runSpendPeriodLimits.dailyUSD, 6.75)
        XCTAssertNil(draft.update.runSpendPeriodLimits.weeklyUSD)
        XCTAssertNil(draft.update.runSpendPeriodLimits.monthlyUSD)
    }

    func testNotificationPreferencesInitializeFromSettingsSurfaceAndUpdate() {
        let preferences = QuillCodeNotificationPreferences(
            agentRunNotificationsEnabled: false,
            agentRunNotificationsOnlyWhenInactive: false,
            automationNotificationsEnabled: true
        )
        let surface = WorkspaceSettingsSurface(
            config: AppConfig(notificationPreferences: preferences),
            hasStoredAPIKey: false
        )

        var draft = QuillCodeSettingsDraft(settings: surface)
        draft.apiBaseURL = "https://api.trustedrouter.test/v1"
        draft.automationNotificationsEnabled = false

        XCTAssertFalse(draft.agentRunNotificationsEnabled)
        XCTAssertFalse(draft.agentRunNotificationsOnlyWhenInactive)
        XCTAssertFalse(draft.automationNotificationsEnabled)
        XCTAssertEqual(
            draft.update.notificationPreferences,
            QuillCodeNotificationPreferences(
                agentRunNotificationsEnabled: false,
                agentRunNotificationsOnlyWhenInactive: false,
                automationNotificationsEnabled: false
            )
        )
    }

    func testBlankReplacementKeyBecomesNilAndClearFlagIsPreserved() {
        var draft = QuillCodeSettingsDraft()
        draft.apiBaseURL = "https://api.trustedrouter.test/v1"
        draft.replacementAPIKey = "   "
        draft.shouldClearAPIKey = true

        let update = draft.update

        XCTAssertNil(update.replacementAPIKey)
        XCTAssertTrue(update.shouldClearAPIKey)
    }

    func testBlankBaseURLCannotSave() {
        var draft = QuillCodeSettingsDraft()
        draft.apiBaseURL = " \n\t "

        XCTAssertFalse(draft.canSave)
        XCTAssertEqual(draft.update.apiBaseURL, "")
    }

    func testComputerUseApprovalsInitializeFromSettingsSurface() {
        let config = AppConfig(
            computerUseApprovedBundleIdentifiers: ["com.apple.Terminal", "com.google.Chrome"],
            computerUseApprovedAppNames: ["Terminal", "Google Chrome"],
            browserAllowedDomains: ["trustedrouter.com", "localhost"],
            browserBlockedDomains: ["example.com"]
        )
        let surface = WorkspaceSettingsSurface(config: config, hasStoredAPIKey: false)

        let draft = QuillCodeSettingsDraft(settings: surface)

        XCTAssertEqual(
            draft.computerUseApprovedBundleIdentifiersText,
            "com.apple.Terminal\ncom.google.Chrome"
        )
        XCTAssertEqual(draft.computerUseApprovedAppNamesText, "Terminal\nGoogle Chrome")
        XCTAssertEqual(draft.browserAllowedDomainsText, "trustedrouter.com\nlocalhost")
        XCTAssertEqual(draft.browserBlockedDomainsText, "example.com")
    }

    func testComputerUseApprovalUpdateAcceptsCommaAndNewlineInput() {
        var draft = QuillCodeSettingsDraft()
        draft.apiBaseURL = "https://api.trustedrouter.test/v1"
        draft.computerUseApprovedBundleIdentifiersText = " com.apple.Terminal, com.apple.Terminal\ncom.google.Chrome "
        draft.computerUseApprovedAppNamesText = " Terminal,\nterminal\nGoogle Chrome "

        let update = draft.update

        XCTAssertEqual(update.computerUseApprovedBundleIdentifiers, [
            "com.apple.Terminal",
            "com.google.Chrome"
        ])
        XCTAssertEqual(update.computerUseApprovedAppNames, ["Terminal", "Google Chrome"])
    }

    func testBrowserDomainPolicyUpdateAcceptsCommaAndNewlineInput() {
        var draft = QuillCodeSettingsDraft()
        draft.apiBaseURL = "https://api.trustedrouter.test/v1"
        draft.browserAllowedDomainsText = " HTTPS://TrustedRouter.com/app, trustedrouter.com\n*.example.com "
        draft.browserBlockedDomainsText = " blocked.example.com,\nhttps://blocked.example.com/path "

        let update = draft.update

        XCTAssertEqual(update.browserAllowedDomains, ["trustedrouter.com", "example.com"])
        XCTAssertEqual(update.browserBlockedDomains, ["blocked.example.com"])
    }

    func testClearsComputerUseApprovals() {
        var draft = QuillCodeSettingsDraft()
        draft.computerUseApprovedBundleIdentifiersText = "com.apple.Terminal"
        draft.computerUseApprovedAppNamesText = "Terminal"

        draft.clearComputerUseApprovals()

        XCTAssertEqual(draft.computerUseApprovedBundleIdentifiersText, "")
        XCTAssertEqual(draft.computerUseApprovedAppNamesText, "")
        XCTAssertEqual(draft.update.computerUseApprovedBundleIdentifiers, [])
        XCTAssertEqual(draft.update.computerUseApprovedAppNames, [])
    }

    func testClearsBrowserDomainPolicy() {
        var draft = QuillCodeSettingsDraft()
        draft.browserAllowedDomainsText = "trustedrouter.com"
        draft.browserBlockedDomainsText = "example.com"

        draft.clearBrowserDomainPolicy()

        XCTAssertEqual(draft.browserAllowedDomainsText, "")
        XCTAssertEqual(draft.browserBlockedDomainsText, "")
        XCTAssertEqual(draft.update.browserAllowedDomains, [])
        XCTAssertEqual(draft.update.browserBlockedDomains, [])
    }

    func testAddsDetectedComputerUseAppByBundleIdentifier() {
        var draft = QuillCodeSettingsDraft()
        let application = ComputerUseApplication(
            name: "Terminal",
            bundleIdentifier: "com.apple.Terminal"
        )

        draft.addComputerUseApproval(for: application)
        draft.addComputerUseApproval(for: application)

        XCTAssertTrue(draft.hasComputerUseApproval(for: application))
        XCTAssertEqual(draft.computerUseApprovedBundleIdentifiersText, "com.apple.Terminal")
        XCTAssertEqual(draft.computerUseApprovedAppNamesText, "")
        XCTAssertEqual(draft.update.computerUseApprovedBundleIdentifiers, ["com.apple.Terminal"])
        XCTAssertEqual(draft.update.computerUseApprovedAppNames, [])
    }

    func testAddsDetectedComputerUseAppByNameWhenBundleIdentifierIsMissing() {
        var draft = QuillCodeSettingsDraft()
        let application = ComputerUseApplication(name: "Linux Terminal")

        draft.addComputerUseApproval(for: application)

        XCTAssertTrue(draft.hasComputerUseApproval(for: application))
        XCTAssertEqual(draft.computerUseApprovedBundleIdentifiersText, "")
        XCTAssertEqual(draft.computerUseApprovedAppNamesText, "Linux Terminal")
        XCTAssertEqual(draft.update.computerUseApprovedAppNames, ["Linux Terminal"])
    }
}
