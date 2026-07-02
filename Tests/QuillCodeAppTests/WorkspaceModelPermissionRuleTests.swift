import XCTest
import QuillCodeCore
import QuillCodePersistence
import QuillCodeSafety
import QuillCodeTools
@testable import QuillCodeApp

/// Functional tests at the approval-flow seam: an "always" answer must persist the right rule and
/// immediately resolve the other pending requests it matches (backfill).
final class WorkspaceModelPermissionRuleTests: XCTestCase {
    @MainActor
    private func makeModelWithPendingApprovals(
        _ requests: [ApprovalRequest]
    ) throws -> (model: QuillCodeWorkspaceModel, store: PermissionRuleFileStore, root: URL) {
        let root = try makeQuillCodeTestDirectory()
        let store = PermissionRuleFileStore(directory: root.appendingPathComponent(".permissions-store"))
        let model = QuillCodeWorkspaceModel(permissionRuleStore: store)
        _ = model.addProject(path: root, name: "Demo")
        _ = model.newChat()
        model.mutateSelectedThread { thread in
            for request in requests {
                thread.events.append(ThreadEvent(
                    kind: .approvalRequested,
                    summary: "clarify: review required",
                    payloadJSON: try? JSONHelpers.encodePretty(request)
                ))
            }
        }
        return (model, store, root)
    }

    private func shellApproval(id: String, cmd: String) -> ApprovalRequest {
        ApprovalRequest(
            id: id,
            toolCall: ToolCall(name: ToolDefinition.shellRun.name, argumentsJSON: ToolArguments.json(["cmd": cmd])),
            toolDefinition: .shellRun,
            reason: "review required",
            recommendedVerdict: .clarify
        )
    }

    @MainActor
    private func decidedRequestIDs(in model: QuillCodeWorkspaceModel) -> Set<String> {
        Set((model.selectedThread?.events ?? [])
            .filter { $0.kind == .approvalDecided }
            .compactMap { event -> String? in
                guard let payloadJSON = event.payloadJSON,
                      let decision = try? JSONHelpers.decode(ApprovalDecision.self, from: payloadJSON)
                else {
                    return nil
                }
                return decision.requestID
            })
    }

    @MainActor
    func testAlwaysAllowSavesExactRuleAndBackfillsMatchingPendingRequests() throws {
        let matching = shellApproval(id: "approval-a", cmd: "echo taught")
        let alsoMatching = shellApproval(id: "approval-b", cmd: "echo  taught") // whitespace respelling
        let unrelated = shellApproval(id: "approval-c", cmd: "echo other")
        let (model, store, root) = try makeModelWithPendingApprovals([matching, alsoMatching, unrelated])

        let didAct = model.runToolCardAction(
            ToolCardActionSurface(title: "Always run", kind: .approveAlways, requestID: "approval-a", style: .secondary),
            workspaceRoot: root
        )
        XCTAssertTrue(didAct)

        // The persisted rule is EXACT (action + normalized resource), not auto-generalized.
        let saved = store.load(forWorkspaceRoot: root)
        XCTAssertEqual(saved.table.rules, [
            PermissionRule(action: ToolDefinition.shellRun.name, resource: "echo taught", match: .exact, decision: .allow)
        ])

        // The acted-on request AND the matching pending request are decided; the unrelated one is
        // still waiting.
        let decided = decidedRequestIDs(in: model)
        XCTAssertTrue(decided.contains("approval-a"))
        XCTAssertTrue(decided.contains("approval-b"), "backfill must resolve pending requests the rule matches")
        XCTAssertFalse(decided.contains("approval-c"))
        XCTAssertEqual(
            WorkspaceApprovalActionPlanner.undecidedRequests(in: model.selectedThread).map(\.id),
            ["approval-c"]
        )

        // Both approved tools actually ran.
        let completions = (model.selectedThread?.events ?? []).filter { $0.kind == .toolCompleted }
        XCTAssertEqual(completions.count, 2, "the taught command must run for the acted and backfilled requests")
    }

    @MainActor
    func testAlwaysDenySavesDenyRuleBackfillsSkipsAndRunsNothing() throws {
        let matching = shellApproval(id: "deny-a", cmd: "git push origin main")
        let alsoMatching = shellApproval(id: "deny-b", cmd: "git push origin main")
        let unrelated = shellApproval(id: "deny-c", cmd: "git status")
        let (model, store, root) = try makeModelWithPendingApprovals([matching, alsoMatching, unrelated])

        let didAct = model.runToolCardAction(
            ToolCardActionSurface(title: "Never", kind: .denyAlways, requestID: "deny-a", style: .destructive),
            workspaceRoot: root
        )
        XCTAssertTrue(didAct)

        XCTAssertEqual(store.load(forWorkspaceRoot: root).table.rules, [
            PermissionRule(action: ToolDefinition.shellRun.name, resource: "git push origin main", match: .exact, decision: .deny)
        ])

        let decided = decidedRequestIDs(in: model)
        XCTAssertTrue(decided.contains("deny-a"))
        XCTAssertTrue(decided.contains("deny-b"))
        XCTAssertFalse(decided.contains("deny-c"))

        XCTAssertTrue(
            (model.selectedThread?.events ?? []).allSatisfy { $0.kind != .toolCompleted && $0.kind != .toolRunning },
            "an always-deny must never execute anything"
        )
    }

