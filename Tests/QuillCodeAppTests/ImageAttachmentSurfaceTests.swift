import XCTest
import QuillCodeCore
@testable import QuillCodeApp

@MainActor
final class ImageAttachmentSurfaceTests: XCTestCase {
    func testWorkspaceSurfaceExposesComposerAndTranscriptImages() throws {
        let attachment = try makeAttachment()
        let thread = ChatThread(
            messages: [ChatMessage(role: .user, content: "Look", attachments: [attachment])],
            composerAttachments: [attachment]
        )
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(threads: [thread], selectedThreadID: thread.id),
            composer: ComposerState(attachments: [attachment])
        )

        let surface = model.surface()

        XCTAssertEqual(surface.composer.attachments.map(\.displayName), ["screen.png"])
        XCTAssertTrue(surface.composer.canSend)
        XCTAssertEqual(surface.transcript.messages.first?.attachments.map(\.displayName), ["screen.png"])
    }

    func testHTMLRendererIncludesComposerAndSentImageTargets() throws {
        let attachment = try makeAttachment()
        let thread = ChatThread(
            messages: [ChatMessage(role: .user, content: "", attachments: [attachment])],
            composerAttachments: [attachment]
        )
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(threads: [thread], selectedThreadID: thread.id),
            composer: ComposerState(attachments: [attachment])
        )
        let surface = model.surface()

        let composerHTML = WorkspaceHTMLTranscriptRenderer.renderComposer(
            surface.composer,
            topBar: surface.topBar
        )
        let transcriptHTML = WorkspaceHTMLTranscriptRenderer.render(
            transcript: surface.transcript,
            contextBanner: nil,
            review: surface.review,
            runtimeIssue: nil,
            retryLastTurnCommand: nil
        )

        XCTAssertTrue(composerHTML.contains("data-testid=\"attach-images-button\""), composerHTML)
        XCTAssertTrue(composerHTML.contains("data-testid=\"composer-attachment\""), composerHTML)
        XCTAssertTrue(transcriptHTML.contains("data-testid=\"message-attachment\""), transcriptHTML)
        XCTAssertTrue(transcriptHTML.contains("screen.png"), transcriptHTML)
    }

    private func makeAttachment() throws -> ChatAttachment {
        try XCTUnwrap(ChatAttachment(
            displayName: "screen.png",
            format: .png,
            localURL: URL(fileURLWithPath: "/tmp/screen.png"),
            byteCount: 8
        ))
    }
}
