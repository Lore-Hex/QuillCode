import XCTest
import QuillCodeCore
import QuillCodeSafety
@testable import QuillCodeApp

final class WorkspaceTranscriptSurfaceBuilderTests: XCTestCase {
    func testPlanModeBlockSurfacesAnApprovableToolCard() async throws {
        // Regression for the missing-approve-button bug: a plan-mode block must stay
        // APPROVABLE. The verdict is taken from the REAL reviewer and fed into the request the
        // exact way AgentToolStepRunner.appendBlockedReview builds it, so this fails if the
        // .plan arm ever returns `.deny` (the hard, button-suppressing signal for `rm -rf /`).
        let call = ToolCall(
            id: "plan-block-1",
            name: ToolDefinition.shellRun.name,
            argumentsJSON: ToolArguments.json(["cmd": "touch a.txt"])
        )
        let review = await StaticSafetyReviewer().review(.init(
            mode: .plan,
            userMessage: "make the change",
            toolCall: call,
            toolDefinition: ToolDefinition.shellRun,
            recentMessages: []
        ))
        let request = ApprovalRequest(
            id: "plan-approval-1",
            toolCall: call,
            toolDefinition: ToolDefinition.shellRun,
            reason: review.rationale,
            recommendedVerdict: review.verdict
        )
        let thread = ChatThread(mode: .plan, events: [
            ThreadEvent(kind: .toolQueued, summary: "queued", payloadJSON: try JSONHelpers.encodePretty(call)),
            ThreadEvent(
                kind: .approvalRequested,
                summary: "plan block",
                payloadJSON: try JSONHelpers.encodePretty(request)
            )
        ])

        let card = try XCTUnwrap(
            WorkspaceTranscriptSurfaceBuilder(thread: thread).timelineItems().compactMap(\.toolCard).first
        )
        XCTAssertTrue(
            card.actions.contains { $0.kind == .approve },
            "a plan-blocked tool must surface an approve button; got \(card.actions.map(\.title))"
        )
    }

    func testThinkingSurfaceShowsWhileSendingAndKeepsTraceCollapsedByDefaultData() {
        let thread = ChatThread(events: [
            ThreadEvent(kind: .message, summary: "run tests"),
            ThreadEvent(kind: .notice, summary: "Streaming model response"),
            ThreadEvent(kind: .toolQueued, summary: "host.shell.run queued"),
            ThreadEvent(kind: .toolRunning, summary: "host.shell.run running")
        ])

        let thinking = WorkspaceTranscriptThinkingSurfaceBuilder(
            thread: thread,
            composer: ComposerState(isSending: true),
            agentStatus: TopBarAgentStatusLabel.running
        ).surface()

        XCTAssertEqual(thinking?.id, "thinking-\(thread.id.uuidString)")
        XCTAssertEqual(thinking?.title, "Thinking")
        XCTAssertEqual(thinking?.subtitle, "Running: host.shell.run running")
        XCTAssertEqual(thinking?.traceTitle, "Trace")
        XCTAssertEqual(thinking?.traceLines, [
            "Streaming model response",
            "Queued: host.shell.run queued",
            "Running: host.shell.run running"
        ])
    }

    func testThinkingSurfaceStaysVisibleWhileAssistantDraftStreams() {
        let thread = ChatThread(messages: [
            ChatMessage(role: .user, content: "say hello"),
            ChatMessage(role: .assistant, content: "hel")
        ], events: [
            ThreadEvent(kind: .message, summary: "say hello"),
            ThreadEvent(kind: .notice, summary: "Streaming model response")
        ])

        let thinking = WorkspaceTranscriptThinkingSurfaceBuilder(
            thread: thread,
            composer: ComposerState(isSending: true),
            agentStatus: TopBarAgentStatusLabel.streaming
        ).surface()

        XCTAssertEqual(thinking?.title, "Streaming")
        XCTAssertEqual(thinking?.subtitle, "Streaming model response")
    }

