#if canImport(AppKit) && canImport(CoreGraphics) && canImport(ImageIO)
import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import QuillCodeApp

final class QuillCodeImageThumbnailLoaderTests: XCTestCase {
    func testDownsamplesLargeBitmapWithinPixelBudget() throws {
        let data = try png(width: 2_048, height: 1_024)

        let thumbnail = try QuillCodeImageThumbnailLoader.thumbnail(
            from: data,
            maximumPixelSize: 256
        )

        XCTAssertEqual(thumbnail.pixelWidth, 256)
        XCTAssertEqual(thumbnail.pixelHeight, 128)
    }

    func testDoesNotUpscaleSmallBitmap() throws {
        let data = try png(width: 64, height: 32)

        let thumbnail = try QuillCodeImageThumbnailLoader.thumbnail(
            from: data,
            maximumPixelSize: 512
        )

        XCTAssertEqual(thumbnail.pixelWidth, 64)
        XCTAssertEqual(thumbnail.pixelHeight, 32)
    }

    func testRasterizesSVGWithinPixelBudget() throws {
        let data = Data(
            ##"<svg xmlns="http://www.w3.org/2000/svg" width="640" height="320"><rect width="640" height="320" fill="#2475b9"/></svg>"##.utf8
        )

        let thumbnail = try QuillCodeImageThumbnailLoader.thumbnail(
            from: data,
            maximumPixelSize: 160
        )

        XCTAssertEqual(thumbnail.pixelWidth, 160)
        XCTAssertEqual(thumbnail.pixelHeight, 80)
    }

    func testLoadsBoundedDataImageOffMainPath() async throws {
        let data = try png(width: 320, height: 160)
        let url = try XCTUnwrap(URL(string: "data:image/png;base64,\(data.base64EncodedString())"))

        let thumbnail = try await QuillCodeImageThumbnailLoader.load(
            from: url,
            maximumPixelSize: 80
        )

        XCTAssertEqual(thumbnail.pixelWidth, 80)
        XCTAssertEqual(thumbnail.pixelHeight, 40)
    }

    func testStreamsAndDownsamplesRemoteImageWithinBounds() async throws {
        let data = try png(width: 640, height: 320)
        ImageThumbnailURLProtocol.state.configure(payload: data)
        defer { ImageThumbnailURLProtocol.state.reset() }

        let thumbnail = try await QuillCodeImageThumbnailLoader.load(
            from: URL(string: "https://example.com/preview.png")!,
            maximumPixelSize: 160,
            remoteSessionConfiguration: ImageThumbnailURLProtocol.configuration()
        )

        XCTAssertEqual(thumbnail.pixelWidth, 160)
        XCTAssertEqual(thumbnail.pixelHeight, 80)
    }

    func testRejectsOversizedRemoteResponseBeforeBodyDownload() async throws {
        ImageThumbnailURLProtocol.state.configure(
            payload: Data(),
            declaredContentLength: QuillCodeImageThumbnailLoader.maximumEncodedBytes + 1
        )
        defer { ImageThumbnailURLProtocol.state.reset() }

        do {
            _ = try await QuillCodeImageThumbnailLoader.load(
                from: URL(string: "https://example.com/oversized.png")!,
                maximumPixelSize: 160,
                remoteSessionConfiguration: ImageThumbnailURLProtocol.configuration()
            )
            XCTFail("Expected an oversized remote image to be rejected.")
        } catch QuillCodeImageThumbnailError.sourceTooLarge {
            XCTAssertEqual(ImageThumbnailURLProtocol.state.deliveredBytes, 0)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testRejectsOversizedLocalFileBeforeImageDecode() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "quill-cowork-thumbnail-tests-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("oversized.png")
        XCTAssertTrue(FileManager.default.createFile(atPath: fileURL.path, contents: nil))
        let handle = try FileHandle(forWritingTo: fileURL)
        try handle.truncate(atOffset: UInt64(QuillCodeImageThumbnailLoader.maximumEncodedBytes + 1))
        try handle.close()

        XCTAssertThrowsError(
            try QuillCodeImageThumbnailLoader.thumbnail(
                fromFile: fileURL,
                maximumPixelSize: 256
            )
        ) { error in
            guard case QuillCodeImageThumbnailError.sourceTooLarge = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    private func png(width: Int, height: Int) throws -> Data {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0.12, green: 0.46, blue: 0.72, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try XCTUnwrap(context.makeImage())
        let output = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(
            output,
            UTType.png.identifier as CFString,
            1,
            nil
        ))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return output as Data
    }
}

private final class ImageThumbnailURLProtocolState: @unchecked Sendable {
    struct Fixture: Sendable {
        var payload: Data
        var declaredContentLength: Int
    }

    private let lock = NSLock()
    private var fixture: Fixture?
    private var deliveredByteCount = 0

    var deliveredBytes: Int {
        lock.lock()
        defer { lock.unlock() }
        return deliveredByteCount
    }

    func configure(payload: Data, declaredContentLength: Int? = nil) {
        lock.lock()
        fixture = Fixture(
            payload: payload,
            declaredContentLength: declaredContentLength ?? payload.count
        )
        deliveredByteCount = 0
        lock.unlock()
    }

    func snapshot() -> Fixture? {
        lock.lock()
        defer { lock.unlock() }
        return fixture
    }

    func recordDelivery(_ count: Int) {
        lock.lock()
        deliveredByteCount += count
        lock.unlock()
    }

    func reset() {
        lock.lock()
        fixture = nil
        deliveredByteCount = 0
        lock.unlock()
    }
}

private final class ImageThumbnailURLProtocol: URLProtocol, @unchecked Sendable {
    static let state = ImageThumbnailURLProtocolState()

    static func configuration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ImageThumbnailURLProtocol.self]
        return configuration
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let fixture = Self.state.snapshot(),
              let url = request.url,
              let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: [
                    "Content-Length": String(fixture.declaredContentLength),
                    "Content-Type": "image/png",
                ]
              )
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        guard !fixture.payload.isEmpty else {
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        Self.state.recordDelivery(fixture.payload.count)
        client?.urlProtocol(self, didLoad: fixture.payload)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
#endif
