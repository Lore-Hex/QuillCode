import XCTest

final class ParityPlaywrightSettingsRuntimeGateTests: QuillCodeParityTestCase {
    func testPlaywrightSettingsAndRuntimeFlowsStayInFocusedSpec() throws {
        let testRoot = Self.packageRoot().appendingPathComponent("E2E/playwright/tests")
        let settingsSpecText = try String(
            contentsOf: testRoot.appendingPathComponent("settings.spec.ts"),
            encoding: .utf8
        )
        let coreSpecText = try String(
            contentsOf: testRoot.appendingPathComponent("core.spec.ts"),
            encoding: .utf8
        )

        for expected in [
            "harnessURL()",
            "openSettings",
            "computer-use-settings",
            "runtime-diagnostics",
            "TrustedRouter rate limit reached",
            "TrustedRouter provider unavailable"
        ] {
            Self.assertSource(settingsSpecText, contains: expected)
        }
        for flowName in [
            "shows actionable Computer Use setup in settings",
            "shows actionable TrustedRouter runtime issue",
            "retries the last user turn from a runtime issue",
            "shows runtime diagnostics in settings",
            "opens model picker from malformed model issue",
            "surfaces rate limits with model-switch recovery and diagnostics",
            "surfaces provider outages with model-switch recovery and diagnostics"
        ] {
            Self.assertSource(settingsSpecText, contains: flowName)
            Self.assertSource(coreSpecText, excludes: flowName)
        }
    }
}
