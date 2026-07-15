import XCTest
@testable import QuillCodeCore

final class ChatAttachmentTests: XCTestCase {
    func testDetectsSupportedImageMagicBytes() {
        XCTAssertEqual(ChatImageFormat.detect(in: Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])), .png)
        XCTAssertEqual(ChatImageFormat.detect(in: Data([0xFF, 0xD8, 0xFF, 0x00])), .jpeg)
        XCTAssertEqual(ChatImageFormat.detect(in: Data("GIF89a".utf8)), .gif)
        XCTAssertEqual(ChatImageFormat.detect(in: Data("RIFF1234WEBP".utf8)), .webp)
        XCTAssertNil(ChatImageFormat.detect(in: Data("not an image".utf8)))
    }

    func testAttachmentRejectsInvalidMetadataAndNormalizesDisplayName() throws {
        let url = URL(fileURLWithPath: "/tmp/image.png")
        let attachment = try XCTUnwrap(ChatAttachment(
            displayName: "folder/screenshot.png\n",
            format: .png,
            localURL: url,
            byteCount: 8
        ))

        XCTAssertEqual(attachment.displayName, "screenshot.png")
        XCTAssertNil(ChatAttachment(displayName: "", format: .png, localURL: url, byteCount: 8))
        XCTAssertNil(ChatAttachment(displayName: "x", format: .png, localURL: url, byteCount: 0))
        XCTAssertNil(ChatAttachment(
            displayName: "x",
            format: .png,
            localURL: url,
            byteCount: ChatAttachment.maximumByteCount + 1
        ))
    }

    func testAttachmentDetailRoundTripsAndDefaultsForLegacyRecords() throws {
        let attachment = try XCTUnwrap(ChatAttachment(
            displayName: "image.png",
            format: .png,
            localURL: URL(fileURLWithPath: "/tmp/image.png"),
            byteCount: 8,
            detail: .high
        ))
        let encoder = JSONEncoder()
        let encoded = try encoder.encode(attachment)
        XCTAssertEqual(try JSONDecoder().decode(ChatAttachment.self, from: encoded).detail, .high)

        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        legacy.removeValue(forKey: "detail")
        let legacyData = try JSONSerialization.data(withJSONObject: legacy)
        XCTAssertEqual(try JSONDecoder().decode(ChatAttachment.self, from: legacyData).detail, .auto)
    }

    func testLegacyMessageAndThreadDecodeWithoutAttachmentFields() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let messageJSON = """
        {
          "id": "\(UUID().uuidString)",
          "role": "user",
          "content": "hello",
          "createdAt": "2020-01-01T00:00:00Z"
        }
        """
        let message = try decoder.decode(ChatMessage.self, from: Data(messageJSON.utf8))
        XCTAssertEqual(message.attachments, [])

        let threadJSON = """
        {
          "id": "\(UUID().uuidString)",
          "title": "Legacy",
          "instructions": [],
          "memories": [],
          "mode": "auto",
          "model": "trustedrouter/fast",
          "messages": [],
          "events": [],
          "isPinned": false,
          "isArchived": false,
          "createdAt": "2020-01-01T00:00:00Z",
          "updatedAt": "2020-01-01T00:00:00Z"
        }
        """
        let thread = try decoder.decode(ChatThread.self, from: Data(threadJSON.utf8))
        XCTAssertEqual(thread.composerAttachments, [])
    }
}
