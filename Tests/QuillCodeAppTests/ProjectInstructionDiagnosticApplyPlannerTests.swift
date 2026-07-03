import XCTest
import QuillCodeCore
import QuillCodeTools
@testable import QuillCodeApp

final class ProjectInstructionDiagnosticApplyPlannerTests: XCTestCase {
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

        let plan = try XCTUnwrap(ProjectInstructionDiagnosticApplyPlanner.plan(
            for: diagnostic,
            selectedReferenceIndex: 0,
            instructions: [root, nested]
        ))

        XCTAssertEqual(plan.diagnosticID, diagnostic.id)
        XCTAssertEqual(plan.selectedReferenceIndex, 0)
        XCTAssertEqual(plan.summary, "Keep requires tests and remove the conflicting instruction line.")
        XCTAssertEqual(plan.toolCall.name, ToolDefinition.applyPatch.name)
        let patch = try stringArgument("patch", in: plan.toolCall)
        XCTAssertTrue(patch.contains("diff --git a/Sources/Feature/AGENTS.md b/Sources/Feature/AGENTS.md"))
        XCTAssertTrue(patch.contains("-Do not run tests for feature changes."))
        XCTAssertFalse(patch.contains("-Always run tests before final answers."))
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

        XCTAssertNil(ProjectInstructionDiagnosticApplyPlanner.plan(
            for: staleDiagnostic,
            selectedReferenceIndex: 0,
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

        let actions = ProjectInstructionDiagnosticApplyPlanner.supportedActions(
            for: diagnostic,
            instructions: []
        )

        XCTAssertEqual(actions.map(\.title), ["Keep requires tests", "Keep avoids tests"])
        XCTAssertEqual(actions.map(\.kind), ["apply", "apply"])
        XCTAssertEqual(actions.first?.commandID, "activity-instruction-apply:0:\(diagnostic.id)")
        XCTAssertEqual(actions.last?.commandID, "activity-instruction-apply:1:\(diagnostic.id)")
    }

    func testPlannerClearsExactDuplicateScopeSourceWithFileWrite() throws {
        let root = ProjectInstruction(
            path: "AGENTS.md",
            title: "AGENTS.md",
            content: "Prefer small diffs.\nRun focused tests.",
            byteCount: 37
        )
        let rules = ProjectInstruction(
            path: ".quillcode/rules.md",
            title: "rules.md",
            content: "Prefer small diffs.\nRun focused tests.\n",
            byteCount: 38
        )
        let instructions = [root, rules]
        let diagnostic = try duplicateScope(in: instructions)

        let actions = ProjectInstructionDiagnosticApplyPlanner.supportedActions(
            for: diagnostic,
            instructions: instructions
        )
        let plan = try XCTUnwrap(ProjectInstructionDiagnosticApplyPlanner.plan(
            for: diagnostic,
            selectedReferenceIndex: 1,
            instructions: instructions
        ))

        XCTAssertEqual(actions.map(\.title), [
            "Clear duplicate AGENTS.md",
            "Clear duplicate .quillcode/rules.md"
        ])
        XCTAssertEqual(plan.diagnosticID, diagnostic.id)
        XCTAssertEqual(plan.selectedReferenceIndex, 1)
        XCTAssertEqual(plan.toolCall.name, ToolDefinition.fileWrite.name)
        XCTAssertEqual(plan.toolCall.argumentsJSON, ToolArguments.json([
            "content": "",
            "path": ".quillcode/rules.md"
        ]))
    }

    func testPlannerRejectsNonIdenticalDuplicateScopeSources() throws {
        let root = ProjectInstruction(
            path: "AGENTS.md",
            title: "AGENTS.md",
            content: "Prefer small diffs.",
            byteCount: 19
        )
        let rules = ProjectInstruction(
            path: ".quillcode/rules.md",
            title: "rules.md",
            content: "Prefer small diffs.\nUse Swift idioms.",
            byteCount: 37
        )
        let instructions = [root, rules]
        let diagnostic = try duplicateScope(in: instructions)

        XCTAssertTrue(ProjectInstructionDiagnosticApplyPlanner.supportedActions(
            for: diagnostic,
            instructions: instructions
        ).isEmpty)
        XCTAssertNil(ProjectInstructionDiagnosticApplyPlanner.plan(
            for: diagnostic,
            selectedReferenceIndex: 1,
            instructions: instructions
        ))
    }

    func testPlannerRemovesRepeatedBroadLinesFromNestedInstructionSource() throws {
        let root = ProjectInstruction(
            path: "AGENTS.md",
            title: "AGENTS.md",
            content: "Keep changes reviewable.\nRun focused validation.\n",
            byteCount: 48
        )
        let nested = ProjectInstruction(
            path: "Sources/Feature/AGENTS.md",
            title: "Feature AGENTS.md",
            content: "Use feature patterns.\nKeep changes reviewable.\nRun focused validation.\nPrefer local helpers.\n",
            byteCount: 90
        )
        let instructions = [root, nested]
        let diagnostic = try nestedOverlap(in: instructions)

        let actions = ProjectInstructionDiagnosticApplyPlanner.supportedActions(
            for: diagnostic,
            instructions: instructions
        )
        let plan = try XCTUnwrap(ProjectInstructionDiagnosticApplyPlanner.plan(
            for: diagnostic,
            selectedReferenceIndex: 0,
            instructions: instructions
        ))

        XCTAssertEqual(actions.map(\.title), ["Remove repeated lines from Sources/Feature/AGENTS.md"])
        XCTAssertEqual(plan.summary, "Remove repeated broad guidance from Sources/Feature/AGENTS.md.")
        XCTAssertEqual(plan.toolCall.name, ToolDefinition.applyPatch.name)
        let patch = try stringArgument("patch", in: plan.toolCall)
        XCTAssertTrue(patch.contains("diff --git a/Sources/Feature/AGENTS.md b/Sources/Feature/AGENTS.md"))
        XCTAssertTrue(patch.contains("-Keep changes reviewable."))
        XCTAssertTrue(patch.contains("-Run focused validation."))
        XCTAssertTrue(patch.contains(" Use feature patterns."))
        XCTAssertTrue(patch.contains(" Prefer local helpers."))
        XCTAssertFalse(patch.contains("diff --git a/AGENTS.md b/AGENTS.md"))
    }

    func testPlannerLeavesExplicitNestedOverrideManual() throws {
        let root = ProjectInstruction(
            path: "AGENTS.md",
            title: "AGENTS.md",
            content: "Keep changes reviewable.",
            byteCount: 24
        )
        let nested = ProjectInstruction(
            path: "Sources/Feature/AGENTS.md",
            title: "Feature AGENTS.md",
            content: "This file overrides broader guidance for feature experiments.",
            byteCount: 60
        )
        let instructions = [root, nested]
        let diagnostic = try XCTUnwrap(
            ProjectInstructionDiagnosticsBuilder
                .diagnostics(for: instructions)
                .first { $0.id.hasPrefix("instruction-nested-override-") }
        )

        XCTAssertEqual(ProjectInstructionDiagnosticApplyPlanner.supportedActions(
            for: diagnostic,
            instructions: instructions
        ), [])
        XCTAssertNil(ProjectInstructionDiagnosticApplyPlanner.plan(
            for: diagnostic,
            selectedReferenceIndex: 0,
            instructions: instructions
        ))
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

    private func duplicateScope(
        in instructions: [ProjectInstruction],
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> ProjectInstructionDiagnostic {
        try XCTUnwrap(
            ProjectInstructionDiagnosticsBuilder
                .diagnostics(for: instructions)
                .first(where: \.isDuplicateScope),
            file: file,
                line: line
        )
    }

    private func nestedOverlap(
        in instructions: [ProjectInstruction],
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> ProjectInstructionDiagnostic {
        try XCTUnwrap(
            ProjectInstructionDiagnosticsBuilder
                .diagnostics(for: instructions)
                .first(where: \.isNestedOverlap),
            file: file,
            line: line
        )
    }

    private func stringArgument(
        _ key: String,
        in toolCall: ToolCall,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> String {
        let data = try XCTUnwrap(toolCall.argumentsJSON.data(using: .utf8), file: file, line: line)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: String],
            file: file,
            line: line
        )
        return try XCTUnwrap(object[key], file: file, line: line)
    }
}
