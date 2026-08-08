import XCTest

final class ParityNativeWorkspaceProgressiveDisclosureGateTests: QuillCodeParityTestCase {
    func testTranscriptActionsAppearOnIntentWithoutLosingAlternateAccess() throws {
        let messageText = try Self.appSourceText(named: "QuillCodeTranscriptMessageView.swift")

        Self.assertSource(messageText, containsAll: [
            "if showsActions",
            ".onHover",
            ".focusable()",
            "focusedAction",
            "isVoiceOverEnabled",
            ".contextMenu",
            "messageContextMenu"
        ])
    }
}
