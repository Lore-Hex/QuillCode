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
        XCTAssertEqual(settings.modelCatalogStatusLabel, "Bundled catalog")
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
        XCTAssertEqual(settings.computerUseRequirements.map(\.title), ["Screen Recording", "Accessibility"])
        XCTAssertEqual(settings.computerUseRequirements.map(\.statusLabel), ["Required", "Required"])
        XCTAssertEqual(settings.computerUseRequirements.map(\.isGranted), [false, false])
        XCTAssertEqual(settings.computerUseRequirements.first?.command.id, "computer-use-open-screen-recording")
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
          }
        }
        """.data(using: .utf8)!

        let settings = try JSONDecoder().decode(WorkspaceSettingsSurface.self, from: data)

        XCTAssertEqual(settings.computerUseStatusLabel, "Accessibility needed")
        XCTAssertEqual(
            settings.computerUseNextAction,
            "Open Accessibility, enable QuillCode, then refresh status."
        )
        XCTAssertEqual(settings.computerUseRequirements.map(\.title), ["Screen Recording", "Accessibility"])
        XCTAssertEqual(settings.computerUseRequirements.map(\.statusLabel), ["Granted", "Required"])
        XCTAssertEqual(settings.computerUseRequirements.map(\.command.isEnabled), [false, true])
    }

    func testSettingsSurfaceUsesUnavailableComputerUseReasonWithoutPermissionRows() {
        let status = ComputerUseStatus.unavailable(
            "Linux Computer Use detected Wayland but needs helper tools: ydotool, wtype."
        )
        let settings = WorkspaceSettingsSurface(
            config: AppConfig(),
            hasStoredAPIKey: false,
            computerUseStatus: status
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
