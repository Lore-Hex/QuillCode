import XCTest
import QuillCodeCore
@testable import QuillCodeApp

final class ProjectInstructionDiagnosticsBuilderTests: XCTestCase {
    func testDiagnosticsFlagDuplicateInstructionScopes() {
        let diagnostics = ProjectInstructionDiagnosticsBuilder.diagnostics(for: [
            instruction("AGENTS.md"),
            instruction(".quillcode/rules.md"),
            instruction("Sources/Feature/AGENTS.md")
        ])

        XCTAssertEqual(diagnostics.first?.id, "instruction-duplicate-scope-root")
        XCTAssertEqual(diagnostics.first?.title, "Shared instruction scope")
        XCTAssertEqual(diagnostics.first?.detail, "whole project: AGENTS.md, .quillcode/rules.md")
        XCTAssertEqual(diagnostics.first?.statusLabel, "review")
    }

    func testDiagnosticsFlagNestedInstructionOverrides() {
        let diagnostics = ProjectInstructionDiagnosticsBuilder.diagnostics(for: [
            instruction("AGENTS.md"),
            instruction("Sources/AGENTS.md"),
            instruction("Sources/Feature/.quillcode/rules.md"),
            instruction("Tests/AGENTS.md")
        ])

        XCTAssertEqual(diagnostics.map(\.id), [
            "instruction-nested-override-Sources",
            "instruction-nested-override-Sources-Feature",
            "instruction-nested-override-Tests"
        ])
        XCTAssertEqual(
            diagnostics[1].detail,
            "Sources/Feature/** from Sources/Feature/.quillcode/rules.md may override AGENTS.md, Sources/AGENTS.md"
        )
        XCTAssertEqual(diagnostics[1].statusLabel, "scope")
    }

    func testDiagnosticsDoNotFlagSiblingScopes() {
        let diagnostics = ProjectInstructionDiagnosticsBuilder.diagnostics(for: [
            instruction("Sources/Feature/AGENTS.md"),
            instruction("Tests/AGENTS.md")
        ])

        XCTAssertEqual(diagnostics, [])
    }

    private func instruction(_ path: String) -> ProjectInstruction {
        ProjectInstruction(
            path: path,
            title: path,
            content: "Rules",
            byteCount: 5
        )
    }
}
