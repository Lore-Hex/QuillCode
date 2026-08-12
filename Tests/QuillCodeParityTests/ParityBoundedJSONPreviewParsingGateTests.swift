import XCTest

final class ParityBoundedJSONPreviewParsingGateTests: QuillCodeParityTestCase {
    func testStructuredJSONPreviewsUseSharedBoundedDocumentReader() throws {
        let reader = try Self.appSourceText(named: "ToolArtifactJSONDocumentReader.swift")
        Self.assertSource(reader, containsAll: [
            "NSCache<CacheKey, Box>",
            "cacheEntryLimit = 4",
            "cacheEstimatedByteLimit = 4 * 1_024 * 1_024",
            "maximumDepth = 64",
            "maximumNodeCount = 16_384",
            ".contentModificationDateKey",
            ".fileResourceIdentifierKey",
            "private let lock = NSLock()"
        ])

        let directParserAllowlist: Set<String> = [
            "ToolArtifactBunLockfilePreviewBuilder.swift",
            "ToolArtifactCargoCompilerJSONLinesPreviewBuilder.swift",
            "ToolArtifactGoTestJSONLinesPreviewBuilder.swift",
            "ToolArtifactJSONLinesPreviewBuilder.swift",
            "ToolArtifactMypyJSONPreviewBuilder.swift"
        ]
        var sharedReaderCount = 0

        for fileURL in try Self.swiftSourceFiles(in: "Sources/QuillCodeApp")
            where fileURL.lastPathComponent.hasPrefix("ToolArtifact")
                && fileURL.lastPathComponent.hasSuffix("PreviewBuilder.swift")
        {
            let source = try String(contentsOf: fileURL, encoding: .utf8)
            if source.contains("ToolArtifactJSONDocumentReader.document") {
                sharedReaderCount += 1
            }
            if source.contains("JSONSerialization.jsonObject"),
               !directParserAllowlist.contains(fileURL.lastPathComponent) {
                XCTFail("\(fileURL.lastPathComponent) bypasses the shared bounded JSON reader")
            }
        }

        XCTAssertGreaterThanOrEqual(sharedReaderCount, 39)
    }
}
