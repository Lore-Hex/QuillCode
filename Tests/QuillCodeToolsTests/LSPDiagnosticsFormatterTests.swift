import Foundation
import XCTest
@testable import QuillCodeTools

final class LSPDiagnosticsFormatterTests: XCTestCase {
    private let root = URL(fileURLWithPath: "/ws")

    private func diagnostic(line: Int, severity: LSPDiagnosticSeverity, message: String) -> LSPDiagnostic {
        LSPDiagnostic(
            range: LSPRange(start: LSPPosition(line: line, character: 0), end: LSPPosition(line: line, character: 1)),
            severity: severity,
            message: message
        )
    }

    func testNoErrorsOrWarningsReturnsNil() {
        let diagnostics = ["/ws/A.swift": [diagnostic(line: 0, severity: .information, message: "note")]]
        XCTAssertNil(LSPDiagnosticsFormatter.format(diagnosticsByPath: diagnostics, workspaceRoot: root))
    }

    func testFormatsErrorWithRelativePathAnd1BasedLine() throws {
        let diagnostics = ["/ws/Sources/A.swift": [diagnostic(line: 4, severity: .error, message: "cannot find 'foo'")]]
        let output = try XCTUnwrap(LSPDiagnosticsFormatter.format(diagnosticsByPath: diagnostics, workspaceRoot: root))
        XCTAssertTrue(output.contains("Sources/A.swift:5: error: cannot find 'foo'"), output)
    }

    func testCapsAtFiveFiles() throws {
        var diagnostics: [String: [LSPDiagnostic]] = [:]
        for i in 0..<8 {
            diagnostics["/ws/File\(i).swift"] = [diagnostic(line: 0, severity: .error, message: "boom \(i)")]
        }
        let output = try XCTUnwrap(LSPDiagnosticsFormatter.format(diagnosticsByPath: diagnostics, workspaceRoot: root))
        let shownFiles = Set(output.split(separator: "\n").compactMap { line -> String? in
            guard line.contains(".swift:") else { return nil }
            return String(line.split(separator: ":").first ?? "")
        })
        XCTAssertEqual(shownFiles.count, LSPDiagnosticsFormatter.maxFiles)
        XCTAssertTrue(output.contains("showing 5 of 8 files"), output)
    }

    func testEditedFileListedFirst() throws {
        let diagnostics = [
            "/ws/Zebra.swift": [diagnostic(line: 0, severity: .error, message: "z error")],
            "/ws/Apple.swift": [diagnostic(line: 0, severity: .error, message: "a error")]
        ]
        let output = try XCTUnwrap(LSPDiagnosticsFormatter.format(
            diagnosticsByPath: diagnostics,
            workspaceRoot: root,
            editedPath: "/ws/Zebra.swift"
        ))
        let firstFileLine = output.split(separator: "\n").first { $0.contains(".swift:") }
        XCTAssertTrue(firstFileLine?.contains("Zebra.swift") ?? false, "edited file should be first: \(output)")
    }

    func testErrorsSortBeforeWarnings() throws {
        let diagnostics = [
            "/ws/A.swift": [
                diagnostic(line: 10, severity: .warning, message: "a warning"),
                diagnostic(line: 2, severity: .error, message: "an error")
            ]
        ]
        let output = try XCTUnwrap(LSPDiagnosticsFormatter.format(diagnosticsByPath: diagnostics, workspaceRoot: root))
        let errorIndex = output.range(of: "an error")?.lowerBound
        let warningIndex = output.range(of: "a warning")?.lowerBound
        XCTAssertNotNil(errorIndex)
        XCTAssertNotNil(warningIndex)
        XCTAssertTrue(errorIndex! < warningIndex!, "errors should be listed before warnings")
    }

    func testMultilineMessageCollapsedToOneLine() throws {
        let diagnostics = ["/ws/A.swift": [diagnostic(line: 0, severity: .error, message: "line1\nline2")]]
        let output = try XCTUnwrap(LSPDiagnosticsFormatter.format(diagnosticsByPath: diagnostics, workspaceRoot: root))
        XCTAssertFalse(output.contains("line1\nline2"))
        XCTAssertTrue(output.contains("line1 line2"))
    }
}
