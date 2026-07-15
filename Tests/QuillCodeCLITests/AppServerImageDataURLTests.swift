import Foundation
@testable import QuillCodeCLI
import QuillCodeCore
import XCTest

final class AppServerImageDataURLTests: XCTestCase {
    func testDecodesSupportedBase64ImageAndDerivesManagedName() throws {
        let value = "DATA:image/png;BASE64,\(Self.onePixelPNG.base64EncodedString())"

        let image = try AppServerImageDataURL(value)

        XCTAssertEqual(image.data, Self.onePixelPNG)
        XCTAssertEqual(image.format, .png)
        XCTAssertEqual(image.displayName, "image.png")
    }

    func testRejectsRemoteAndMalformedInputsWithoutEchoingTheirValues() {
        let cases: [(String, AppServerImageDataURLError)] = [
            ("https://example.com/private.png?token=secret", .unsupportedURL),
            ("data:image/png;base64,%%%", .invalidEncoding),
            ("data:text/plain;base64,SGVsbG8=", .unsupportedURL),
            ("data:image/png,AAAA", .unsupportedURL)
        ]

        for (value, expected) in cases {
            XCTAssertThrowsError(try AppServerImageDataURL(value)) { error in
                XCTAssertEqual(error as? AppServerImageDataURLError, expected)
                XCTAssertFalse(error.localizedDescription.contains(value))
                XCTAssertFalse(error.localizedDescription.contains("secret"))
            }
        }
    }

    func testRejectsDeclaredMediaTypeThatDoesNotMatchMagicBytes() {
        let value = "data:image/jpeg;base64,\(Self.onePixelPNG.base64EncodedString())"

        XCTAssertThrowsError(try AppServerImageDataURL(value)) { error in
            XCTAssertEqual(error as? AppServerImageDataURLError, .declaredTypeMismatch)
        }
    }

    func testRejectsUnsupportedImageBytesAndOversizedPayloadBeforeDecode() {
        XCTAssertThrowsError(try AppServerImageDataURL("data:image/png;base64,SGVsbG8=")) { error in
            XCTAssertEqual(error as? AppServerImageDataURLError, .unsupportedImage)
        }

        let oversized = "data:image/png;base64," + String(
            repeating: "A",
            count: AppServerImageDataURL.maximumEncodedBytes + 1
        )
        XCTAssertThrowsError(try AppServerImageDataURL(oversized)) { error in
            XCTAssertEqual(error as? AppServerImageDataURLError, .imageTooLarge)
        }
    }

    func testAppServerLineLimitFitsFourMaximumSizeImageInputs() {
        let encodedImages = AppServerImageDataURL.maximumEncodedBytes
            * ChatAttachment.maximumCountPerTurn

        XCTAssertGreaterThan(AppServerSession.maximumMessageBytes, encodedImages)
    }

    private static let onePixelPNG = Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
    )!
}
