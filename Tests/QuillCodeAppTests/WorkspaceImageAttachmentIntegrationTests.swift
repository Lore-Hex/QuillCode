import XCTest
import QuillCodeCore
import QuillCodePersistence
@testable import QuillCodeApp

@MainActor
final class WorkspaceImageAttachmentIntegrationTests: XCTestCase {
    func testImportPersistsAcrossThreadSwitchAndExplicitRemoveDeletesManagedFile() async throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("screen.png")
        try Self.onePixelPNG.write(to: source)
        let threadStore = JSONThreadStore(directory: root.appendingPathComponent("threads"))
        let imageStore = ImageAttachmentStore(directory: root.appendingPathComponent("attachments"))
        let model = QuillCodeWorkspaceModel(
            threadStore: threadStore,
            imageAttachmentStore: imageStore
        )
        let firstThreadID = model.newChat()

        await model.addComposerImages(from: [source])

        let managedURL = try XCTUnwrap(model.composer.attachments.first?.localURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: managedURL.path))
        XCTAssertEqual(try threadStore.load(firstThreadID).composerAttachments.count, 1)

        _ = model.newChat()
        XCTAssertTrue(model.composer.attachments.isEmpty)
        model.selectThread(firstThreadID)
        XCTAssertEqual(model.composer.attachments.map(\.displayName), ["screen.png"])

        let attachmentID = try XCTUnwrap(model.composer.attachments.first?.id)
        model.removeComposerImage(attachmentID)
        XCTAssertFalse(FileManager.default.fileExists(atPath: managedURL.path))
        XCTAssertTrue(try threadStore.load(firstThreadID).composerAttachments.isEmpty)
    }

    func testImageOnlyComposerSubmissionBecomesUserTurn() async throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("screen.png")
        try Self.onePixelPNG.write(to: source)
        let model = QuillCodeWorkspaceModel(
            imageAttachmentStore: ImageAttachmentStore(directory: root.appendingPathComponent("attachments"))
        )
        await model.addComposerImages(from: [source])

        await model.submitComposer(workspaceRoot: root)

        let userMessage = try XCTUnwrap(model.selectedThread?.messages.first { $0.role == .user })
        XCTAssertEqual(userMessage.content, "")
        XCTAssertEqual(userMessage.attachments.map(\.displayName), ["screen.png"])
        XCTAssertTrue(model.composer.attachments.isEmpty)
    }

    private static let onePixelPNG = Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
    )!
}
