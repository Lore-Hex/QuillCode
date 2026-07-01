import XCTest
import QuillCodeCore
@testable import QuillCodeApp

final class ProjectInstructionDiagnosticPatchPlannerTests: XCTestCase {
    func testPlannerBuildsKeepSidePatchForSemanticConflict() throws {
        let root = ProjectInstruction(
            path: "AGENTS.md",
            title: "AGENTS.md",
            content: "Root guidance.\nAlways run tests before final answers.\nPrefer small diffs.\n",
            byteCount: 72
        )
        let nested = ProjectInstruction(
            path: "Sources/Feature/AGENTS.md",
            title: "Feature AGENTS.md",
            content: "Feature guidance.\nDo not run tests for feature changes.\nUse feature patterns.\n",
            byteCount: 76
        )
        let diagnostic = try semanticConflict(in: [root, nested])

        let plan = try XCTUnwrap(ProjectInstructionDiagnosticPatchPlanner.plan(
            for: diagnostic,
            keepReferenceIndex: 0,
            instructions: [root, nested]
        ))

        XCTAssertEqual(plan.diagnosticID, diagnostic.id)
        XCTAssertEqual(plan.keepReferenceIndex, 0)
        XCTAssertEqual(plan.summary, "Keep requires tests and remove the conflicting instruction line.")
        XCTAssertTrue(plan.patch.contains("diff --git a/Sources/Feature/AGENTS.md b/Sources/Feature/AGENTS.md"))
        XCTAssertTrue(plan.patch.contains("-Do not run tests for feature changes."))
        XCTAssertFalse(plan.patch.contains("-Always run tests before final answers."))
    }

    func testPlannerRejectsAmbiguousOrStaleDiagnostics() throws {
        let instruction = ProjectInstruction(
            path: "AGENTS.md",
            title: "AGENTS.md",
            content: "Always run tests before final answers.",
            byteCount: 38
        )
        let staleDiagnostic = ProjectInstructionDiagnostic(
            id: "instruction-semantic-conflict-tests-agents-md-rules-md",
            title: "Conflicting instruction intent",
            detail: "Tests conflict",
            statusLabel: ProjectInstructionDiagnosticStatusLabel.conflict,
            sourceReferences: [
                ProjectInstructionDiagnosticSourceReference(
                    path: "AGENTS.md",
                    lineNumber: 1,
                    role: "requires tests",
                    excerpt: "Not the current line"
                ),
                ProjectInstructionDiagnosticSourceReference(
                    path: ".quillcode/rules.md",
                    lineNumber: 1,
                    role: "avoids tests",
                    excerpt: "Do not run tests."
                )
            ]
        )

        XCTAssertNil(ProjectInstructionDiagnosticPatchPlanner.plan(
            for: staleDiagnostic,
            keepReferenceIndex: 0,
            instructions: [instruction]
        ))
    }

    func testSupportedActionsUseTypedInstructionDiagnosticCommands() throws {
        let diagnostic = try semanticConflict(in: [
            ProjectInstruction(
                path: "AGENTS.md",
                title: "AGENTS.md",
                content: "Always run tests before final answers.",
                byteCount: 38
            ),
            ProjectInstruction(
                path: "Sources/Feature/AGENTS.md",
                title: "Feature AGENTS.md",
                content: "Do not run tests for feature changes.",
                byteCount: 37
            )
        ])

        let actions = ProjectInstructionDiagnosticPatchPlanner.supportedKeepActions(for: diagnostic)

        XCTAssertEqual(actions.map(\.title), ["Keep requires tests", "Keep avoids tests"])
        XCTAssertEqual(actions.map(\.kind), ["apply", "apply"])
        XCTAssertEqual(actions.first?.commandID, "activity-instruction-apply:0:\(diagnostic.id)")
        XCTAssertEqual(actions.last?.commandID, "activity-instruction-apply:1:\(diagnostic.id)")
    }

    private func semanticConflict(
        in instructions: [ProjectInstruction],
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> ProjectInstructionDiagnostic {
        try XCTUnwrap(
            ProjectInstructionDiagnosticsBuilder
                .diagnostics(for: instructions)
                .first(where: \.isConflict),
            file: file,
            line: line
        )
    }
}