    func testMessageSurfacesHideToolMessagesAndAttachFeedback() throws {
        let user = ChatMessage(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            role: .user,
            content: "run whoami"
        )
        let tool = ChatMessage(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            role: .tool,
            content: "quill"
        )
        let assistant = ChatMessage(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
            role: .assistant,
            content: "You are `quill`."
        )
        let feedback = MessageFeedback(messageID: assistant.id, value: .helpful)
        let thread = ChatThread(
            messages: [user, tool, assistant],
            events: [
                ThreadEvent(
                    kind: .messageFeedback,
                    summary: "helpful",
                    payloadJSON: try JSONHelpers.encodePretty(feedback)
                )
            ]
        )

        let messages = WorkspaceTranscriptSurfaceBuilder(thread: thread).messageSurfaces()

        XCTAssertEqual(messages.map(\.role), [.user, .assistant])
        XCTAssertNil(messages.first?.feedback)
        XCTAssertEqual(messages.last?.feedback, .helpful)
    }

    func testToolCardsCollapseToolLifecycleAndAttachArtifacts() throws {
        let call = ToolCall(
            id: "tool-call-1",
            name: ToolDefinition.fileWrite.name,
            argumentsJSON: ToolArguments.json(["path": "hello.txt", "content": "hello"])
        )
        let result = ToolResult(ok: true, stdout: "wrote hello.txt\n", artifacts: ["hello.txt"])
        let thread = ChatThread(events: [
            ThreadEvent(kind: .toolQueued, summary: "queued", payloadJSON: try JSONHelpers.encodePretty(call)),
            ThreadEvent(kind: .toolRunning, summary: "running"),
            ThreadEvent(kind: .toolCompleted, summary: "completed", payloadJSON: try JSONHelpers.encodePretty(result))
        ])

        let cards = WorkspaceTranscriptSurfaceBuilder(thread: thread).toolCards()

        XCTAssertEqual(cards.count, 1)
        XCTAssertEqual(cards[0].id, "tool-call-1")
        XCTAssertEqual(cards[0].title, ToolDefinition.fileWrite.name)
        XCTAssertEqual(cards[0].subtitle, "Completed · hello.txt")
        XCTAssertEqual(cards[0].status, .done)
        XCTAssertEqual(cards[0].inputJSON, call.argumentsJSON)
        XCTAssertEqual(cards[0].artifacts.map(\.label), ["hello.txt"])
    }

    func testTimelineFollowsThreadEventsAndAppendsUnmatchedMessages() throws {
        let user = ChatMessage(role: .user, content: "run whoami")
        let assistant = ChatMessage(role: .assistant, content: "You are `quill`.")
        let unmatchedAssistant = ChatMessage(role: .assistant, content: "One more note.")
        let call = ToolCall(
            id: "shell-1",
            name: ToolDefinition.shellRun.name,
            argumentsJSON: ToolArguments.json(["cmd": "whoami"])
        )
        let result = ToolResult(ok: true, stdout: "quill\n")
        let thread = ChatThread(
            messages: [user, assistant, unmatchedAssistant],
            events: [
                ThreadEvent(kind: .message, summary: user.content),
                ThreadEvent(kind: .toolQueued, summary: "queued", payloadJSON: try JSONHelpers.encodePretty(call)),
                ThreadEvent(kind: .toolCompleted, summary: "completed", payloadJSON: try JSONHelpers.encodePretty(result)),
                ThreadEvent(kind: .message, summary: assistant.content)
            ]
        )

        let timeline = WorkspaceTranscriptSurfaceBuilder(thread: thread).timelineItems()

        XCTAssertEqual(timeline.map(\.kind), [.message, .toolCard, .message, .message])
        XCTAssertEqual(timeline[0].message?.text, user.content)
        XCTAssertEqual(timeline[1].toolCard?.id, "shell-1")
        XCTAssertEqual(timeline[1].toolCard?.status, .done)
        XCTAssertEqual(timeline[1].toolCard?.subtitle, "Completed · whoami")
        XCTAssertEqual(timeline[2].message?.text, assistant.content)
        XCTAssertEqual(timeline[3].message?.text, unmatchedAssistant.content)
    }

