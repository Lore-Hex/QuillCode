import XCTest
@testable import QuillCodeApp

/// The first-run connect gate is the fix for the "dead first chat": a keyless user must be shown the
/// TrustedRouter sign-in up front, not dropped into a composer that silently fails. These lock the
/// show/hide decision.
final class TranscriptConnectPromptTests: XCTestCase {
    func testShownWhenNoCredentialStored() {
        let prompt = TranscriptConnectPrompt.make(hasStoredAPIKey: false)
        XCTAssertNotNil(prompt, "a keyless user must see the connect gate")
        XCTAssertEqual(prompt?.accountURL, TranscriptConnectPrompt.defaultAccountURL)
    }

    func testHiddenWhenCredentialStored() {
        let prompt = TranscriptConnectPrompt.make(hasStoredAPIKey: true)
        XCTAssertNil(prompt, "a connected user must never see onboarding")
    }

    func testCopyIsSentenceCaseAndNamesTheAction() {
        // Guardrails on the surfaced copy so a refactor can't silently blank the hero or the CTA.
        XCTAssertFalse(TranscriptConnectPrompt.title.isEmpty)
        XCTAssertTrue(TranscriptConnectPrompt.signInButtonTitle.contains("TrustedRouter"))
        XCTAssertFalse(TranscriptConnectPrompt.subtitle.localizedCaseInsensitiveContains("coding"))
        XCTAssertFalse(TranscriptConnectPrompt.browserSignInCaption.contains("localhost"))
        XCTAssertEqual(TranscriptConnectPrompt.steps, ["Sign in", "Choose a model", "Start a task"])
    }
}
