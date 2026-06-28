import XCTest
import QuillCodeAgent
import QuillCodeCore
import QuillCodeTools
@testable import QuillCodeApp

@MainActor
final class WorkspaceActivityIntegrationTests: XCTestCase {
    func testActivitySurfaceSummarizesThreadToolsSourcesAndArtifacts() throws {
        let instruction = ProjectInstruction(
            path: ".quillcode/rules.md",
            title: "rules.md",
            content: "Use the repo patterns.",
            byteCount: 22
        )
        let memory = MemoryNote(
            id: "global-note",
            scope: .global,
            title: "Prefers concise diffs",
            content: "Keep changes reviewable.",
            relativePath: "preferences.md",
            byteCount: 24
        )
        let call = ToolCall(
            id: "tool-activity",
            name: ToolDefinition.shellRun.name,
            argumentsJSON: #"{"cmd":"whoami"}"#
        )
        let result = ToolResult(
            ok: true,
            stdout: "quill\n",
            artifacts: ["/tmp/quillcode-activity.png"]
        )
        let thread = ChatThread(
            title: "Run command",
            messages: [
                .init(role: .user, content: "run whoami"),
                .init(role: .assistant, content: "Output:\nquill")
            ],
            events: [
                .init(kind: .message, summary: "run whoami"),
                .init(kind: .toolQueued, summary: "host.shell.run queued", payloadJSON: try JSONHelpers.encodePretty(call)),
                .init(kind: .toolRunning, summary: "host.shell.run running"),
                .init(kind: .toolCompleted, summary: "host.shell.run completed", payloadJSON: try JSONHelpers.encodePretty(result)),
                .init(kind: .message, summary: "Output:\nquill")
            ],
            instructions: [instruction],
            memories: [memory]
        )
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(
                threads: [thread],
                selectedThreadID: thread.id
            ),
            activity: ActivityState(isVisible: true)
        )

        let activity = model.surface().activity

