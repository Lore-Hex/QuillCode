import Foundation
import XCTest
@testable import QuillCodeCore

final class AppConfigCompatibilityTests: XCTestCase {
    func testAppConfigDecodesOlderPayloadWithoutFavorites() throws {
        let config = try JSONHelpers.decode(AppConfig.self, from: """
        {
          "defaultModel": "trustedrouter/fusion",
          "mode": "auto",
          "apiBaseURL": "https://api.trustedrouter.com/v1",
          "authMode": "oauth",
          "developerOverrideEnabled": false
        }
        """)

        XCTAssertEqual(config.defaultModel, TrustedRouterDefaults.prometheusModel)
        XCTAssertEqual(config.favoriteModels, [])
        XCTAssertEqual(config.browserAllowedDomains, [])
        XCTAssertEqual(config.browserBlockedDomains, [])
        XCTAssertEqual(config.notificationPreferences, QuillCodeNotificationPreferences())
        XCTAssertEqual(config.runSpendFuseUSD, 1.0)
        XCTAssertEqual(config.managedWorktrees, ManagedWorktreeSettings())
        XCTAssertEqual(config.keyboardShortcuts, KeyboardShortcutPreferences())
        XCTAssertEqual(config.maxToolSteps, AppConfig.defaultMaxToolSteps)
    }

    func testKeyboardShortcutPreferencesNormalizeAndKeepLatestOverride() throws {
        let preferences = KeyboardShortcutPreferences(overrides: [
            KeyboardShortcutOverride(
                commandID: " search ",
                key: " k ",
                modifiers: [.shift, .command, .command]
            ),
            KeyboardShortcutOverride(
                commandID: "search",
                key: "g",
                modifiers: [.command]
            ),
            KeyboardShortcutOverride(commandID: "", key: "x", modifiers: [.command])
        ])

        XCTAssertEqual(preferences.overrides, [
            KeyboardShortcutOverride(commandID: "search", key: "g", modifiers: [.command])
        ])

        let encoded = try JSONEncoder().encode(AppConfig(keyboardShortcuts: preferences))
        let decoded = try JSONDecoder().decode(AppConfig.self, from: encoded)
        XCTAssertEqual(decoded.keyboardShortcuts, preferences)
    }

    func testKeyboardShortcutPreferencesRejectUnsafeOrUnsupportedManualOverrides() {
        let preferences = KeyboardShortcutPreferences(overrides: [
            KeyboardShortcutOverride(commandID: "bare-letter", key: "x", modifiers: []),
            KeyboardShortcutOverride(commandID: "unsupported-name", key: "space", modifiers: [.command]),
            KeyboardShortcutOverride(commandID: "safe-letter", key: " K ", modifiers: [.option]),
            KeyboardShortcutOverride(commandID: "escape", key: "ESCAPE", modifiers: [])
        ])

        XCTAssertEqual(preferences.overrides, [
            KeyboardShortcutOverride(commandID: "escape", key: "escape", modifiers: []),
            KeyboardShortcutOverride(commandID: "safe-letter", key: "k", modifiers: [.option])
        ])
    }

    func testKeyboardShortcutPreferencesNormalizeRawConfigDuringDecoding() throws {
        let preferences = try JSONHelpers.decode(KeyboardShortcutPreferences.self, from: """
        {
          "overrides": [
            {"commandID":" bare ","key":" X ","modifiers":[]},
            {"commandID":"unsafe-name","key":"space","modifiers":["command"]},
            {"commandID":"search","key":" G ","modifiers":["shift","command","command"]},
            {"commandID":"search","key":" K ","modifiers":["option"]}
          ]
        }
        """)

        XCTAssertEqual(preferences.overrides, [
            KeyboardShortcutOverride(commandID: "search", key: "k", modifiers: [.option])
        ])
    }

    func testAppConfigDecodesAndNormalizesMaxToolSteps() throws {
        let config = try JSONHelpers.decode(AppConfig.self, from: """
        {
          "maxToolSteps": 32
        }
        """)

        XCTAssertEqual(config.maxToolSteps, 32)
        // Non-positive values normalize to the ≥1 floor rather than wedging the loop at zero steps.
        XCTAssertEqual(AppConfig(maxToolSteps: 0).maxToolSteps, 1)
        XCTAssertEqual(AppConfig(maxToolSteps: -5).maxToolSteps, 1)
    }

