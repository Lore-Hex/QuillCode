import XCTest
import Foundation
import QuillCodeCore
@testable import QuillCodeTools

// Shared helpers for the encoding round-trip tests.
private let bom = Data([0xEF, 0xBB, 0xBF])

private func makeWorkspace() throws -> URL {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("qc-enc-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

private func containsCRLF(_ data: Data) -> Bool {
    let bytes = [UInt8](data)
    for i in bytes.indices.dropLast() where bytes[i] == 0x0D && bytes[i + 1] == 0x0A {
        return true
    }
    return false
}

// MARK: - Functional: through FileToolExecutor.write / .read

final class FileEncodingExecutorFunctionalTests: XCTestCase {
    func testWritePreservesBOMAndCRLFOfExistingFile() throws {
        let root = try makeWorkspace()
        let files = FileToolExecutor(workspaceRoot: root)
        let url = root.appendingPathComponent("windows.txt")
        try (bom + Data("old\r\nlines\r\n".utf8)).write(to: url)

        // The model edits it with bare-LF content (as it always does).
        XCTAssertTrue(files.write(path: "windows.txt", content: "new\nlines\n").ok)

        let raw = try Data(contentsOf: url)
        XCTAssertTrue(raw.starts(with: [0xEF, 0xBB, 0xBF]), "BOM must be preserved")
        XCTAssertTrue(containsCRLF(raw), "CRLF must be preserved")
        XCTAssertEqual(raw, bom + Data("new\r\nlines\r\n".utf8))
    }

    func testWriteNewFileIsPlainLFNoBOM() throws {
        let root = try makeWorkspace()
        let files = FileToolExecutor(workspaceRoot: root)
        XCTAssertTrue(files.write(path: "fresh.txt", content: "a\nb\n").ok)
        let raw = try Data(contentsOf: root.appendingPathComponent("fresh.txt"))
        XCTAssertEqual(raw, Data("a\nb\n".utf8))
    }

    func testWriteOverLFFileStaysLF() throws {
        let root = try makeWorkspace()
        let files = FileToolExecutor(workspaceRoot: root)
        let url = root.appendingPathComponent("unix.txt")
        try Data("one\ntwo\n".utf8).write(to: url)
        XCTAssertTrue(files.write(path: "unix.txt", content: "three\nfour\n").ok)
        XCTAssertEqual(try Data(contentsOf: url), Data("three\nfour\n".utf8))
    }

    func testReadNormalizesBOMAndCRLFForDisplay() throws {
        let root = try makeWorkspace()
        let files = FileToolExecutor(workspaceRoot: root)
        let url = root.appendingPathComponent("windows.txt")
        try (bom + Data("a\r\nb\r\n".utf8)).write(to: url)
        // The numbered view must be clean: no U+FEFF on line 1, no trailing \r.
        XCTAssertEqual(files.read(path: "windows.txt").stdout, "1\ta\n2\tb")
    }

    func testReadRendersLoneCRFileAsNumberedLines() throws {
        // Classic-Mac CR-only endings must render as three numbered lines, not one line with
        // embedded control characters.
        let root = try makeWorkspace()
        let files = FileToolExecutor(workspaceRoot: root)
        try Data("one\rtwo\rthree".utf8).write(to: root.appendingPathComponent("classic.txt"))
        XCTAssertEqual(files.read(path: "classic.txt").stdout, "1\tone\n2\ttwo\n3\tthree")
    }
}

// MARK: - Integration: through the ToolRouter dispatch the agent uses

final class FileEncodingRouterIntegrationTests: XCTestCase {
    func testRouterFileWritePreservesExistingStyle() throws {
        let root = try makeWorkspace()
        let url = root.appendingPathComponent("windows.txt")
        try (bom + Data("old\r\n".utf8)).write(to: url)

        let router = ToolRouter(workspaceRoot: root)
        // Overwriting an existing file requires the session to have read it first.
        XCTAssertTrue(router.execute(ToolCall(
            name: ToolDefinition.fileRead.name,
            argumentsJSON: #"{"path":"windows.txt"}"#
        )).ok)
        let call = ToolCall(
            name: ToolDefinition.fileWrite.name,
            argumentsJSON: #"{"path":"windows.txt","content":"changed\n"}"#
        )
        let result = router.execute(call)
        XCTAssertTrue(result.ok, result.error ?? "")

        let raw = try Data(contentsOf: url)
        XCTAssertEqual(raw, bom + Data("changed\r\n".utf8))
    }
}
