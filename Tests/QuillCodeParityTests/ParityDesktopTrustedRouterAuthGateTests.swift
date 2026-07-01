import XCTest

final class ParityDesktopTrustedRouterAuthGateTests: QuillCodeParityTestCase {
    func testDesktopTrustedRouterSignInUsesLoopbackOAuth() throws {
        let text = try Self.desktopSourceText()
        let controllerText = try Self.desktopSourceText(named: "QuillCodeDesktopController.swift")
        let signInText = try Self.desktopSourceText(named: "QuillCodeDesktopSignInCoordinator.swift")

        Self.assertSource(text, contains: "QuillCodeDesktopSignInCoordinator")
        Self.assertSource(text, contains: "TrustedRouterLoopbackCallbackServer")
        Self.assertSource(text, contains: "TrustedRouterDefaults.loopbackCallbackURL")
        Self.assertSource(text, contains: "createAuthorization")
        Self.assertSource(text, contains: "exchangeCode")
        Self.assertSource(text, contains: "saveTrustedRouterAPIKey")
        Self.assertSource(text, contains: "fetchModelCatalog")
        Self.assertSource(signInText, contains: "func completeSignInAndApply")
        Self.assertSource(signInText, contains: "model.applySettings")
        Self.assertSource(signInText, contains: "model.applyRuntime")
        Self.assertSource(signInText, contains: "model.setModelCatalog")
        Self.assertSource(signInText, contains: "QuillCodeRuntimeStatusLabel.signInFailed")
        Self.assertSource(controllerText, contains: "signInCoordinator.completeSignInAndApply")
        Self.assertSource(controllerText, excludes: "exchangeCode")
        Self.assertSource(controllerText, excludes: "TrustedRouterOAuthClient")
        Self.assertSource(controllerText, excludes: "TrustedRouterLoopbackCallbackServer")
        Self.assertSource(controllerText, excludes: "private func completeTrustedRouterSignIn")
        Self.assertSource(controllerText, excludes: "QuillCodeRuntimeStatusLabel.signInFailed")
        XCTAssertFalse(
            text.contains("NSWorkspace.shared.open(url)") && text.contains("TrustedRouterDefaults.signInURL"),
            "Desktop sign-in should not regress to opening the static sign-in documentation page."
        )
    }

}
