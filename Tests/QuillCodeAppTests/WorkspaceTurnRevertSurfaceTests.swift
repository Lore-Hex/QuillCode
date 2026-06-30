import XCTest
@testable import QuillCodeApp
import QuillCodeCore
import QuillCodeTools

@MainActor
final class WorkspaceTurnRevertSurfaceTests: XCTestCase {
    private func applyPatchEvent(_ patch: String, at seconds: TimeInterval) -> ThreadEvent {
        let call = ToolCall(name: ToolDefinition.applyPatch.name, argumentsJSON: ToolArguments.json(["patch": patch]))
        let payload = (try? JSONHelpers.encodePretty(call.redactedForTranscript())) ?? call.argumentsJSON
        return ThreadEvent(kind: .toolQueued, createdAt: Date(timeIntervalSince1970: seconds), summary: "queued", payloadJSON: payload)
    }

    func testUserMessageStartingAnApplyPatchTurnGetsARevertAffordance() {
        let user = ChatMessage(role: .user, content: "do it", createdAt: Date(timeIntervalSince1970: 100))
        let thread = ChatThread(title: "T", messages: [user], events: [applyPatchEvent("DIFF", at: 150)])
        let surfaces = WorkspaceTranscriptSurfaceBuilder(thread: thread).messageSurfaces()
        XCTAssertEqual(surfaces.first(where: { $0.id == user.id })?.revert?.turnMessageID, user.id)
    }

    func testMessageWithoutApplyPatchHasNoRevertAffordance() {
        let user = ChatMessage(role: .user, content: "just talk", createdAt: Date(timeIntervalSince1970: 100))
        let thread = ChatThread(title: "T", messages: [user], events: [])
        XCTAssertNil(WorkspaceTranscriptSurfaceBuilder(thread: thread).messageSurfaces().first?.revert)
    }

    func testRevertScopeCopyMatchesTheCrossSurfaceParityFixture() {
        // The SAME two literals are asserted against the JS harness in revert.spec.ts, so the
        // truthful copy is pinned byte-identical across Swift, HTML, and the harness.
        XCTAssertEqual(
            TurnRevertCopy.scope(hasNonApplyPatchEdits: false),
            "Reverses the file edits this turn applied, including files it created. It does not undo your own earlier edits, shell commands the turn ran, or git commits."
        )
        XCTAssertEqual(
            TurnRevertCopy.scope(hasNonApplyPatchEdits: true),
            "Reverses the file edits this turn applied, including files it created. It does not undo your own earlier edits, shell commands the turn ran, or git commits. This turn also changed files outside apply_patch, which can't be reverted automatically."
        )
    }

    func testHTMLRendererEmitsRevertButtonForRevertableUserMessage() {
        let user = ChatMessage(role: .user, content: "do it", createdAt: Date(timeIntervalSince1970: 100))
        let thread = ChatThread(title: "T", messages: [user], events: [applyPatchEvent("DIFF", at: 150)])
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(threads: [thread], selectedThreadID: thread.id))
        let html = WorkspaceHTMLRenderer.render(model.surface())
        XCTAssertTrue(html.contains(#"data-testid="message-revert-turn""#))
        XCTAssertTrue(html.contains("data-turn-id=\"\(user.id.uuidString)\""))
    }

    private func shellEvent(at seconds: TimeInterval) -> ThreadEvent {
        let call = ToolCall(name: ToolDefinition.shellRun.name, argumentsJSON: ToolArguments.json(["command": "rm x"]))
        let payload = (try? JSONHelpers.encodePretty(call.redactedForTranscript())) ?? call.argumentsJSON
        return ThreadEvent(kind: .toolQueued, createdAt: Date(timeIntervalSince1970: seconds), summary: "queued", payloadJSON: payload)
    }

    func testRemoteProjectHidesTheRevertAffordanceAndRefusesRevert() {
        let user = ChatMessage(role: .user, content: "edit", createdAt: Date(timeIntervalSince1970: 100))
        let connection = ProjectConnection.ssh(path: "/srv/app", host: "feather.local", user: "quill")
        let project = ProjectRef(name: "Remote", path: connection.path, connection: connection)
        let thread = ChatThread(title: "T", projectID: project.id, messages: [user], events: [applyPatchEvent("DIFF", at: 150)])
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            projects: [project], selectedProjectID: project.id, threads: [thread], selectedThreadID: thread.id
        ))