    func testApprovalRequestTurnsActiveToolCardIntoActionableReview() throws {
        let call = ToolCall(
            id: "shell-approval-1",
            name: ToolDefinition.shellRun.name,
            argumentsJSON: ToolArguments.json(["cmd": "ls"])
        )
        let request = ApprovalRequest(
            id: "approval-1",
            toolCall: call,
            toolDefinition: ToolDefinition.shellRun,
            reason: "review required"
        )
        let failedResult = ToolResult(ok: false, error: "stopped")
        let thread = ChatThread(events: [
            ThreadEvent(kind: .toolQueued, summary: "queued", payloadJSON: try JSONHelpers.encodePretty(call)),
            ThreadEvent(
                kind: .approvalRequested,
                summary: "approve shell",
                payloadJSON: try JSONHelpers.encodePretty(request)
            ),
            ThreadEvent(kind: .toolFailed, summary: "failed", payloadJSON: try JSONHelpers.encodePretty(failedResult))
        ])

        let timelineCards = WorkspaceTranscriptSurfaceBuilder(thread: thread)
            .timelineItems()
            .compactMap(\.toolCard)

        XCTAssertEqual(timelineCards.count, 2)
        XCTAssertEqual(timelineCards[0].id, "shell-approval-1")
        XCTAssertEqual(timelineCards[0].title, ToolDefinition.shellRun.name)
        XCTAssertEqual(timelineCards[0].status, .review)
        XCTAssertEqual(timelineCards[0].subtitle, "Ready to run · ls")
        XCTAssertEqual(timelineCards[0].statusDisplayLabel, "Ready")
        XCTAssertEqual(timelineCards[0].statusAccessibilityLabel, "ready to run")
        XCTAssertEqual(timelineCards[0].reviewState, .ready)
        XCTAssertFalse(timelineCards[0].isExpanded)
        XCTAssertEqual(timelineCards[0].density, .peek)
        XCTAssertEqual(timelineCards[0].actions.map(\.title), ["Run", "Edit", "Skip"])
        XCTAssertEqual(timelineCards[0].actions.map(\.requestID), ["approval-1", "approval-1", "approval-1"])
        XCTAssertEqual(timelineCards[1].title, "Tool")
        XCTAssertEqual(timelineCards[1].status, .failed)
        XCTAssertEqual(timelineCards[1].subtitle, "Failed")
    }

    func testApprovalDecisionCollapsesReviewCardAndClearsActions() throws {
        let call = ToolCall(
            id: "shell-approval-2",
            name: ToolDefinition.shellRun.name,
            argumentsJSON: ToolArguments.json(["cmd": "whoami"])
        )
        let request = ApprovalRequest(
            id: "approval-2",
            toolCall: call,
            toolDefinition: ToolDefinition.shellRun,
            reason: "review required"
        )
        let decision = ApprovalDecision(
            requestID: "approval-2",
            verdict: .approve,
            rationale: "Approved from the tool card."
        )
        let thread = ChatThread(events: [
            ThreadEvent(kind: .toolQueued, summary: "queued", payloadJSON: try JSONHelpers.encodePretty(call)),
            ThreadEvent(
                kind: .approvalRequested,
                summary: "approve shell",
                payloadJSON: try JSONHelpers.encodePretty(request)
            ),
            ThreadEvent(
                kind: .approvalDecided,
                summary: "approve: Approved from the tool card.",
                payloadJSON: try JSONHelpers.encodePretty(decision)
            )
        ])

        let card = try XCTUnwrap(WorkspaceTranscriptSurfaceBuilder(thread: thread).toolCards().first)

        XCTAssertEqual(card.status, .done)
        XCTAssertEqual(card.subtitle, "Approved · whoami")
        XCTAssertFalse(card.isExpanded)
        XCTAssertEqual(card.density, .collapsed)
        XCTAssertEqual(card.actions, [])
        XCTAssertTrue(card.outputJSON?.contains("Approved from the tool card.") == true)
    }

