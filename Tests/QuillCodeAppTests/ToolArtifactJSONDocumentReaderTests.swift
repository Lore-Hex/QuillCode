import Foundation
import XCTest
@testable import QuillCodeApp

final class ToolArtifactJSONDocumentReaderTests: XCTestCase {
    override func setUp() {
        super.setUp()
        ToolArtifactJSONDocumentReader.resetCacheForTesting()
    }

    override func tearDown() {
        ToolArtifactJSONDocumentReader.resetCacheForTesting()
        super.tearDown()
    }

    func testPreviewBuildersShareOneFileReadAndParse() throws {
        let fileURL = try fixtureFile(contents: """
        [{"filePath":"/workspace/App.swift","messages":[{"ruleId":"no-debugger","severity":2}],"errorCount":1,"warningCount":0}]
        """)
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        let artifact = ToolArtifactState(value: fileURL.path)
        XCTAssertNotNil(artifact.eslintJSONPreview)
        XCTAssertNil(artifact.stylelintJSONPreview)
        XCTAssertNil(artifact.jsonPreview)

        let diagnostics = ToolArtifactJSONDocumentReader.diagnosticsForTesting()
        XCTAssertEqual(diagnostics.fileReadCount, 1)
        XCTAssertEqual(diagnostics.parseCount, 1)
        XCTAssertGreaterThanOrEqual(diagnostics.cacheHitCount, 3)
    }

    func testMalformedDocumentIsNegativelyCached() throws {
        let fileURL = try fixtureFile(contents: #"{"unfinished": true"#)
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        let artifact = ToolArtifactState(value: fileURL.path)
        XCTAssertNil(artifact.eslintJSONPreview)
        XCTAssertNil(artifact.pytestJSONPreview)
        XCTAssertNil(artifact.jsonPreview)

        let diagnostics = ToolArtifactJSONDocumentReader.diagnosticsForTesting()
        XCTAssertEqual(diagnostics.fileReadCount, 1)
        XCTAssertEqual(diagnostics.parseCount, 1)
        XCTAssertGreaterThanOrEqual(diagnostics.cacheHitCount, 2)
    }

    func testMetadataChangeInvalidatesSamePathAndSize() throws {
        let fileURL = try fixtureFile(contents: #"{"a":1}"#)
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        let first = try XCTUnwrap(ToolArtifactJSONDocumentReader.document(for: fileURL, byteLimit: 1_024))
        XCTAssertEqual((first.root as? [String: Int])?["a"], 1)

        try Data(#"{"b":2}"#.utf8).write(to: fileURL)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(2)],
            ofItemAtPath: fileURL.path
        )

        let second = try XCTUnwrap(ToolArtifactJSONDocumentReader.document(for: fileURL, byteLimit: 1_024))
        XCTAssertEqual((second.root as? [String: Int])?["b"], 2)
        XCTAssertEqual(
            ToolArtifactJSONDocumentReader.diagnosticsForTesting(),
            .init(fileReadCount: 2, parseCount: 2, cacheHitCount: 0)
        )
    }

    func testConcurrentRequestsCoalesceIntoOneParse() throws {
        let fileURL = try fixtureFile(contents: #"{"value":42}"#)
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        DispatchQueue.concurrentPerform(iterations: 32) { _ in
            _ = try? ToolArtifactJSONDocumentReader.document(for: fileURL, byteLimit: 1_024)
        }

        XCTAssertEqual(
            ToolArtifactJSONDocumentReader.diagnosticsForTesting(),
            .init(fileReadCount: 1, parseCount: 1, cacheHitCount: 31)
        )
    }

    func testStructurallyExplosiveDocumentIsRejectedAndNegativelyCached() throws {
        let fileURL = try fixtureFile(contents: "[" + Array(repeating: "0", count: 16_384).joined(separator: ",") + "]")
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        XCTAssertNil(try ToolArtifactJSONDocumentReader.document(for: fileURL, byteLimit: 128 * 1_024))
        XCTAssertNil(try ToolArtifactJSONDocumentReader.document(for: fileURL, byteLimit: 128 * 1_024))
        XCTAssertEqual(
            ToolArtifactJSONDocumentReader.diagnosticsForTesting(),
            .init(fileReadCount: 1, parseCount: 1, cacheHitCount: 1)
        )
    }

    func testCallerByteLimitIsEnforcedBeforeReadingOrCaching() throws {
        let fileURL = try fixtureFile(contents: #"{"payload":"abcdefghijklmnopqrstuvwxyz"}"#)
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        XCTAssertNil(try ToolArtifactJSONDocumentReader.document(for: fileURL, byteLimit: 8))
        XCTAssertEqual(
            ToolArtifactJSONDocumentReader.diagnosticsForTesting(),
            .init(fileReadCount: 0, parseCount: 0, cacheHitCount: 0)
        )
        XCTAssertNotNil(try ToolArtifactJSONDocumentReader.document(for: fileURL, byteLimit: 1_024))
        XCTAssertEqual(ToolArtifactJSONDocumentReader.diagnosticsForTesting().parseCount, 1)
    }

    private func fixtureFile(contents: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("quill-cowork-json-preview-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent("artifact.json")
        try Data(contents.utf8).write(to: fileURL)
        return fileURL
    }
}
