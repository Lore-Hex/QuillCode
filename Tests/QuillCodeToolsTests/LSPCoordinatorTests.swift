import Foundation
import XCTest
import QuillCodeCore
@testable import QuillCodeTools

final class LSPCoordinatorTests: XCTestCase {
    private var workspace: URL!

    override func setUpWithError() throws {
        workspace = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("quillcode-lsp-coord-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        // Resolve symlinks (/var -> /private/var on macOS) so on-disk paths match the coordinator's.
        workspace = workspace.resolvingSymlinksInPath()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: workspace)
    }

    private func registry(available: Bool) -> LSPServerRegistry {
        LSPServerRegistry(
            configs: LSPServerRegistry.defaults,
            commandLocator: StubCommandLocator(resolvedPath: available ? "/usr/bin/sourcekit-lsp" : nil)
        )
    }

    private func makeCoordinator(server: StubLanguageServer, available: Bool = true, formatOnSave: Bool = false) -> LSPCoordinator {
        let launcher = StubLSPServerLauncher { server }
        let sessions = LSPSessionManager(workspaceRoot: workspace, registry: registry(available: available), launcher: launcher)
        return LSPCoordinator(workspaceRoot: workspace, sessions: sessions, formatOnSave: formatOnSave, diagnosticsWait: 0.4)
    }

    private func writeFile(_ name: String, _ contents: String) throws -> URL {
        let url = workspace.appendingPathComponent(name)
        try Data(contents.utf8).write(to: url)
        return url
    }

    func testDiagnosticsAfterWriteReportsErrors() throws {
        let file = try writeFile("Broken.swift", "let x = \n")
        let server = StubLanguageServer()
        server.initializeResult = ["capabilities": [:]]
        server.diagnosticsOnSave[LSPURI.from(path: file.path)] = [[
            "range": ["start": ["line": 0, "character": 8], "end": ["line": 0, "character": 8]],
            "severity": 1,
            "message": "expected expression after '='"
        ]]
        let coordinator = makeCoordinator(server: server)

        let feedback = coordinator.afterWrite(paths: [file])
        let notice = try XCTUnwrap(feedback.notice)
        XCTAssertTrue(notice.contains("Broken.swift:1:"), notice)
        XCTAssertTrue(notice.contains("expected expression"), notice)
        XCTAssertFalse(feedback.didFormat)
    }

    func testMissingServerDegradesGracefully() throws {
        let file = try writeFile("A.swift", "let x = 1\n")
        let server = StubLanguageServer()
        let coordinator = makeCoordinator(server: server, available: false)

        let feedback = coordinator.afterWrite(paths: [file])
        // One-time notice about the missing server; never an error, never a crash.
        XCTAssertNotNil(feedback.notice)
        XCTAssertTrue(feedback.notice!.contains("not available"))
        XCTAssertFalse(feedback.didFormat)
        // Second write: no repeated notice.
        XCTAssertNil(coordinator.afterWrite(paths: [file]).notice)
    }

    func testUnsupportedFileTypeIsNoOp() throws {
        let file = try writeFile("notes.md", "# hi\n")
        let server = StubLanguageServer()
        let coordinator = makeCoordinator(server: server)
        let feedback = coordinator.afterWrite(paths: [file])
        XCTAssertNil(feedback.notice)
        XCTAssertFalse(feedback.didFormat)
    }

