import XCTest
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
        XCTAssertEqual(activity.tools.map(\.title), ["Shell command"])
        XCTAssertEqual(activity.tools.first?.statusLabel, ToolCardStatus.done.rawValue)
        XCTAssertEqual(activity.artifacts.map(\.label), ["quillcode-activity.png"])
        XCTAssertEqual(activity.sources.map(\.title), ["rules.md", "Prefers concise diffs"])
        XCTAssertEqual(activity.sources.first?.detail, ".quillcode/rules.md · Scope: whole project")
        XCTAssertEqual(activity.sources.first?.actions.map(\.title), ["Open", "Edit"])
        XCTAssertEqual(activity.sources.first?.actions.map(\.commandID), [
            "activity-source-open:.quillcode/rules.md",
            "activity-source-edit:.quillcode/rules.md"
        ])
        XCTAssertEqual(activity.sources.first?.actions.map(\.kind), ["open", "edit"])
        XCTAssertEqual(activity.finalAnswer, "Output: quill")
        XCTAssertEqual(activity.planItems.map(\.title), [
            "Understand request",
            "Load context",
            "Use tools",
            "Review results",
            "Answer user"
        ])
        XCTAssertEqual(activity.planItems.map(\.statusLabel), ["Done", "Done", "Done", "Done", "Done"])
        XCTAssertTrue(activity.planItems.contains { $0.title == "Use tools" && $0.detail.contains("Shell command") })
        XCTAssertTrue(activity.handoffSummary?.contains("Thread: Run command") == true)
        XCTAssertTrue(activity.handoffSummary?.contains("Latest request: run whoami") == true)
        XCTAssertTrue(activity.handoffSummary?.contains("Tools: 1 tool (Shell command)") == true)
        XCTAssertTrue(activity.handoffSummary?.contains("Artifacts: 1 artifact (quillcode-activity.png)") == true)
        XCTAssertTrue(activity.recentSteps.contains { $0.title == "Tool completed" && $0.statusLabel == "Done" })
        XCTAssertEqual(activity.sections.map(\.kind), [.plan, .recent, .subagents, .handoff, .tools, .sources, .artifacts, .latestAnswer])
        XCTAssertEqual(activity.sections.first { $0.kind == .plan }?.items.map(\.title), activity.planItems.map(\.title))
        XCTAssertEqual(activity.sections.first { $0.kind == .plan }?.countLabel, "5 items")
        XCTAssertEqual(activity.sections.first { $0.kind == .subagents }?.countLabel, "0 items")
        XCTAssertEqual(activity.sections.first { $0.kind == .handoff }?.bodyText, activity.handoffSummary)
        XCTAssertEqual(activity.sections.first { $0.kind == .handoff }?.countLabel, "1 summary")
        XCTAssertEqual(activity.sections.first { $0.kind == .tools }?.items.map(\.title), ["Shell command"])
        XCTAssertEqual(activity.sections.first { $0.kind == .artifacts }?.artifacts.map(\.label), ["quillcode-activity.png"])
        XCTAssertEqual(activity.sections.first { $0.kind == .latestAnswer }?.bodyText, "Output: quill")
        XCTAssertEqual(activity.sections.first { $0.kind == .tools }?.toggleCommandID, "activity-toggle-section:tools")
    }

    func testActivitySurfaceShowsContextSummaryProgressNotices() throws {
        let fallbackOutcome = WorkspaceContextSummaryOutcome(
            summaryOverride: nil,
            source: .deterministicFallback,
            errorDescription: "summary timeout"
        )
        let thread = ChatThread(
            title: "Large thread",
            messages: [.init(role: .user, content: "compact this")],
            events: [
                .init(
                    kind: .notice,
                    summary: WorkspaceContextSummaryTelemetryPlanner.sourceStartSummary(purpose: .compact)
                ),
                .init(
                    kind: .notice,
                    summary: WorkspaceContextSummaryTelemetryPlanner.sourceFinishedSummary(
                        outcome: fallbackOutcome,
                        purpose: .compact
                    )
                )
            ]
        )
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(threads: [thread], selectedThreadID: thread.id),
            activity: ActivityState(isVisible: true)
        )

        let activity = model.surface().activity
        let contextSection = try XCTUnwrap(activity.sections.first { $0.kind == .context })

        XCTAssertEqual(activity.contextItems.map(\.title), [
            "Compacting context",
            "Deterministic fallback used"
        ])
        XCTAssertEqual(activity.contextItems.map(\.statusLabel), ["Running", "Checked"])
        XCTAssertEqual(contextSection.title, "Context")
        XCTAssertEqual(contextSection.itemTestID, "activity-context")
        XCTAssertEqual(contextSection.countLabel, "2 items")
    }

    func testActivitySurfaceShowsE2EPrivateSummaryAsDoneNotFallback() throws {
        // An E2E-routed thread summarizes locally BY DESIGN. Both the source-thread notice (matched by
        // string) and the continuation telemetry must render it as a completed, privacy-explained step
        // — never as the "fallback used / Checked" degraded outcome, and never dropped entirely.
        let e2eOutcome = WorkspaceContextSummaryOutcome(
            summaryOverride: "Local summary of the private chat.",
            source: .e2eDeterministic
        )
        let thread = ChatThread(
            title: "E2E thread",
            messages: [.init(role: .user, content: "compact this")],
            events: [
                // The REAL sequence starts with a start notice. It persists forever alongside the
                // finish notice, so it must not claim a TrustedRouter call that never happens.
                .init(
                    kind: .notice,
                    summary: WorkspaceContextSummaryTelemetryPlanner.sourceStartSummary(
                        purpose: .compact,
                        isLocal: true
                    )
                ),
                .init(
                    kind: .notice,
                    summary: WorkspaceContextSummaryTelemetryPlanner.sourceFinishedSummary(
                        outcome: e2eOutcome,
                        purpose: .compact
                    )
                ),
                WorkspaceContextSummaryTelemetryPlanner.continuationEvent(
                    outcome: e2eOutcome,
                    sourceTitle: "E2E thread",
                    purpose: .compact
                )
            ]
        )
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(threads: [thread], selectedThreadID: thread.id),
            activity: ActivityState(isVisible: true)
        )

        let activity = model.surface().activity

        XCTAssertEqual(activity.contextItems.map(\.title), [
            "Compacting context",
            "Compacted privately",
            "Context compacted privately"
        ], "every notice must still render — an unmatched summary string would drop it entirely")
        XCTAssertEqual(
            activity.contextItems.map(\.statusLabel),
            ["Running", "Done", "Done"],
            "a deliberate private summary is done, not the 'Checked' degraded-fallback state"
        )
        XCTAssertFalse(
            activity.contextItems.contains { $0.detail.contains("TrustedRouter") },
            "an E2E thread never calls the auxiliary model — no row may claim it asked TrustedRouter"
        )
        let continuationDetail = try XCTUnwrap(activity.contextItems.last).detail
        XCTAssertTrue(
            continuationDetail.contains("Local summary (end-to-end encrypted)"),
            continuationDetail
        )
        XCTAssertFalse(
            activity.contextItems.contains { $0.detail.contains("Fallback reason") },
            "nothing failed, so no fallback reason may be shown"
        )
    }

    func testActivitySurfaceShowsContextSummaryContinuationTelemetry() throws {
        let modelOutcome = WorkspaceContextSummaryOutcome(
            summaryOverride: "Keep the current repo and validation details.",
            source: .model
        )
        let thread = ChatThread(
            title: "Compact continuation",
            messages: [.init(role: .assistant, content: "Context compacted.")],
            events: [
                WorkspaceContextSummaryTelemetryPlanner.continuationEvent(
                    outcome: modelOutcome,
                    sourceTitle: "Large thread",
                    purpose: .compact
                )
            ]
        )
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(threads: [thread], selectedThreadID: thread.id),
            activity: ActivityState(isVisible: true)
        )

        let activity = model.surface().activity
        let contextItem = try XCTUnwrap(activity.contextItems.first)
        let contextSection = try XCTUnwrap(activity.sections.first { $0.kind == .context })

        XCTAssertEqual(contextItem.title, "Context compacted")
        XCTAssertEqual(contextItem.detail, "Model summary · from Large thread · 45 characters")
        XCTAssertEqual(contextItem.statusLabel, "Done")
        XCTAssertEqual(contextSection.items, [contextItem])
        XCTAssertEqual(activity.sections.map(\.kind).prefix(3), [.plan, .context, .recent])
    }

}
