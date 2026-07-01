import XCTest
@testable import QuillCodeApp
import QuillCodeCore
import QuillCodeTools

final class WorkspaceTurnRevertPlannerTests: XCTestCase {
    private func userMessage(_ content: String, at seconds: TimeInterval) -> ChatMessage {
        ChatMessage(role: .user, content: content, createdAt: Date(timeIntervalSince1970: seconds))
    }

    private func toolQueuedEvent(name: String, arguments: [String: String], at seconds: TimeInterval) -> ThreadEvent {
        let call = ToolCall(name: name, argumentsJSON: ToolArguments.json(arguments))
        // Mirror WorkspaceToolEventRecorder: the .toolQueued payload is the redacted ToolCall.
        let payload = (try? JSONHelpers.encodePretty(call.redactedForTranscript())) ?? call.argumentsJSON
        return ThreadEvent(kind: .toolQueued, createdAt: Date(timeIntervalSince1970: seconds), summary: "\(name) queued", payloadJSON: payload)
    }

    private func applyPatchEvent(_ patch: String, at seconds: TimeInterval) -> ThreadEvent {
        toolQueuedEvent(name: ToolDefinition.applyPatch.name, arguments: ["patch": patch], at: seconds)
    }

    func testGroupsApplyPatchEditsUnderTheirOwningTurnInChronologicalOrder() {
        let u1 = userMessage("first", at: 100)
        let u2 = userMessage("second", at: 300)
        let thread = ChatThread(title: "T", messages: [u1, u2], events: [
            applyPatchEvent("PATCH-A", at: 150),
            applyPatchEvent("PATCH-B", at: 160),
            applyPatchEvent("PATCH-C", at: 350)
        ])

        let plans = WorkspaceTurnRevertPlanner.plans(for: thread)
        XCTAssertEqual(plans.count, 2)
        XCTAssertEqual(plans[0].turnMessageID, u1.id)
        XCTAssertEqual(plans[0].patches, ["PATCH-A", "PATCH-B"])
        XCTAssertFalse(plans[0].hasNonApplyPatchEdits)
        XCTAssertEqual(plans[1].turnMessageID, u2.id)
        XCTAssertEqual(plans[1].patches, ["PATCH-C"])
    }

    func testTurnWithoutApplyPatchYieldsNoPlan() {
        let u1 = userMessage("only shell", at: 100)
        let thread = ChatThread(title: "T", messages: [u1], events: [
            toolQueuedEvent(name: "host.shell.run", arguments: ["command": "ls"], at: 150)
        ])
        XCTAssertTrue(WorkspaceTurnRevertPlanner.plans(for: thread).isEmpty)
        XCTAssertNil(WorkspaceTurnRevertPlanner.plan(for: u1.id, in: thread))
    }

    func testFlagsTurnsThatAlsoEditedOutsideApplyPatch() {
        let u1 = userMessage("mixed", at: 100)
        let thread = ChatThread(title: "T", messages: [u1], events: [
            applyPatchEvent("PATCH-A", at: 150),
            toolQueuedEvent(name: "host.file.write", arguments: ["path": "x.txt", "content": "hi"], at: 160)
        ])

        let plan = WorkspaceTurnRevertPlanner.plan(for: u1.id, in: thread)
        XCTAssertEqual(plan?.patches, ["PATCH-A"])
        XCTAssertEqual(plan?.hasNonApplyPatchEdits, true)
    }

    func testFlagsDestructiveGitToolsAsNonApplyPatchEdits() {
        // host.git.restore / git.commit are working-tree mutators a reverse-patch can't undo.
        for mutatingTool in ["host.git.restore", "host.git.commit", "host.mcp.call"] {
            let u1 = userMessage("with \(mutatingTool)", at: 100)
            let thread = ChatThread(title: "T", messages: [u1], events: [
                applyPatchEvent("PATCH-A", at: 150),
                toolQueuedEvent(name: mutatingTool, arguments: ["x": "y"], at: 160)
            ])
            XCTAssertEqual(
                WorkspaceTurnRevertPlanner.plan(for: u1.id, in: thread)?.hasNonApplyPatchEdits, true,
                "\(mutatingTool) should flag the revert scope"
            )
        }
    }

    func testEmptyPatchesAreIgnored() {
        let u1 = userMessage("blank patch", at: 100)
        let thread = ChatThread(title: "T", messages: [u1], events: [
            applyPatchEvent("   ", at: 150)
        ])
        XCTAssertTrue(WorkspaceTurnRevertPlanner.plans(for: thread).isEmpty)
    }

    func testRedactionPreservesTheApplyPatchArgumentThePlannerReads() {
        // The planner's data source must survive transcript redaction (only env/environment
        // are redacted) — otherwise the whole feature silently loses its input.
        let call = ToolCall(name: ToolDefinition.applyPatch.name, argumentsJSON: ToolArguments.json(["patch": "THE-DIFF"]))
        let redacted = call.redactedForTranscript()
        XCTAssertEqual((try? ToolArguments(redacted.argumentsJSON))?.string("patch"), "THE-DIFF")
    }

    func testFlagsPrCheckoutThatTheOldDenylistMissed() {
        // Regression: host.git.pr.checkout (risk .append) mutates the local tree but was absent from
        // the hand-maintained denylist, so a turn doing apply_patch + pr.checkout claimed a clean undo.
        let u1 = userMessage("edit then checkout a PR", at: 100)
        let thread = ChatThread(title: "T", messages: [u1], events: [
            applyPatchEvent("PATCH-A", at: 150),
            toolQueuedEvent(name: "host.git.pr.checkout", arguments: ["selector": "42"], at: 160)
        ])
        XCTAssertEqual(WorkspaceTurnRevertPlanner.plan(for: u1.id, in: thread)?.hasNonApplyPatchEdits, true)
    }

    func testReadOnlyToolDoesNotFlagRevertScope() {
        // A read-only tool alongside apply_patch leaves the undo fully honorable — no partial warning.
        let u1 = userMessage("edit then read a file", at: 100)
        let thread = ChatThread(title: "T", messages: [u1], events: [
            applyPatchEvent("PATCH-A", at: 150),
            toolQueuedEvent(name: ToolDefinition.fileRead.name, arguments: ["path": "x.txt"], at: 160)
        ])
        XCTAssertEqual(WorkspaceTurnRevertPlanner.plan(for: u1.id, in: thread)?.hasNonApplyPatchEdits, false)
    }

    func testUnknownDynamicToolIsTreatedAsMutating() {
        // A tool not in the static catalog (an MCP/dynamic tool) is conservatively mutating — better to
        // over-warn than to under-report and lie about the undo scope.
        XCTAssertTrue(WorkspaceTurnRevertPlanner.isMutatingNonApplyTool("mcp.some.custom.tool"))
        XCTAssertFalse(WorkspaceTurnRevertPlanner.isMutatingNonApplyTool(ToolDefinition.applyPatch.name))
    }

    func testMutatingClassifierMatchesTheToolRiskCatalog() {
        // Correct-by-construction: every non-read tool in the catalog (except apply_patch) is flagged,
        // and every read-only tool is not — so a future mutating tool can never silently slip through.
        for definition in ToolRouter.definitions {
            let expected = definition.name != ToolDefinition.applyPatch.name && definition.risk != .read
            XCTAssertEqual(
                WorkspaceTurnRevertPlanner.isMutatingNonApplyTool(definition.name), expected,
                "\(definition.name) [risk \(definition.risk.rawValue)] misclassified"
            )
        }
    }
}