    func testFormatOnSaveRewritesFileAndIsIdempotent() throws {
        let messy = "let  x=1\n"
        let clean = "let x = 1\n"
        let file = try writeFile("Messy.swift", messy)

        let server = StubLanguageServer()
        server.initializeResult = ["capabilities": ["documentFormattingProvider": true]]
        // The server returns a full-range edit replacing the document with the clean text.
        server.resultsByMethod["textDocument/formatting"] = [[
            "range": ["start": ["line": 0, "character": 0], "end": ["line": 1, "character": 0]],
            "newText": clean
        ]]
        let coordinator = makeCoordinator(server: server, formatOnSave: true)

        let feedback = coordinator.afterWrite(paths: [file])
        XCTAssertTrue(feedback.didFormat)
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), clean)
        XCTAssertTrue(feedback.notice?.contains("Auto-formatted") ?? false)

        // Idempotence: reformatting already-clean content produces the same clean text. Point the
        // server at an edit that yields the identical text -> no rewrite, no format notice.
        server.resultsByMethod["textDocument/formatting"] = [[
            "range": ["start": ["line": 0, "character": 0], "end": ["line": 1, "character": 0]],
            "newText": clean
        ]]
        let second = coordinator.afterWrite(paths: [file])
        XCTAssertFalse(second.didFormat, "no change means no rewrite")
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), clean)
    }

    func testFormatFailureKeepsOriginal() throws {
        let original = "let  x=1\n"
        let file = try writeFile("Keep.swift", original)

        let server = StubLanguageServer()
        server.initializeResult = ["capabilities": ["documentFormattingProvider": true]]
        // A malformed edit (position past the end) must be rejected, leaving the file untouched.
        server.resultsByMethod["textDocument/formatting"] = [[
            "range": ["start": ["line": 99, "character": 0], "end": ["line": 99, "character": 5]],
            "newText": "garbage"
        ]]
        let coordinator = makeCoordinator(server: server, formatOnSave: true)

        let feedback = coordinator.afterWrite(paths: [file])
        XCTAssertFalse(feedback.didFormat)
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), original, "malformed format edits must not corrupt the file")
    }

    func testFormatOnSavePreservesCRLFLineEndings() throws {
        // A CRLF file must stay CRLF after formatting — format-on-save must not silently rewrite every
        // line to LF (the same guarantee host.file.write gives via FileEncodingPreservation).
        let messyCRLF = "let  x=1\r\n"
        let cleanLF = "let x = 1\n" // sourcekit-lsp emits LF
        let url = workspace.appendingPathComponent("CRLF.swift")
        try Data(messyCRLF.utf8).write(to: url)

        let server = StubLanguageServer()
        server.initializeResult = ["capabilities": ["documentFormattingProvider": true]]
        server.resultsByMethod["textDocument/formatting"] = [[
            "range": ["start": ["line": 0, "character": 0], "end": ["line": 1, "character": 0]],
            "newText": cleanLF
        ]]
        let coordinator = makeCoordinator(server: server, formatOnSave: true)

        let feedback = coordinator.afterWrite(paths: [url])
        XCTAssertTrue(feedback.didFormat)
        let onDisk = try Data(contentsOf: url)
        let text = String(decoding: onDisk, as: UTF8.self)
        XCTAssertTrue(text.contains("\r\n"), "CRLF line endings must be preserved, got: \(text.debugDescription)")
        XCTAssertEqual(text, "let x = 1\r\n")
    }

    func testFormatOnSaveDoesNotDoubleBOMAndIsIdempotent() throws {
        // A UTF-8 BOM-prefixed file, formatted, must end with EXACTLY ONE BOM — not a doubled one —
        // and a second format-on-save pass must be a byte-for-byte no-op.
        let bom: [UInt8] = [0xEF, 0xBB, 0xBF]
        let url = workspace.appendingPathComponent("BOM.swift")
        try Data(bom + Array("let  x=1\n".utf8)).write(to: url)

        let server = StubLanguageServer()
        server.initializeResult = ["capabilities": ["documentFormattingProvider": true]]
        // The server sees the decoded text (with a leading U+FEFF scalar) and returns the formatted
        // document, preserving that scalar the way a real server round-trips the file's leading BOM.
        server.resultsByMethod["textDocument/formatting"] = [[
            "range": ["start": ["line": 0, "character": 0], "end": ["line": 1, "character": 0]],
            "newText": "\u{FEFF}let x = 1\n"
        ]]
        let coordinator = makeCoordinator(server: server, formatOnSave: true)

        let feedback = coordinator.afterWrite(paths: [url])
        XCTAssertTrue(feedback.didFormat)
        let onDisk = [UInt8](try Data(contentsOf: url))
        // Exactly one BOM at the front, and no second BOM immediately after it.
        XCTAssertEqual(Array(onDisk.prefix(3)), bom, "must start with a single BOM")
        XCTAssertNotEqual(Array(onDisk.dropFirst(3).prefix(3)), bom, "the BOM must not be doubled")
        XCTAssertEqual(onDisk, bom + Array("let x = 1\n".utf8))

        // Idempotence: a second pass over the already-formatted BOM file must not change any bytes.
        let before = try Data(contentsOf: url)
        let second = coordinator.afterWrite(paths: [url])
        XCTAssertFalse(second.didFormat, "re-formatting an already-formatted BOM file must be a no-op")
        XCTAssertEqual(try Data(contentsOf: url), before, "second pass must be byte-for-byte identical")
    }

    func testFormatOffByDefaultLeavesFileUntouched() throws {
        let original = "let  x=1\n"
        let file = try writeFile("NoFormat.swift", original)
        let server = StubLanguageServer()
        server.initializeResult = ["capabilities": ["documentFormattingProvider": true]]
        server.resultsByMethod["textDocument/formatting"] = [[
            "range": ["start": ["line": 0, "character": 0], "end": ["line": 1, "character": 0]],
            "newText": "let x = 1\n"
        ]]
        // formatOnSave defaults to false.
        let coordinator = makeCoordinator(server: server, formatOnSave: false)
        let feedback = coordinator.afterWrite(paths: [file])
        XCTAssertFalse(feedback.didFormat)
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), original)
    }
}