    @MainActor
    func testBackfillNeverResolvesHardBlockedRequests() throws {
        var hardBlocked = shellApproval(id: "hard-a", cmd: "echo taught")
        hardBlocked.recommendedVerdict = .deny // the static safety floor said no
        let acted = shellApproval(id: "soft-b", cmd: "echo taught")
        let (model, _, root) = try makeModelWithPendingApprovals([hardBlocked, acted])

        _ = model.runToolCardAction(
            ToolCardActionSurface(title: "Always run", kind: .approveAlways, requestID: "soft-b", style: .secondary),
            workspaceRoot: root
        )

        let decided = decidedRequestIDs(in: model)
        XCTAssertTrue(decided.contains("soft-b"))
        XCTAssertFalse(
            decided.contains("hard-a"),
            "a persisted allow skips the ASK, never the safety floor: hard-blocked requests stay blocked"
        )
    }

    @MainActor
    func testAlwaysAllowOverCorruptRuleFileSurfacesDiagnosticAndStillSaves() throws {
        let request = shellApproval(id: "approval-x", cmd: "echo resilient")
        let (model, store, root) = try makeModelWithPendingApprovals([request])
        let fileURL = store.fileURL(forWorkspaceRoot: root)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("corrupt!".utf8).write(to: fileURL)

        _ = model.runToolCardAction(
            ToolCardActionSurface(title: "Always run", kind: .approveAlways, requestID: "approval-x", style: .secondary),
            workspaceRoot: root
        )

        XCTAssertNotNil(model.lastError, "a corrupt rules file must surface a diagnostic, not crash")
        XCTAssertEqual(store.load(forWorkspaceRoot: root).table.rules.count, 1, "the new rule still lands in a fresh file")
    }

    @MainActor
    func testPlainApproveSavesNoRule() throws {
        let request = shellApproval(id: "plain-a", cmd: "echo once")
        let (model, store, root) = try makeModelWithPendingApprovals([request])

        _ = model.runToolCardAction(
            ToolCardActionSurface(title: "Run", kind: .approve, requestID: "plain-a", style: .primary),
            workspaceRoot: root
        )

        XCTAssertTrue(store.load(forWorkspaceRoot: root).table.isEmpty)
    }

    // MARK: - Planner + projection surfaces for the new kinds

    func testPlannerBuildsAlwaysApprovePlan() throws {
        let request = shellApproval(id: "plan-a", cmd: "swift test")
        let thread = ChatThread(events: [ThreadEvent(
            kind: .approvalRequested,
            summary: "clarify",
            payloadJSON: try JSONHelpers.encodePretty(request)
        )])

        let plan = try XCTUnwrap(WorkspaceApprovalActionPlanner.plan(
            action: ToolCardActionSurface(title: "Always run", kind: .approveAlways, requestID: "plan-a", style: .secondary),
            thread: thread
        ))

        XCTAssertTrue(plan.shouldRunTool)
        XCTAssertEqual(plan.persistRuleDecision, .allow)
        let decision = try JSONHelpers.decode(
            ApprovalDecision.self,
            from: try XCTUnwrap(plan.decisionEvent?.payloadJSON)
        )
        XCTAssertEqual(decision.verdict, .approve)
    }

    func testPlannerBuildsAlwaysDenyPlan() throws {
        let request = shellApproval(id: "plan-d", cmd: "git push")
        let thread = ChatThread(events: [ThreadEvent(
            kind: .approvalRequested,
            summary: "clarify",
            payloadJSON: try JSONHelpers.encodePretty(request)
        )])

        let plan = try XCTUnwrap(WorkspaceApprovalActionPlanner.plan(
            action: ToolCardActionSurface(title: "Never", kind: .denyAlways, requestID: "plan-d", style: .destructive),
            thread: thread
        ))

        XCTAssertFalse(plan.shouldRunTool)
        XCTAssertEqual(plan.persistRuleDecision, .deny)
        XCTAssertNotNil(plan.assistantNotice)
        let decision = try JSONHelpers.decode(
            ApprovalDecision.self,
            from: try XCTUnwrap(plan.decisionEvent?.payloadJSON)
        )
        XCTAssertEqual(decision.verdict, .deny)
    }

    func testApprovalCardOffersAlwaysActions() throws {
        let request = shellApproval(id: "card-a", cmd: "swift test")
        let event = ThreadEvent(
            kind: .approvalRequested,
            summary: "clarify",
            payloadJSON: try JSONHelpers.encodePretty(request)
        )
        let card = WorkspaceToolCardProjection.approvalReviewCard(for: event)
        XCTAssertEqual(
            card.actions.map(\.kind),
            [.approve, .approveAlways, .edit, .deny, .denyAlways]
        )
    }