        XCTAssertTrue(activity.isVisible)
        XCTAssertEqual(activity.taskTitle, "run whoami")
        XCTAssertEqual(activity.tools.map(\.title), [ToolDefinition.shellRun.name])
        XCTAssertEqual(activity.tools.first?.statusLabel, ToolCardStatus.done.rawValue)
        XCTAssertEqual(activity.artifacts.map(\.label), ["quillcode-activity.png"])
        XCTAssertEqual(activity.sources.map(\.title), ["rules.md", "Prefers concise diffs"])
        XCTAssertEqual(activity.sources.first?.detail, ".quillcode/rules.md · Scope: whole project")
        XCTAssertEqual(activity.finalAnswer, "Output: quill")
        XCTAssertEqual(activity.planItems.map(\.title), [
            "Understand request",
            "Load context",
            "Use tools",
            "Review results",
            "Answer user"
        ])
        XCTAssertEqual(activity.planItems.map(\.statusLabel), ["Done", "Done", "Done", "Done", "Done"])
        XCTAssertTrue(activity.planItems.contains { $0.title == "Use tools" && $0.detail.contains(ToolDefinition.shellRun.name) })
        XCTAssertTrue(activity.handoffSummary?.contains("Thread: Run command") == true)
        XCTAssertTrue(activity.handoffSummary?.contains("Latest request: run whoami") == true)
        XCTAssertTrue(activity.handoffSummary?.contains("Tools: 1 tool (\(ToolDefinition.shellRun.name))") == true)
        XCTAssertTrue(activity.handoffSummary?.contains("Artifacts: 1 artifact (quillcode-activity.png)") == true)
        XCTAssertTrue(activity.recentSteps.contains { $0.title == "Tool completed" && $0.statusLabel == "Done" })
        XCTAssertEqual(activity.sections.map(\.kind), [.plan, .recent, .subagents, .handoff, .tools, .sources, .artifacts, .latestAnswer])
        XCTAssertEqual(activity.sections.first { $0.kind == .plan }?.items.map(\.title), activity.planItems.map(\.title))
        XCTAssertEqual(activity.sections.first { $0.kind == .plan }?.countLabel, "5 items")
        XCTAssertEqual(activity.sections.first { $0.kind == .subagents }?.countLabel, "0 items")
        XCTAssertEqual(activity.sections.first { $0.kind == .handoff }?.bodyText, activity.handoffSummary)
        XCTAssertEqual(activity.sections.first { $0.kind == .handoff }?.countLabel, "1 summary")
        XCTAssertEqual(activity.sections.first { $0.kind == .tools }?.items.map(\.title), [ToolDefinition.shellRun.name])
        XCTAssertEqual(activity.sections.first { $0.kind == .artifacts }?.artifacts.map(\.label), ["quillcode-activity.png"])
        XCTAssertEqual(activity.sections.first { $0.kind == .latestAnswer }?.bodyText, "Output: quill")
        XCTAssertEqual(activity.sections.first { $0.kind == .tools }?.toggleCommandID, "activity-toggle-section:tools")
    }

    func testActivitySourcesSurfaceInstructionDiagnostics() throws {
        let instructions = [
            ProjectInstruction(path: "AGENTS.md", title: "AGENTS.md", content: "Use Swift.", byteCount: 10),
            ProjectInstruction(path: ".quillcode/rules.md", title: "rules.md", content: "Use tests.", byteCount: 10),
            ProjectInstruction(path: "Sources/Feature/AGENTS.md", title: "Feature AGENTS.md", content: "Use feature tests.", byteCount: 18, wasTruncated: true)
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
        let instructions = [
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
        let conflict = try XCTUnwrap(activity.sources.first { $0.statusLabel == "conflict" })
        let reviewSection = try XCTUnwrap(activity.sections.first { $0.kind == .instructionReview })

        XCTAssertEqual(conflict.title, "Conflicting instruction intent")
        XCTAssertEqual(
            conflict.detail,
            "Tests: AGENTS.md says require; Sources/Feature/AGENTS.md says avoid"
        )
        XCTAssertEqual(reviewSection.title, "Instruction Review")
        XCTAssertEqual(reviewSection.countLabel, "1 issue")
        XCTAssertEqual(reviewSection.items, [conflict])
        XCTAssertEqual(
            activity.sections.map(\.kind),
            [.plan, .recent, .subagents, .handoff, .tools, .instructionReview, .sources, .artifacts]
        )
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

    func testActivitySurfacePrefersModelAuthoredPlan() throws {
        let update = AgentPlanUpdate(
            explanation: "The model is planning the work directly.",
            plan: [
                AgentPlanItem(step: "Inspect current state", status: .completed),
                AgentPlanItem(step: "Apply focused change", status: .inProgress, detail: "Keep the diff small."),
                AgentPlanItem(step: "Run validation", status: .pending)
            ]
        )
        let result = ToolResult(ok: true, stdout: try JSONHelpers.encodePretty(update))
        let thread = ChatThread(
            title: "Plan work",
            messages: [.init(role: .user, content: "plan the work")],
            events: [
                .init(
                    kind: .toolCompleted,
                    summary: "\(ToolDefinition.planUpdate.name) completed",
                    payloadJSON: try JSONHelpers.encodePretty(result)
                )
            ]
        )
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(threads: [thread], selectedThreadID: thread.id),
            activity: ActivityState(isVisible: true)
        )

        let activity = model.surface().activity

        XCTAssertEqual(activity.planItems.map(\.title), [
            "Inspect current state",
            "Apply focused change",
            "Run validation"
        ])
        XCTAssertEqual(activity.planItems.map(\.statusLabel), ["Done", "Running", "Pending"])
        XCTAssertEqual(activity.planItems[0].detail, "The model is planning the work directly.")
        XCTAssertEqual(activity.planItems[1].detail, "Keep the diff small.")
        XCTAssertEqual(activity.sections.first { $0.kind == .plan }?.countLabel, "3 items")
        XCTAssertEqual(activity.sections.first { $0.kind == .plan }?.items.map(\.kind), [
            "authored-plan",
            "authored-plan",
            "authored-plan"
        ])
    }

    func testActivitySurfacePrefersModelAuthoredHandoffSummary() throws {
        let update = AgentHandoffUpdate(
            summary: "The branch is ready for final validation.",
            nextSteps: ["Run focused tests", "Open a PR"]
        )
        let result = ToolResult(ok: true, stdout: try JSONHelpers.encodePretty(update))
        let thread = ChatThread(
            title: "Handoff work",
            messages: [.init(role: .user, content: "summarize for handoff")],
            events: [
                .init(
                    kind: .toolCompleted,
                    summary: "\(ToolDefinition.handoffUpdate.name) completed",
                    payloadJSON: try JSONHelpers.encodePretty(result)
                )
            ]
        )
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(threads: [thread], selectedThreadID: thread.id),
            activity: ActivityState(isVisible: true)
        )

        let activity = model.surface().activity

        XCTAssertEqual(
            activity.handoffSummary,
            """
            The branch is ready for final validation.
            Next steps:
            1. Run focused tests
            2. Open a PR
            """
        )
        XCTAssertEqual(activity.sections.first { $0.kind == .handoff }?.bodyText, activity.handoffSummary)
        XCTAssertEqual(activity.sections.first { $0.kind == .handoff }?.countLabel, "1 summary")
    }

    func testActivityCommandTogglesActivityPane() {
        let model = QuillCodeWorkspaceModel()

        XCTAssertFalse(model.surface().activity.isVisible)
        XCTAssertTrue(model.runWorkspaceCommand("toggle-activity", workspaceRoot: URL(fileURLWithPath: "/tmp")))
        XCTAssertTrue(model.surface().activity.isVisible)
    }

    func testActivitySectionToggleCollapsesSharedSurfaceSection() throws {
        let call = ToolCall(
            id: "tool-activity",
            name: ToolDefinition.shellRun.name,
            argumentsJSON: #"{"cmd":"whoami"}"#
        )
        let result = ToolResult(ok: true, stdout: "quill\n")
        let thread = ChatThread(
            title: "Run command",
            messages: [.init(role: .user, content: "run whoami")],
            events: [
                .init(kind: .toolQueued, summary: "host.shell.run queued", payloadJSON: try JSONHelpers.encodePretty(call)),
                .init(kind: .toolCompleted, summary: "host.shell.run completed", payloadJSON: try JSONHelpers.encodePretty(result))
            ]
        )
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(threads: [thread], selectedThreadID: thread.id),
            activity: ActivityState(isVisible: true)
        )

        XCTAssertEqual(model.surface().activity.sections.first { $0.kind == .tools }?.isCollapsed, false)
        XCTAssertTrue(model.runWorkspaceCommand("activity-toggle-section:tools", workspaceRoot: URL(fileURLWithPath: "/tmp")))
        XCTAssertEqual(model.surface().activity.sections.first { $0.kind == .tools }?.isCollapsed, true)
        XCTAssertTrue(model.surface().activity.isVisible)
        XCTAssertTrue(model.runWorkspaceCommand("activity-toggle-section:handoff", workspaceRoot: URL(fileURLWithPath: "/tmp")))
        XCTAssertEqual(model.surface().activity.sections.first { $0.kind == .handoff }?.isCollapsed, true)
        XCTAssertTrue(model.runWorkspaceCommand("activity-toggle-section:plan", workspaceRoot: URL(fileURLWithPath: "/tmp")))
        XCTAssertEqual(model.surface().activity.sections.first { $0.kind == .plan }?.isCollapsed, true)
        XCTAssertTrue(model.runWorkspaceCommand("activity-toggle-section:tools", workspaceRoot: URL(fileURLWithPath: "/tmp")))
        XCTAssertEqual(model.surface().activity.sections.first { $0.kind == .tools }?.isCollapsed, false)
        XCTAssertFalse(model.runWorkspaceCommand("activity-toggle-section:not-real", workspaceRoot: URL(fileURLWithPath: "/tmp")))
    }

    func testPlanUpdateToolRecordsNormalizedActivityPlan() throws {
        let model = QuillCodeWorkspaceModel(activity: ActivityState(isVisible: true))
        _ = model.newChat()
        let update = AgentPlanUpdate(
            explanation: "  Keep the plan visible while work proceeds.  ",
            plan: [
                AgentPlanItem(step: "  Inspect state  ", status: .completed),
                AgentPlanItem(step: "Implement change", status: .inProgress, detail: "  One reviewable slice.  "),
                AgentPlanItem(step: "Validate and summarize", status: .pending)
            ]
        )
        let call = ToolCall(
            name: ToolDefinition.planUpdate.name,
            argumentsJSON: try JSONHelpers.encodePretty(update)
        )

        let result = model.runToolCall(call, workspaceRoot: try makeTempDirectory())
        let decoded = try JSONHelpers.decode(AgentPlanUpdate.self, from: result.stdout)

        XCTAssertTrue(result.ok, result.error ?? "")
        XCTAssertEqual(decoded.explanation, "Keep the plan visible while work proceeds.")
        XCTAssertEqual(decoded.plan.map(\.step), ["Inspect state", "Implement change", "Validate and summarize"])
        XCTAssertEqual(model.selectedThread?.events.last?.summary, "\(ToolDefinition.planUpdate.name) completed")
        XCTAssertEqual(model.surface().activity.planItems.map(\.title), [
            "Inspect state",
            "Implement change",
            "Validate and summarize"
        ])
        XCTAssertEqual(model.surface().activity.planItems.map(\.statusLabel), ["Done", "Running", "Pending"])
        XCTAssertEqual(model.surface().activity.planItems[1].detail, "One reviewable slice.")
    }

    func testPlanUpdateToolRejectsMultipleRunningSteps() throws {
        let model = QuillCodeWorkspaceModel()
        _ = model.newChat()
        let update = AgentPlanUpdate(
            plan: [
                AgentPlanItem(step: "First", status: .inProgress),
                AgentPlanItem(step: "Second", status: .inProgress)
            ]
        )
        let call = ToolCall(
            name: ToolDefinition.planUpdate.name,
            argumentsJSON: try JSONHelpers.encodePretty(update)
        )

        let result = model.runToolCall(call, workspaceRoot: try makeTempDirectory())

        XCTAssertFalse(result.ok)
        XCTAssertEqual(result.error, "Plan update can have at most one in_progress step.")
        XCTAssertEqual(model.root.topBar.agentStatus, "Failed")
    }

    func testHandoffUpdateToolRecordsNormalizedActivitySummary() throws {
        let model = QuillCodeWorkspaceModel(activity: ActivityState(isVisible: true))
        _ = model.newChat()
        let update = AgentHandoffUpdate(
            summary: "  Current state:\n\n  implementation is ready.  ",
            nextSteps: ["  Run tests  ", "Open PR"]
        )
        let call = ToolCall(
            name: ToolDefinition.handoffUpdate.name,
            argumentsJSON: try JSONHelpers.encodePretty(update)
        )

        let result = model.runToolCall(call, workspaceRoot: try makeTempDirectory())
        let decoded = try JSONHelpers.decode(AgentHandoffUpdate.self, from: result.stdout)

        XCTAssertTrue(result.ok, result.error ?? "")
        XCTAssertEqual(decoded.summary, "Current state:\nimplementation is ready.")
        XCTAssertEqual(decoded.nextSteps, ["Run tests", "Open PR"])
        XCTAssertEqual(model.selectedThread?.events.last?.summary, "\(ToolDefinition.handoffUpdate.name) completed")
        XCTAssertTrue(model.surface().activity.handoffSummary?.contains("Current state") == true)
        XCTAssertTrue(model.surface().activity.handoffSummary?.contains("1. Run tests") == true)
    }

    func testHandoffUpdateToolRejectsEmptySummary() throws {
        let model = QuillCodeWorkspaceModel()
        _ = model.newChat()
        let call = ToolCall(
            name: ToolDefinition.handoffUpdate.name,
            argumentsJSON: try JSONHelpers.encodePretty(AgentHandoffUpdate(summary: "  "))
        )

        let result = model.runToolCall(call, workspaceRoot: try makeTempDirectory())

        XCTAssertFalse(result.ok)
        XCTAssertEqual(result.error, "Handoff update requires a non-empty summary.")
        XCTAssertEqual(model.root.topBar.agentStatus, "Failed")
    }

    func testSubagentProgressToolRecordsVisibleActivityItems() throws {
        let model = QuillCodeWorkspaceModel(activity: ActivityState(isVisible: true))
        _ = model.newChat()
        let update = SubagentProgressUpdate(
            objective: "  Split the validation pass across specialists.  ",
            subagents: [
                SubagentProgressItem(
                    name: "  Explorer  ",
                    role: "  Map the affected files.  ",
                    status: .completed,
                    summary: "  Activity and tool routing found.  "
                ),
                SubagentProgressItem(
                    name: "Verifier",
                    role: "Run focused checks.",
                    status: .running,
                    summary: "Waiting on Swift tests."
                )
            ]
        )
        let call = ToolCall(
            name: ToolDefinition.subagentsUpdate.name,
            argumentsJSON: try JSONHelpers.encodePretty(update)
        )

        let result = model.runToolCall(call, workspaceRoot: try makeTempDirectory())
        let decoded = try JSONHelpers.decode(SubagentProgressUpdate.self, from: result.stdout)
        let subagentSection = try XCTUnwrap(model.surface().activity.sections.first { $0.kind == .subagents })

        XCTAssertTrue(result.ok, result.error ?? "")
        XCTAssertEqual(decoded.objective, "Split the validation pass across specialists.")
        XCTAssertEqual(decoded.subagents.map(\.name), ["Explorer", "Verifier"])
        XCTAssertEqual(model.selectedThread?.events.last?.summary, "\(ToolDefinition.subagentsUpdate.name) completed")
        XCTAssertEqual(model.surface().activity.subagents.map(\.title), ["Explorer", "Verifier"])
        XCTAssertEqual(model.surface().activity.subagents.map(\.statusLabel), ["Done", "Running"])
        XCTAssertEqual(model.surface().activity.subagents.map(\.kind), ["subagent", "subagent"])
        XCTAssertTrue(model.surface().activity.subagents[0].detail.contains("Goal: Split the validation pass"))
        XCTAssertEqual(subagentSection.countLabel, "2 items")
        XCTAssertEqual(subagentSection.itemTestID, "activity-subagent")
    }

    func testSubagentProgressToolRejectsEmptySubagents() throws {
        let model = QuillCodeWorkspaceModel()
        _ = model.newChat()
        let call = ToolCall(
            name: ToolDefinition.subagentsUpdate.name,
            argumentsJSON: try JSONHelpers.encodePretty(SubagentProgressUpdate(subagents: []))
        )

        let result = model.runToolCall(call, workspaceRoot: try makeTempDirectory())

        XCTAssertFalse(result.ok)
        XCTAssertEqual(result.error, "Subagent progress requires at least one subagent with a name and role.")
        XCTAssertEqual(model.root.topBar.agentStatus, "Failed")
    }
}
