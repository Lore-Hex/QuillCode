import XCTest

final class ParityBoundedImagePreviewGateTests: QuillCodeParityTestCase {
    func testLocalImagePreviewSurfacesUseBoundedThumbnailDecoding() throws {
        let loader = try Self.appSourceText(named: "QuillCodeBoundedAsyncImage.swift")
        let artifact = try Self.appSourceText(named: "QuillCodeArtifactImagePreview.swift")
        let attachments = try Self.appSourceText(named: "QuillCodeImageAttachmentViews.swift")
        let documents = try Self.appSourceText(named: "QuillCodeArtifactDocumentPreview.swift")
        let platformRasterizer = try Self.swiftSourceFiles(in: "Sources/QuillCodePlatformUI")
            .first { $0.lastPathComponent == "QuillCodePlatformImageRasterizer.swift" }
            .map { try String(contentsOf: $0, encoding: .utf8) }

        Self.assertSource(loader, containsAll: [
            "CGImageSourceCreateThumbnailAtIndex",
            "kCGImageSourceThumbnailMaxPixelSize",
            "kCGImageSourceShouldCacheImmediately",
            "Task.detached(priority: .utility)",
            "maximumEncodedBytes"
        ])
        Self.assertSource(loader, contains: "QuillCodePlatformImageRasterizer")
        Self.assertSource(loader, excludes: "import AppKit")
        Self.assertSource(try XCTUnwrap(platformRasterizer), containsAll: [
            "import AppKit",
            "NSImage(data: data)",
            "maximumPixelSize"
        ])
        Self.assertSource(artifact, contains: "maximumPixelSize: 1_536")
        Self.assertSource(attachments, contains: "maximumPixelSize: 512")
        Self.assertSource(documents, contains: "maximumPixelSize: 256")
        for source in [artifact, attachments, documents] {
            Self.assertSource(source, contains: "QuillCodeBoundedAsyncImage")
            XCTAssertFalse(source.split(separator: "\n").contains { line in
                line.trimmingCharacters(in: .whitespaces).hasPrefix("AsyncImage(")
            })
        }
    }
}
