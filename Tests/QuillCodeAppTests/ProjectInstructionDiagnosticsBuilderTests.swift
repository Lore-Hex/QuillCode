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

    func testDiagnosticsFlagSemanticContradictionsAcrossOverlappingScopes() {
        let diagnostics = ProjectInstructionDiagnosticsBuilder.diagnostics(for: [
            instruction("AGENTS.md", content: "General guidance.\nAlways run tests before final answers."),
            instruction(
                "Sources/Feature/AGENTS.md",
                content: "Feature guidance.\nDo not run tests for feature changes."
            )
        ])

        XCTAssertEqual(diagnostics.map(\.id), [
            "instruction-nested-override-Sources-Feature",
            "instruction-semantic-conflict-tests-agents-md-sources-feature-agents-md"
        ])
        XCTAssertEqual(diagnostics[1].title, "Conflicting instruction intent")
        XCTAssertEqual(
            diagnostics[1].detail,
            "Tests: AGENTS.md says require; Sources/Feature/AGENTS.md says avoid"
        )
        XCTAssertEqual(diagnostics[1].statusLabel, "conflict")
        XCTAssertEqual(
            diagnostics[1].sourceReferences.map(\.locationLabel),
            ["AGENTS.md:2", "Sources/Feature/AGENTS.md:2"]
        )
        XCTAssertEqual(
            diagnostics[1].sourceReferences.map(\.excerpt),
            [
                "Always run tests before final answers.",
                "Do not run tests for feature changes."
            ]
        )
        XCTAssertEqual(diagnostics[1].sourceReferences.map(\.role), ["requires tests", "avoids tests"])
        XCTAssertEqual(
            diagnostics[1].resolutionHint,
            "Choose one intent for tests guidance and edit the conflicting lines so they agree."
        )
    }

    func testDiagnosticsAttachSourceReferencesToStructuralIssues() {
        let diagnostics = ProjectInstructionDiagnosticsBuilder.diagnostics(for: [
            instruction("AGENTS.md", content: "Root rule."),
            instruction(".quillcode/rules.md", content: "Project rule."),
            instruction("Sources/Feature/AGENTS.md", content: "Feature rule.")
        ])

        XCTAssertEqual(diagnostics[0].title, "Shared instruction scope")
        XCTAssertEqual(
            diagnostics[0].sourceReferences.map(\.locationLabel),
            ["AGENTS.md:1", ".quillcode/rules.md:1"]
        )
        XCTAssertEqual(diagnostics[1].title, "Nested instruction override")
        XCTAssertEqual(
            diagnostics[1].sourceReferences.map(\.locationLabel),
            ["Sources/Feature/AGENTS.md:1", "AGENTS.md:1", ".quillcode/rules.md:1"]
        )
        XCTAssertTrue(diagnostics[1].resolutionHint.contains("State the override explicitly"))
    }

    func testDiagnosticsDoNotFlagSemanticContradictionsAcrossSiblingScopes() {
        let diagnostics = ProjectInstructionDiagnosticsBuilder.diagnostics(for: [
            instruction("Sources/Feature/AGENTS.md", content: "Always run tests for feature changes."),
            instruction("Tests/AGENTS.md", content: "Do not run tests for test-fixture updates.")
        ])

        XCTAssertEqual(diagnostics, [])
    }

    func testDiagnosticsDeduplicateRepeatedSemanticClaims() {
        let diagnostics = ProjectInstructionDiagnosticsBuilder.diagnostics(for: [
            instruction("AGENTS.md", content: "Always run tests. Must run tests before final answers."),
            instruction(".quillcode/rules.md", content: "Never run tests. Do not run tests for this project.")
        ])

        XCTAssertEqual(diagnostics.map(\.id), [
            "instruction-duplicate-scope-root",
            "instruction-semantic-conflict-tests-agents-md-quillcode-rules-md"
        ])
    }

    private func instruction(_ path: String, content: String = "Rules") -> ProjectInstruction {
        ProjectInstruction(
            path: path,
            title: path,
            content: content,
            byteCount: content.utf8.count
        )
    }
}
