import XCTest
import QuillCodeCore
@testable import QuillCodeApp

@MainActor
final class WorkspaceActivityInstructionIntegrationTests: XCTestCase {
    func testActivitySourcesSurfaceInstructionDiagnostics() throws {
        let instructions = [
            ProjectInstruction(path: "AGENTS.md", title: "AGENTS.md", content: "Use Swift.", byteCount: 10),
            ProjectInstruction(path: ".quillcode/rules.md", title: "rules.md", content: "Use tests.", byteCount: 10),
            ProjectInstruction(
                path: "Sources/Feature/AGENTS.md",
                title: "Feature AGENTS.md",
                content: "Use feature tests.",
                byteCount: 18,
                wasTruncated: true
            )
        ]
        let thread = ChatThread(
            title: "Inspect rules",
            messages: [.init(role: .user, content: "what rules apply?")],
            instructions: instructions
        )
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(threads: [thread], selectedThreadID: thread.id),
            activity: ActivityState(isVisible: true)
        )

        let activity = model.surface().activity

        XCTAssertEqual(activity.sources.map(\.title), [
            "AGENTS.md",
            "rules.md",
            "AGENTS.md",
            "Shared instruction scope",
            "Nested instruction override"
        ])
        XCTAssertEqual(activity.sources[2].statusLabel, "truncated")
        XCTAssertEqual(activity.sources[3].detail, "whole project: AGENTS.md, .quillcode/rules.md")
        XCTAssertEqual(
            activity.sources[4].detail,
            "Sources/Feature/** from Sources/Feature/AGENTS.md may override AGENTS.md, .quillcode/rules.md"
        )
        XCTAssertEqual(activity.sections.first { $0.kind == .sources }?.countLabel, "5 items")
    }

    func testActivitySourcesSurfaceInstructionSemanticConflictDiagnostics() throws {
        let fixture = try instructionConflictFixture()
        let thread = ChatThread(
            title: "Inspect conflicts",
            messages: [.init(role: .user, content: "what rules apply?")],
            instructions: fixture.instructions
        )
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(threads: [thread], selectedThreadID: thread.id),
            activity: ActivityState(isVisible: true)
        )

        let activity = model.surface().activity
        let conflict = try XCTUnwrap(activity.sources.first { $0.statusLabel == "conflict" })
        let reviewSection = try XCTUnwrap(activity.sections.first { $0.kind == .instructionReview })

        XCTAssertEqual(conflict.title, "Conflicting instruction intent")
        XCTAssertEqual(conflict.detail, "Tests: AGENTS.md says require; Sources/Feature/AGENTS.md says avoid")
        XCTAssertEqual(reviewSection.title, "Instruction Review")
        XCTAssertEqual(reviewSection.countLabel, "1 issue")
        XCTAssertEqual(reviewSection.items, [conflict])
        XCTAssertEqual(conflict.actions.map(\.title), ["Open Source", "Edit Source", "Resolve", "Dismiss"])
        XCTAssertEqual(conflict.actions.map(\.kind), ["open", "edit", "resolve", "dismiss"])
        XCTAssertEqual(
            conflict.actions.map(\.commandID),
            [
                "activity-source-open-line:1:AGENTS.md",
                "activity-source-edit-line:1:AGENTS.md",
                "activity-instruction-resolve:\(fixture.diagnosticID)",
                "activity-instruction-dismiss:\(fixture.diagnosticID)"
            ]
        )
        XCTAssertEqual(
            activity.sections.map(\.kind),
            [.plan, .recent, .subagents, .handoff, .tools, .instructionReview, .sources, .artifacts]
        )
    }

    func testActivitySourcesHideDismissedInstructionDiagnostics() throws {
        let fixture = try instructionConflictFixture()
        let thread = ChatThread(
            title: "Inspect conflicts",
            messages: [.init(role: .user, content: "what rules apply?")],
            instructions: fixture.instructions
        )
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(threads: [thread], selectedThreadID: thread.id),
            activity: ActivityState(
                isVisible: true,
                dismissedInstructionDiagnosticIDs: [fixture.diagnosticID]
            )
        )

        let activity = model.surface().activity

        XCTAssertFalse(activity.sources.contains { $0.id == fixture.diagnosticID })
        XCTAssertNil(activity.sections.first { $0.kind == .instructionReview })
        let sourceItems = try XCTUnwrap(activity.sections.first { $0.kind == .sources }?.items)
        XCTAssertFalse(sourceItems.contains { $0.title == "Conflicting instruction intent" })
        XCTAssertFalse(sourceItems.contains { $0.statusLabel == "conflict" })
    }

    func testActivitySourcesHideProjectDismissedInstructionDiagnostics() throws {
        let fixture = try instructionConflictFixture()
        var project = ProjectRef(
            name: "QuillCode",
            path: "/tmp/quillcode",
            instructions: fixture.instructions
        )
        project.dismissInstructionDiagnostic(id: fixture.diagnosticID)
        let thread = ChatThread(
            title: "Inspect conflicts",
            projectID: project.id,
            messages: [.init(role: .user, content: "what rules apply?")],
            instructions: fixture.instructions
        )
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(
                projects: [project],
                selectedProjectID: project.id,
                threads: [thread],
                selectedThreadID: thread.id
            ),
            activity: ActivityState(isVisible: true)
        )

        let activity = model.surface().activity

        XCTAssertFalse(activity.sources.contains { $0.id == fixture.diagnosticID })
        XCTAssertNil(activity.sections.first { $0.kind == .instructionReview })
    }

    func testActivitySourcesShowProjectResolvedInstructionDiagnosticsWhenReintroduced() throws {
        let fixture = try instructionConflictFixture()
        var project = ProjectRef(
            name: "QuillCode",
            path: "/tmp/quillcode",
            instructions: fixture.instructions
        )
        project.resolveInstructionDiagnostic(id: fixture.diagnosticID)
        let thread = ChatThread(
            title: "Inspect conflicts",
            projectID: project.id,
            messages: [.init(role: .user, content: "what rules apply?")],
            instructions: fixture.instructions
        )
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(
                projects: [project],
                selectedProjectID: project.id,
                threads: [thread],
                selectedThreadID: thread.id
            ),
            activity: ActivityState(isVisible: true)
        )

        let activity = model.surface().activity

        XCTAssertTrue(activity.sources.contains { $0.id == fixture.diagnosticID })
        XCTAssertNotNil(activity.sections.first { $0.kind == .instructionReview })
    }

    func testActivitySourcesPrioritizeConflictDiagnosticsWithinSourceCap() throws {
        let instructions = [
            ProjectInstruction(path: "AGENTS.md", title: "AGENTS.md", content: "Always run tests.", byteCount: 17),
            ProjectInstruction(path: ".quillcode/rules.md", title: "rules.md", content: "Use Swift.", byteCount: 10),
            ProjectInstruction(path: ".quillcode/instructions.md", title: "instructions.md", content: "Use small diffs.", byteCount: 15),
            ProjectInstruction(path: "Sources/AGENTS.md", title: "Sources AGENTS.md", content: "Use source patterns.", byteCount: 20),
            ProjectInstruction(path: "Sources/Feature/AGENTS.md", title: "Feature AGENTS.md", content: "Do not run tests.", byteCount: 17)
        ]
        let thread = ChatThread(
            title: "Inspect conflicts",
            messages: [.init(role: .user, content: "what rules apply?")],
            instructions: instructions
        )
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(threads: [thread], selectedThreadID: thread.id),
            activity: ActivityState(isVisible: true)
        )

        let activity = model.surface().activity
        let reviewSection = try XCTUnwrap(activity.sections.first { $0.kind == .instructionReview })

        XCTAssertTrue(activity.sources.filter { $0.kind == "instruction-diagnostic" }.prefix(4).contains { $0.statusLabel == "conflict" })
        XCTAssertEqual(reviewSection.items.count, 1)
        XCTAssertEqual(reviewSection.items.first?.statusLabel, "conflict")
    }

    private func instructionConflictFixture(
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> (instructions: [ProjectInstruction], diagnosticID: String) {
        let rootContent = "Always run tests before final answers."
        let featureContent = "Do not run tests for feature changes."
        let instructions = [
            ProjectInstruction(
                path: "AGENTS.md",
                title: "AGENTS.md",
                content: rootContent,
                byteCount: rootContent.utf8.count
            ),
            ProjectInstruction(
                path: "Sources/Feature/AGENTS.md",
                title: "Feature AGENTS.md",
                content: featureContent,
                byteCount: featureContent.utf8.count
            )
        ]
        let diagnosticID = try XCTUnwrap(
            ProjectInstructionDiagnosticsBuilder
                .diagnostics(for: instructions)
                .first { $0.statusLabel == "conflict" }?
                .id,
            file: file,
            line: line
        )
        return (instructions, diagnosticID)
    }
}