        // No revert button is offered on a remote project (the local reverse-patch can't run there).
        XCTAssertNil(model.surface().transcript.messages.first(where: { $0.id == user.id })?.revert)
        // And the dispatch refuses rather than touch the wrong local tree.
        XCTAssertFalse(model.runTurnRevert(turnMessageID: user.id, workspaceRoot: FileManager.default.temporaryDirectory))
        XCTAssertEqual(model.surface().lastError, "Reverting a turn is only supported for local projects.")
    }

    func testRunTurnRevertWithNoPlanFailsHonestly() {
        let user = ChatMessage(role: .user, content: "just talk", createdAt: Date(timeIntervalSince1970: 100))
        let thread = ChatThread(title: "T", messages: [user], events: [])
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(threads: [thread], selectedThreadID: thread.id))

        XCTAssertFalse(model.runTurnRevert(turnMessageID: user.id, workspaceRoot: FileManager.default.temporaryDirectory))
        XCTAssertEqual(model.surface().lastError, "This turn can no longer be reverted.")
        XCTAssertFalse(model.currentToolCards.contains { $0.title == "host.git.revert_turn" })
    }

    func testRunTurnRevertSurfacesAnHonestFailureWhenFilesChangedSince() throws {
        let root = try makeTempGitRepoWithInitialCommit()
        let executor = FileToolExecutor(workspaceRoot: root)
        XCTAssertTrue(executor.write(path: "a.txt", content: "old\n").ok)
        _ = try runGit(["add", "-A"], cwd: root)
        _ = try runGit(["commit", "-m", "base"], cwd: root)
        XCTAssertTrue(executor.write(path: "a.txt", content: "new\n").ok)
        let patch = GitToolExecutor().diff(cwd: root).stdout
        // The user changed the same line AFTER the turn, so the reverse can't apply.
        XCTAssertTrue(executor.write(path: "a.txt", content: "newer\n").ok)

        let user = ChatMessage(role: .user, content: "edit a", createdAt: Date(timeIntervalSince1970: 100))
        let thread = ChatThread(title: "T", messages: [user], events: [applyPatchEvent(patch, at: 150)])
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(threads: [thread], selectedThreadID: thread.id))

        XCTAssertFalse(model.runTurnRevert(turnMessageID: user.id, workspaceRoot: root))
        XCTAssertNotNil(model.surface().lastError)
        // The user's later edit is untouched (no HEAD restore), and the failed run is recorded.
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("a.txt"), encoding: .utf8), "newer\n")
        XCTAssertTrue(model.currentToolCards.contains { $0.title == "host.git.revert_turn" && $0.status == .failed })
    }

    func testHTMLRendererDisclosesNonApplyPatchEditsInTheRevertScope() {
        let user = ChatMessage(role: .user, content: "mixed turn", createdAt: Date(timeIntervalSince1970: 100))
        let thread = ChatThread(title: "T", messages: [user], events: [applyPatchEvent("DIFF", at: 150), shellEvent(at: 160)])
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(threads: [thread], selectedThreadID: thread.id))
        let html = WorkspaceHTMLRenderer.render(model.surface())
        XCTAssertTrue(html.contains("outside apply_patch"))
    }

    func testMessageSurfaceDecodesLegacyJSONWithoutRevertKey() throws {
        let surface = MessageSurface(message: ChatMessage(role: .user, content: "hi"))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(surface)) as? [String: Any])
        object.removeValue(forKey: "revert")
        let decoded = try JSONDecoder().decode(MessageSurface.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(decoded.revert)
    }

    func testRunTurnRevertReverseAppliesTheTurnEditsAndRefreshesDiff() throws {
        let root = try makeTempGitRepoWithInitialCommit()
        let executor = FileToolExecutor(workspaceRoot: root)
        XCTAssertTrue(executor.write(path: "a.txt", content: "old\n").ok)
        _ = try runGit(["add", "-A"], cwd: root)
        _ = try runGit(["commit", "-m", "base"], cwd: root)
        // The turn edited a.txt old -> new; capture exactly what it changed.
        XCTAssertTrue(executor.write(path: "a.txt", content: "new\n").ok)
        let patch = GitToolExecutor().diff(cwd: root).stdout
        XCTAssertFalse(patch.isEmpty)

        let user = ChatMessage(role: .user, content: "edit a", createdAt: Date(timeIntervalSince1970: 100))
        let thread = ChatThread(title: "T", messages: [user], events: [applyPatchEvent(patch, at: 150)])
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(threads: [thread], selectedThreadID: thread.id))

        let ok = model.runTurnRevert(turnMessageID: user.id, workspaceRoot: root)

        XCTAssertTrue(ok)
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("a.txt"), encoding: .utf8), "old\n")
        // The revert is recorded as a transcript tool run plus a diff refresh.
        XCTAssertTrue(model.currentToolCards.contains { $0.title == "host.git.revert_turn" })
    }
}
