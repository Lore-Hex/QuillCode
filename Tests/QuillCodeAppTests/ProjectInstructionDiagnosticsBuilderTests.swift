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

    func testDiagnosticsFlagNestedInstructionOverlaps() {
        let diagnostics = ProjectInstructionDiagnosticsBuilder.diagnostics(for: [
            instruction("AGENTS.md", content: "Keep changes reviewable.\nRun focused tests."),
            instruction("Sources/AGENTS.md", content: "Keep changes reviewable.\nUse source patterns."),
            instruction("Sources/Feature/.quillcode/rules.md", content: "Run focused tests.\nUse feature patterns.")
        ])

        XCTAssertEqual(diagnostics.map(\.id), [
            "instruction-nested-overlap-Sources",
            "instruction-nested-overlap-Sources-Feature"
        ])
        XCTAssertEqual(
            diagnostics[1].detail,
            "Sources/Feature/** repeats broader guidance in Sources/Feature/.quillcode/rules.md; broader source AGENTS.md, Sources/AGENTS.md already applies"
        )
        XCTAssertEqual(diagnostics[1].statusLabel, "scope")
        XCTAssertEqual(
            diagnostics[1].sourceReferences.map(\.role),
            ["repeated nested guidance", "broader guidance"]
        )
    }

    func testDiagnosticsFlagExplicitNestedOverrideLanguage() {
        let diagnostics = ProjectInstructionDiagnosticsBuilder.diagnostics(for: [
            instruction("AGENTS.md", content: "Keep changes reviewable."),
            instruction(
                "Sources/Feature/AGENTS.md",
                content: "Use feature patterns.\nThis file overrides broader guidance for feature experiments."
            )
        ])

        XCTAssertEqual(diagnostics.map(\.id), ["instruction-nested-override-Sources-Feature"])
        XCTAssertEqual(diagnostics.first?.title, "Nested instruction override")
        XCTAssertEqual(diagnostics.first?.sourceReferences.map(\.role), ["nested override", "broader guidance"])
        XCTAssertEqual(
            diagnostics.first?.sourceReferences.map(\.locationLabel),
            ["Sources/Feature/AGENTS.md:2", "AGENTS.md:1"]
        )
        XCTAssertEqual(
            diagnostics.first?.sourceReferences.first?.excerpt,
            "This file overrides broader guidance for feature experiments."
        )
    }

    func testDiagnosticsDoNotFlagAdditiveNestedInstructions() {
        let diagnostics = ProjectInstructionDiagnosticsBuilder.diagnostics(for: [
            instruction("AGENTS.md", content: "Keep changes reviewable."),
            instruction("Sources/Feature/AGENTS.md", content: "Use feature patterns.")
        ])

        XCTAssertEqual(diagnostics, [])
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
            "instruction-semantic-conflict-tests-agents-md-sources-feature-agents-md"
        ])
        XCTAssertEqual(diagnostics[0].title, "Conflicting instruction intent")
        XCTAssertEqual(
            diagnostics[0].detail,
            "Tests: AGENTS.md says require; Sources/Feature/AGENTS.md says avoid"
        )
        XCTAssertEqual(diagnostics[0].statusLabel, "conflict")
        XCTAssertEqual(
            diagnostics[0].sourceReferences.map(\.locationLabel),
            ["AGENTS.md:2", "Sources/Feature/AGENTS.md:2"]
        )
        XCTAssertEqual(
            diagnostics[0].sourceReferences.map(\.excerpt),
            [
                "Always run tests before final answers.",
                "Do not run tests for feature changes."
            ]
        )
        XCTAssertEqual(diagnostics[0].sourceReferences.map(\.role), ["requires tests", "avoids tests"])
        XCTAssertEqual(
            diagnostics[0].resolutionHint,
            "Choose one intent for tests guidance and edit the conflicting lines so they agree."
        )
    }

    func testDiagnosticsAttachSourceReferencesToStructuralIssues() {
        let diagnostics = ProjectInstructionDiagnosticsBuilder.diagnostics(for: [
            instruction("AGENTS.md", content: "Keep changes reviewable."),
            instruction(".quillcode/rules.md", content: "Run focused validation."),
            instruction("Sources/Feature/AGENTS.md", content: "Keep changes reviewable.\nUse feature rule.")
        ])

        XCTAssertEqual(diagnostics[0].title, "Shared instruction scope")
        XCTAssertEqual(
            diagnostics[0].sourceReferences.map(\.locationLabel),
            ["AGENTS.md:1", ".quillcode/rules.md:1"]
        )
        XCTAssertEqual(diagnostics[1].title, "Nested instruction overlap")
        XCTAssertEqual(
            diagnostics[1].sourceReferences.map(\.locationLabel),
            ["Sources/Feature/AGENTS.md:1", "AGENTS.md:1"]
        )
        XCTAssertTrue(diagnostics[1].resolutionHint.contains("Keep broad guidance"))
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
