@testable import QuillCodeCLI
import QuillCodeCore
import XCTest

final class MCPServerConfigOverlayTests: XCTestCase {
    func testResolvesCodexAliasesAndExplicitPolicyPrecedence() throws {
        let input = try MCPServerRunInput(arguments: [
            "prompt": .string("work"),
            "approval-policy": .string("on-request"),
            "config": .object([
                "model": .string("provider/model"),
                "max_tool_steps": .number(17),
                "api_base_url": .string("https://example.test/v1")
            ])
        ])
        let resolved = try MCPServerConfigOverlay.resolve(
            input: input,
            base: AppConfig(mode: .auto),
            serverModel: nil
        )
        XCTAssertEqual(resolved.model, "provider/model")
        XCTAssertEqual(resolved.appConfig.maxToolSteps, 17)
        XCTAssertEqual(resolved.appConfig.apiBaseURL, "https://example.test/v1")
        XCTAssertEqual(resolved.approvalsReviewer, "user")
        XCTAssertEqual(resolved.sandbox, .workspaceWrite)
    }

    func testResolvesAdditionalSafeInvocationLocalConfigAliases() throws {
        let input = try MCPServerRunInput(arguments: [
            "prompt": .string("work"),
            "config": .object([
                "review_model": .string("trustedrouter/socrates"),
                "review_delivery": .string("detached"),
                "auth_mode": .string("developer-override"),
                "computer_use_approved_app_names": .array([.string("Simulator")]),
                "computer_use_approved_bundle_identifiers": .array([
                    .string("com.apple.Terminal")
                ]),
                "notification_preferences": .object([
                    "agentRunNotificationsEnabled": .bool(false),
                    "agentRunNotificationsOnlyWhenInactive": .bool(false),
                    "automationNotificationsEnabled": .bool(true)
                ]),
                "run_spend_period_limits": .object([
                    "dailyUSD": .number(2.5),
                    "weeklyUSD": .number(10),
                    "monthlyUSD": .number(25)
                ])
            ])
        ])

        let resolved = try MCPServerConfigOverlay.resolve(
            input: input,
            base: AppConfig(),
            serverModel: nil
        )

        XCTAssertEqual(resolved.appConfig.reviewModel, "trustedrouter/socrates")
        XCTAssertEqual(resolved.appConfig.reviewDelivery, .detached)
        XCTAssertEqual(resolved.appConfig.authMode, .developerOverride)
        XCTAssertTrue(resolved.appConfig.developerOverrideEnabled)
        XCTAssertEqual(resolved.appConfig.computerUseApprovedAppNames, ["Simulator"])
        XCTAssertEqual(
            resolved.appConfig.computerUseApprovedBundleIdentifiers,
            ["com.apple.Terminal"]
        )
        XCTAssertFalse(resolved.appConfig.notificationPreferences.agentRunNotificationsEnabled)
        XCTAssertFalse(
            resolved.appConfig.notificationPreferences.agentRunNotificationsOnlyWhenInactive
        )
        XCTAssertTrue(resolved.appConfig.notificationPreferences.automationNotificationsEnabled)
        XCTAssertEqual(resolved.appConfig.runSpendPeriodLimits.dailyUSD, 2.5)
        XCTAssertEqual(resolved.appConfig.runSpendPeriodLimits.weeklyUSD, 10)
        XCTAssertEqual(resolved.appConfig.runSpendPeriodLimits.monthlyUSD, 25)
    }

    func testRejectsUnknownConfigAndNonTrustedRouterProvider() throws {
        let unknown = try MCPServerRunInput(arguments: [
            "prompt": .string("work"),
            "config": .object(["mystery": .bool(true)])
        ])
        XCTAssertThrowsError(try MCPServerConfigOverlay.resolve(
            input: unknown,
            base: AppConfig(),
            serverModel: nil
        ))

        let provider = try MCPServerRunInput(arguments: [
            "prompt": .string("work"),
            "config": .object(["model_provider": .string("other")])
        ])
        XCTAssertThrowsError(try MCPServerConfigOverlay.resolve(
            input: provider,
            base: AppConfig(),
            serverModel: nil
        ))
    }

    func testRejectsSecretAndAccountConfigOverrides() throws {
        for key in ["trustedRouterAccount", "developerOverrideEnabled"] {
            let input = try MCPServerRunInput(arguments: [
                "prompt": .string("work"),
                "config": .object([key: .object([:])])
            ])
            XCTAssertThrowsError(try MCPServerConfigOverlay.resolve(
                input: input,
                base: AppConfig(),
                serverModel: nil
            ), key)
        }
    }
}