    // MARK: - Security-review regressions

    /// #3: an unscopable tool (apply_patch) must NOT offer "Always run" — teaching one patch must
    /// never authorize every future patch.
    func testApprovalCardWithholdsAlwaysRunForUnscopableTool() throws {
        let request = ApprovalRequest(
            id: "card-patch",
            toolCall: ToolCall(name: "host.apply_patch", argumentsJSON: ToolArguments.json(["patch": "diff"])),
            toolDefinition: nil,
            reason: "review required",
            recommendedVerdict: .clarify
        )
        let event = ThreadEvent(
            kind: .approvalRequested,
            summary: "clarify",
            payloadJSON: try JSONHelpers.encodePretty(request)
        )
        let card = WorkspaceToolCardProjection.approvalReviewCard(for: event)
        XCTAssertEqual(
            card.actions.map(\.kind),
            [.approve, .edit, .deny, .denyAlways],
            "an unscopable tool must not offer Always run"
        )
    }

    /// #3: even if 'Always run' is somehow driven for an unscopable tool, no allow rule is
    /// persisted — the request is approved just once.
    @MainActor
    func testAlwaysAllowOnUnscopableToolPersistsNoRule() throws {
        let patch = ApprovalRequest(
            id: "patch-a",
            toolCall: ToolCall(name: "host.apply_patch", argumentsJSON: ToolArguments.json(["patch": "diff"])),
            toolDefinition: nil,
            reason: "review required",
            recommendedVerdict: .clarify
        )
        let (model, store, root) = try makeModelWithPendingApprovals([patch])

        _ = model.runToolCardAction(
            ToolCardActionSurface(title: "Always run", kind: .approveAlways, requestID: "patch-a", style: .secondary),
            workspaceRoot: root
        )

        XCTAssertTrue(store.load(forWorkspaceRoot: root).table.isEmpty, "no allow rule may persist for an unscopable tool")
        XCTAssertNotNil(model.lastError, "the user should be told it was approved only once")
    }

    /// #4: an always-allow taught from a bare command must NOT backfill a pending call that carries
    /// an environment override.
    @MainActor
    func testBackfillDoesNotAutoRunEnvInjectedPendingCall() throws {
        let taught = shellApproval(id: "env-taught", cmd: "swift test")
        let injected = ApprovalRequest(
            id: "env-injected",
            toolCall: ToolCall(
                name: ToolDefinition.shellRun.name,
                argumentsJSON: ToolArguments.json(["cmd": "swift test", "environment": ["PATH": "/tmp/evil"]])
            ),
            toolDefinition: .shellRun,
            reason: "review required",
            recommendedVerdict: .clarify
        )
        let (model, _, root) = try makeModelWithPendingApprovals([taught, injected])

        _ = model.runToolCardAction(
            ToolCardActionSurface(title: "Always run", kind: .approveAlways, requestID: "env-taught", style: .secondary),
            workspaceRoot: root
        )

        let decided = decidedRequestIDs(in: model)
        XCTAssertTrue(decided.contains("env-taught"))
        XCTAssertFalse(
            decided.contains("env-injected"),
            "a bare-command allow must not backfill a call carrying an env override"
        )
    }

    /// #6: backfill only resolves CURRENT-TURN pending requests, never ones the user abandoned by
    /// sending a new message.
    @MainActor
    func testBackfillIgnoresStaleRequestsFromAnEarlierTurn() throws {
        let root = try makeQuillCodeTestDirectory()
        let store = PermissionRuleFileStore(directory: root.appendingPathComponent(".permissions-store"))
        let model = QuillCodeWorkspaceModel(permissionRuleStore: store)
        _ = model.addProject(path: root, name: "Demo")
        _ = model.newChat()

        let stale = shellApproval(id: "stale", cmd: "echo taught")
        let current = shellApproval(id: "current", cmd: "echo taught")
        model.mutateSelectedThread { thread in
            // Turn 1: an approval the user never answered, then a NEW user message (they redirected).
            thread.events.append(ThreadEvent(
                kind: .approvalRequested, summary: "clarify",
                payloadJSON: try? JSONHelpers.encodePretty(stale)
            ))
            let secondTurn = "please do the second thing"
            thread.messages.append(ChatMessage(role: .user, content: secondTurn))
            thread.events.append(ThreadEvent(kind: .message, summary: secondTurn))
            // Turn 2: the current pending approval the user is now acting on.
            thread.events.append(ThreadEvent(
                kind: .approvalRequested, summary: "clarify",
                payloadJSON: try? JSONHelpers.encodePretty(current)
            ))
        }

        _ = model.runToolCardAction(
            ToolCardActionSurface(title: "Always run", kind: .approveAlways, requestID: "current", style: .secondary),
            workspaceRoot: root
        )

        let decided = decidedRequestIDs(in: model)
        XCTAssertTrue(decided.contains("current"))
        XCTAssertFalse(
            decided.contains("stale"),
            "a request from an earlier abandoned turn must not be backfilled"
        )
    }
}