    func testDeniedApprovalRequestDoesNotExposeApproveAction() throws {
        let call = ToolCall(
            id: "shell-denied",
            name: ToolDefinition.shellRun.name,
            argumentsJSON: ToolArguments.json(["cmd": "rm -rf /"])
        )
        let request = ApprovalRequest(
            id: "approval-denied",
            toolCall: call,
            toolDefinition: ToolDefinition.shellRun,
            reason: "Auto mode blocks high-risk command pattern: rm -rf /.",
            recommendedVerdict: .deny
        )
        let thread = ChatThread(events: [
            ThreadEvent(kind: .toolQueued, summary: "queued", payloadJSON: try JSONHelpers.encodePretty(call)),
            ThreadEvent(
                kind: .approvalRequested,
                summary: "deny: Auto mode blocks high-risk command pattern: rm -rf /.",
                payloadJSON: try JSONHelpers.encodePretty(request)
            )
        ])

        let card = try XCTUnwrap(WorkspaceTranscriptSurfaceBuilder(thread: thread).toolCards().first)

        XCTAssertEqual(card.status, .review)
        XCTAssertEqual(card.subtitle, "Blocked · rm -rf / · Auto mode blocks high-risk command pattern: rm -rf /.")
        XCTAssertEqual(card.statusDisplayLabel, "Needs review")
        XCTAssertEqual(card.statusAccessibilityLabel, "needs review")
        XCTAssertEqual(card.reviewState, .needsReview)
        XCTAssertTrue(card.isExpanded)
        XCTAssertEqual(card.density, .expanded)
        XCTAssertEqual(card.actions, [])
    }

    func testToolCardSubtitleBuilderSummarizesKnownArguments() {
        XCTAssertEqual(
            WorkspaceToolCardSubtitleBuilder.subtitle(
                stateLabel: "Running",
                toolName: "host.shell.run",
                inputJSON: ToolArguments.json(["cmd": "printf 'hello'\n && whoami"])
            ),
            "Running · printf 'hello' && whoami"
        )
        XCTAssertEqual(
            WorkspaceToolCardSubtitleBuilder.subtitle(
                stateLabel: "Completed",
                toolName: "host.file.list",
                inputJSON: ToolArguments.json(["path": "Sources"])
            ),
            "Completed · Sources"
        )
        XCTAssertEqual(
            WorkspaceToolCardSubtitleBuilder.subtitle(
                stateLabel: "Completed",
                toolName: "host.file.search",
                inputJSON: ToolArguments.json(["query": "AgentRunner"])
            ),
            "Completed · AgentRunner"
        )
        XCTAssertEqual(
            WorkspaceToolCardSubtitleBuilder.subtitle(
                stateLabel: "Completed",
                toolName: "host.git.diff",
                inputJSON: ToolArguments.json(["staged": true])
            ),
            "Completed · staged diff"
        )
        XCTAssertEqual(
            WorkspaceToolCardSubtitleBuilder.subtitle(
                stateLabel: "Completed",
                toolName: "host.git.push",
                inputJSON: ToolArguments.json(["remote": "origin", "branch": "main"])
            ),
            "Completed · origin/main"
        )
        XCTAssertEqual(
            WorkspaceToolCardSubtitleBuilder.subtitle(
                stateLabel: "Completed",
                toolName: "host.git.pr.list",
                inputJSON: ToolArguments.json(["state": "merged", "limit": 12])
            ),
            "Completed · merged, limit 12"
        )
        XCTAssertEqual(
            WorkspaceToolCardSubtitleBuilder.subtitle(
                stateLabel: "Queued",
                toolName: "host.git.pr.lifecycle",
                inputJSON: ToolArguments.json(["action": "reopen", "selector": "42"])
            ),
            "Queued · reopen 42"
        )
    }

