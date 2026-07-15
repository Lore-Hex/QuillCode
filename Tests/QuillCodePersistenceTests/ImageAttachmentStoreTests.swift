import XCTest
import QuillCodeCore
@testable import QuillCodePersistence

final class ImageAttachmentStoreTests: PersistenceTestCase {
    func testImportsImageIntoPrivateManagedStorageAndRoundTripsData() throws {
        let root = try makeTempDirectory()
        let source = root.appendingPathComponent("source.png")
        try Self.onePixelPNG.write(to: source)
        let store = ImageAttachmentStore(directory: root.appendingPathComponent("managed"))

        let attachment = try store.importImage(from: source, threadID: UUID())

        XCTAssertEqual(attachment.displayName, "source.png")
        XCTAssertEqual(attachment.format, .png)
        XCTAssertTrue(store.contains(attachment.localURL))
        XCTAssertEqual(try store.data(for: attachment), Self.onePixelPNG)
        XCTAssertTrue(try store.dataURL(for: attachment).hasPrefix("data:image/png;base64,"))
        let permissions = try FileManager.default.attributesOfItem(atPath: attachment.localURL.path)[.posixPermissions]
        XCTAssertEqual((permissions as? NSNumber)?.intValue, 0o600)
    }

    func testImportsValidatedBytesAndPreservesImageDetail() throws {
        let root = try makeTempDirectory()
        let store = ImageAttachmentStore(directory: root.appendingPathComponent("managed"))

        let attachment = try store.importImage(
            data: Self.onePixelPNG,
            displayName: "remote.png",
            threadID: UUID(),
            detail: .original
        )

        XCTAssertEqual(attachment.displayName, "remote.png")
        XCTAssertEqual(attachment.detail, .original)
        XCTAssertEqual(try store.data(for: attachment), Self.onePixelPNG)
    }

    func testRejectsUnsupportedAndUnmanagedFiles() throws {
        let root = try makeTempDirectory()
        let invalid = root.appendingPathComponent("notes.txt")
        try Data("hello".utf8).write(to: invalid)
        let store = ImageAttachmentStore(directory: root.appendingPathComponent("managed"))

        XCTAssertThrowsError(try store.importImage(from: invalid, threadID: UUID())) { error in
            XCTAssertEqual(error as? ImageAttachmentStoreError, .unsupportedImage)
        }
        let unmanaged = try XCTUnwrap(ChatAttachment(
            displayName: "source.png",
            format: .png,
            localURL: invalid,
            byteCount: 5
        ))
        XCTAssertThrowsError(try store.data(for: unmanaged)) { error in
            XCTAssertEqual(error as? ImageAttachmentStoreError, .unmanagedAttachment)
        }
    }

    func testRejectsManagedAttachmentReplacedByOutsideSymlink() throws {
        let root = try makeTempDirectory()
        let source = root.appendingPathComponent("source.png")
        let outside = root.appendingPathComponent("outside.png")
        try Self.onePixelPNG.write(to: source)
        try Self.onePixelPNG.write(to: outside)
        let store = ImageAttachmentStore(directory: root.appendingPathComponent("managed"))
        let attachment = try store.importImage(from: source, threadID: UUID())

        try FileManager.default.removeItem(at: attachment.localURL)
        try FileManager.default.createSymbolicLink(at: attachment.localURL, withDestinationURL: outside)

        XCTAssertThrowsError(try store.data(for: attachment)) { error in
            XCTAssertEqual(error as? ImageAttachmentStoreError, .unmanagedAttachment)
        }
    }

    func testAdoptsManagedImageWithoutCopyingIt() throws {
        let root = try makeTempDirectory()
        let managed = root.appendingPathComponent("managed")
        let screenshot = managed
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("computer-use", isDirectory: true)
            .appendingPathComponent("screenshot.png")
        try FileManager.default.createDirectory(
            at: screenshot.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Self.onePixelPNG.write(to: screenshot)
        let store = ImageAttachmentStore(directory: managed)

        let attachment = try store.attachmentForManagedImage(
            at: screenshot,
            displayName: "Computer Use screenshot.png"
        )

        XCTAssertEqual(
            attachment.localURL.resolvingSymlinksInPath(),
            screenshot.resolvingSymlinksInPath()
        )
        XCTAssertEqual(attachment.displayName, "Computer Use screenshot.png")
        XCTAssertEqual(attachment.format, .png)
        XCTAssertEqual(try store.data(for: attachment), Self.onePixelPNG)
        let files = try FileManager.default.contentsOfDirectory(
            at: screenshot.deletingLastPathComponent(),
            includingPropertiesForKeys: nil
        )
        XCTAssertEqual(files.count, 1)
        XCTAssertEqual(
            files.first?.resolvingSymlinksInPath(),
            screenshot.resolvingSymlinksInPath()
        )
        let permissions = try FileManager.default.attributesOfItem(atPath: screenshot.path)[.posixPermissions]
        XCTAssertEqual((permissions as? NSNumber)?.intValue, 0o600)
    }

    func testRefusesToAdoptImageOutsideManagedStorage() throws {
        let root = try makeTempDirectory()
        let outside = root.appendingPathComponent("outside.png")
        try Self.onePixelPNG.write(to: outside)
        let store = ImageAttachmentStore(directory: root.appendingPathComponent("managed"))

        XCTAssertThrowsError(try store.attachmentForManagedImage(at: outside)) { error in
            XCTAssertEqual(error as? ImageAttachmentStoreError, .unmanagedAttachment)
        }
    }

    private static let onePixelPNG = Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
    )!
}