    func testAppConfigDecodesAndNormalizesRunSpendFuse() throws {
        let config = try JSONHelpers.decode(AppConfig.self, from: """
        {
          "runSpendFuseUSD": 0.25
        }
        """)

        XCTAssertEqual(config.runSpendFuseUSD, 0.25)
        XCTAssertNil(AppConfig(runSpendFuseUSD: 0).runSpendFuseUSD)
        XCTAssertNil(AppConfig(runSpendFuseUSD: -1).runSpendFuseUSD)
        XCTAssertNil(AppConfig(runSpendFuseUSD: .infinity).runSpendFuseUSD)
    }

    func testAppConfigNormalizesComputerUseApprovals() {
        let config = AppConfig(
            computerUseApprovedBundleIdentifiers: [
                " com.apple.Terminal ",
                "com.apple.terminal",
                ""
            ],
            computerUseApprovedAppNames: [
                "Terminal",
                " terminal ",
                "Google Chrome"
            ]
        )

        XCTAssertEqual(config.computerUseApprovedBundleIdentifiers, ["com.apple.Terminal"])
        XCTAssertEqual(config.computerUseApprovedAppNames, ["Terminal", "Google Chrome"])
    }

    func testAppConfigNormalizesBrowserDomainPolicy() {
        let config = AppConfig(
            browserAllowedDomains: [" https://TrustedRouter.com/app ", "*.Example.com"],
            browserBlockedDomains: ["blocked.example.com", "https://BLOCKED.example.com/path"]
        )

        XCTAssertEqual(config.browserAllowedDomains, ["trustedrouter.com", "example.com"])
        XCTAssertEqual(config.browserBlockedDomains, ["blocked.example.com"])
        XCTAssertEqual(config.browserDomainPolicy.statusLabel, "Allowlist + blocklist")
    }

    func testAppConfigCarriesNotificationPreferences() {
        let preferences = QuillCodeNotificationPreferences(
            agentRunNotificationsEnabled: false,
            agentRunNotificationsOnlyWhenInactive: false,
            automationNotificationsEnabled: true
        )

        let config = AppConfig(notificationPreferences: preferences)

        XCTAssertEqual(config.notificationPreferences, preferences)
    }

    func testProjectAndThreadDecodeOlderStateWithoutInstructions() throws {
        let projectID = UUID()
        let date = ISO8601DateFormatter().string(from: Date())
        let project = try JSONHelpers.decode(ProjectRef.self, from: """
        {
          "id": "\(projectID.uuidString)",
          "name": "QuillCode",
          "path": "/tmp/QuillCode",
          "lastOpenedAt": "\(date)"
        }
        """)
        XCTAssertEqual(project.instructions, [])
        XCTAssertEqual(project.instructionDiagnosticResolutions, [])
        XCTAssertEqual(project.dismissedInstructionDiagnosticIDs, [])
        XCTAssertEqual(project.resolvedInstructionDiagnosticIDs, [])
        XCTAssertEqual(project.localActions, [])
        XCTAssertEqual(project.memories, [])

        let threadID = UUID()
        let thread = try JSONHelpers.decode(ChatThread.self, from: """
        {
          "id": "\(threadID.uuidString)",
          "title": "Old thread",
          "projectID": "\(projectID.uuidString)",
          "mode": "auto",
          "model": "trustedrouter/fusion",
          "messages": [],
          "events": [],
          "isPinned": false,
          "isArchived": false,
          "createdAt": "\(date)",
          "updatedAt": "\(date)"
        }
        """)
        XCTAssertEqual(thread.model, TrustedRouterDefaults.prometheusModel)
        XCTAssertEqual(thread.instructions, [])
        XCTAssertEqual(thread.memories, [])
    }

    func testProjectConnectionParsesSSHAddresses() throws {
        let scpStyle = try XCTUnwrap(ProjectConnection.parseSSH("quill@feather.local:/srv/quill"))
        XCTAssertEqual(scpStyle, .ssh(path: "/srv/quill", host: "feather.local", user: "quill"))
        XCTAssertEqual(scpStyle.displayLabel, "ssh://quill@feather.local/srv/quill")

        let urlStyle = try XCTUnwrap(ProjectConnection.parseSSH("ssh://root@example.com:2222/opt/app"))
        XCTAssertEqual(urlStyle.path, "/opt/app")
        XCTAssertEqual(urlStyle.host, "example.com")
        XCTAssertEqual(urlStyle.user, "root")
        XCTAssertEqual(urlStyle.port, 2222)
        XCTAssertEqual(urlStyle.displayLabel, "ssh://root@example.com:2222/opt/app")

        XCTAssertNil(ProjectConnection.parseSSH("not a remote"))
        XCTAssertNil(ProjectConnection.parseSSH("host:relative/path"))
    }
}