    func testToolCardSubtitleBuilderSummarizesBrowserOpenAndReviewComment() {
        XCTAssertEqual(
            WorkspaceToolCardSubtitleBuilder.subtitle(
                stateLabel: "Completed",
                toolName: "host.browser.open",
                inputJSON: ToolArguments.json(["url": "https://example.com/docs"])
            ),
            "Completed · https://example.com/docs"
        )
        XCTAssertEqual(
            WorkspaceToolCardSubtitleBuilder.subtitle(
                stateLabel: "Completed",
                toolName: "host.git.pr.review_comment",
                inputJSON: ToolArguments.json(["path": "Sources/App.swift", "line": 12, "body": "nit"])
            ),
            "Completed · Sources/App.swift"
        )
        // host.browser.inspect takes no arguments, so it has no detail to show.
        XCTAssertEqual(
            WorkspaceToolCardSubtitleBuilder.subtitle(
                stateLabel: "Completed",
                toolName: "host.browser.inspect",
                inputJSON: "{}"
            ),
            "Completed"
        )
    }

    func testToolCardSubtitleBuilderSummarizesMCPAndComputerUseArguments() {
        XCTAssertEqual(
            WorkspaceToolCardSubtitleBuilder.subtitle(
                stateLabel: "Completed",
                toolName: "host.mcp.call",
                inputJSON: ToolArguments.json(["serverID": "fs", "toolName": "list_dir"])
            ),
            "Completed · list_dir"
        )
        XCTAssertEqual(
            WorkspaceToolCardSubtitleBuilder.subtitle(
                stateLabel: "Completed",
                toolName: "host.mcp.resource.read",
                inputJSON: ToolArguments.json(["serverID": "fs", "resourceName": "README"])
            ),
            "Completed · README"
        )
        XCTAssertEqual(
            WorkspaceToolCardSubtitleBuilder.subtitle(
                stateLabel: "Completed",
                toolName: "host.mcp.prompt.get",
                inputJSON: ToolArguments.json(["serverID": "fs", "promptName": "summarize"])
            ),
            "Completed · summarize"
        )
        XCTAssertEqual(
            WorkspaceToolCardSubtitleBuilder.subtitle(
                stateLabel: "Completed",
                toolName: "host.computer.click",
                inputJSON: ToolArguments.json(["x": 120, "y": 340])
            ),
            "Completed · 120, 340"
        )
        XCTAssertEqual(
            WorkspaceToolCardSubtitleBuilder.subtitle(
                stateLabel: "Completed",
                toolName: "host.computer.type",
                inputJSON: ToolArguments.json(["text": "hello world"])
            ),
            "Completed · hello world"
        )
        XCTAssertEqual(
            WorkspaceToolCardSubtitleBuilder.subtitle(
                stateLabel: "Completed",
                toolName: "host.computer.key",
                inputJSON: ToolArguments.json(["key": "cmd+s"])
            ),
            "Completed · cmd+s"
        )
        // host.computer.screenshot takes no arguments, so it has no detail.
        XCTAssertEqual(
            WorkspaceToolCardSubtitleBuilder.subtitle(
                stateLabel: "Completed",
                toolName: "host.computer.screenshot",
                inputJSON: "{}"
            ),
            "Completed"
        )
    }

    func testToolCardSubtitleBuilderFallsBackForInvalidOrUnknownInput() {
        XCTAssertEqual(
            WorkspaceToolCardSubtitleBuilder.subtitle(
                stateLabel: "Completed",
                toolName: "host.shell.run",
                inputJSON: "{}"
            ),
            "Completed"
        )
        XCTAssertEqual(
            WorkspaceToolCardSubtitleBuilder.subtitle(
                stateLabel: "Completed",
                toolName: "host.unknown",
                inputJSON: ToolArguments.json(["cmd": "whoami"])
            ),
            "Completed"
        )
    }
}
