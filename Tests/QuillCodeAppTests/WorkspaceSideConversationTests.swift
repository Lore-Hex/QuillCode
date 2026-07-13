import XCTest
import QuillCodeCore
@testable import QuillCodeApp

@MainActor
final class WorkspaceSideConversationTests: XCTestCase {
    func testSlashParserSupportsSideAndBtwWithOptionalPrompt() {
        XCTAssertEqual(WorkspaceSideConversationSlash.parse("/side")?.prompt, nil)
        XCTAssertEqual(WorkspaceSideConversationSlash.parse("  /SIDE explain this  ")?.prompt, "explain this")
        XCTAssertEqual(WorkspaceSideConversationSlash.parse("/btw check the API")?.prompt, "check the API")
        XCTAssertEqual(WorkspaceSideConversationSlash.parse("/side\tcheck spacing")?.prompt, "check spacing")
        XCTAssertNil(WorkspaceSideConversationSlash.parse("/sidebar"))
        XCTAssertNil(WorkspaceSideConversationSlash.parse("explain this"))
    }

    func testStartsTransientSideConversationWithInheritedContext() throws {
        let parent = parentThread()
        let model = model(selectedThread: parent)

        let sideID = try XCTUnwrap(model.startSideConversation(prompt: "Explain the failure"))
        let side = try XCTUnwrap(model.selectedThread)

        XCTAssertEqual(side.id, sideID)
        XCTAssertEqual(side.runtimeContext.sideConversationParentThreadID, parent.id)
        XCTAssertEqual(side.messages, parent.messages)
        XCTAssertEqual(side.instructions, parent.instructions)
        XCTAssertEqual(side.memories, parent.memories)
        XCTAssertEqual(side.worktree, parent.worktree)
        XCTAssertNil(side.goal)
        XCTAssertEqual(model.composer.draft, "Explain the failure")
        XCTAssertEqual(model.root.sidebarItems.map(\.id), [parent.id])
        XCTAssertEqual(model.root.allSidebarItems.map(\.id), [parent.id])
    }

    func testReturnRestoresParentDraftAndDiscardsSideConversation() throws {
        let parent = parentThread(composerDraft: "main draft")
        let model = model(selectedThread: parent)
        let sideID = try XCTUnwrap(model.startSideConversation())
        model.setDraft("temporary side draft")

        XCTAssertTrue(model.returnFromSideConversation())

        XCTAssertEqual(model.root.selectedThreadID, parent.id)
        XCTAssertEqual(model.composer.draft, "main draft")
        XCTAssertFalse(model.root.threads.contains { $0.id == sideID })
        XCTAssertNil(model.activeSideConversationParentThreadID)
    }

    func testSelectingAnotherThreadDiscardsSideConversation() throws {
        let parent = parentThread()
        let other = ChatThread(title: "Other", messages: [.init(role: .user, content: "Other task")])
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            threads: [parent, other],
            selectedThreadID: parent.id
        ))
        let sideID = try XCTUnwrap(model.startSideConversation())

        model.selectThread(other.id)

        XCTAssertEqual(model.root.selectedThreadID, other.id)
        XCTAssertFalse(model.root.threads.contains { $0.id == sideID })
        XCTAssertNil(model.activeSideConversationParentThreadID)
    }

    func testNewChatDiscardsSideConversationBeforeCreatingDurableThread() throws {
        let parent = parentThread()
        let model = model(selectedThread: parent)
        let sideID = try XCTUnwrap(model.startSideConversation())

        let newThreadID = model.newChat()

        XCTAssertEqual(model.root.selectedThreadID, newThreadID)
        XCTAssertFalse(model.root.threads.contains { $0.id == sideID })
        XCTAssertTrue(model.root.threads.contains { $0.id == parent.id })
        XCTAssertFalse(try XCTUnwrap(model.selectedThread).runtimeContext.isEphemeral)
    }

    func testSurfaceShowsReturnButDisablesDurableLifecycleCommands() throws {
        let parent = parentThread()
        let model = model(selectedThread: parent)
        _ = try XCTUnwrap(model.startSideConversation())

        let surface = model.surface()
        let side = try XCTUnwrap(surface.sideConversation)

        XCTAssertEqual(side.parentThreadID, parent.id)
        XCTAssertEqual(side.parentTitle, parent.title)
        XCTAssertEqual(side.parentStatus, "Main chat is ready")
        XCTAssertEqual(side.returnCommand.id, "side-conversation-return")
        XCTAssertEqual(command("side-conversation-return", in: surface.commands)?.isEnabled, true)
        for id in [
            "thread-rename", "thread-duplicate", "thread-pin", "thread-clear",
            "thread-archive", "thread-delete", "fork-from-last", "compact-context"
        ] {
            XCTAssertEqual(command(id, in: surface.commands)?.isEnabled, false, id)
        }

        let html = WorkspaceHTMLRenderer.render(surface)
        XCTAssertTrue(html.contains(#"data-testid="side-conversation""#))
        XCTAssertTrue(html.contains(#"data-command-id="side-conversation-return""#))
        XCTAssertTrue(html.contains("Side conversation"))
    }

    func testRejectsSideConversationWithoutAParentTurnOrInsideAnotherSideConversation() throws {
        let emptyParent = ChatThread(title: "Empty")
        let emptyModel = model(selectedThread: emptyParent)

        XCTAssertNil(emptyModel.startSideConversation())
        XCTAssertEqual(emptyModel.lastError, "Send a message in the main chat before opening a side conversation.")

        let parent = parentThread()
        let nestedModel = model(selectedThread: parent)
        _ = try XCTUnwrap(nestedModel.startSideConversation())
        XCTAssertNil(nestedModel.startSideConversation())
        XCTAssertEqual(nestedModel.lastError, "A side conversation is already open. Return to the parent chat first.")
    }

    private func parentThread(composerDraft: String? = nil) -> ChatThread {
        ChatThread(
            title: "Main task",
            messages: [
                .init(role: .user, content: "Implement the feature"),
                .init(role: .assistant, content: "Working on it"),
                .init(role: .tool, content: #"{"result":"reference"}"#)
            ],
            goal: ThreadGoal(objective: "Ship the feature"),
            instructions: [
                ProjectInstruction(path: "AGENTS.md", title: "Rules", content: "Use Swift.", byteCount: 10)
            ],
            memories: [
                MemoryNote(
                    id: "memory-1",
                    scope: .project,
                    title: "Preference",
                    content: "Prefer focused tests.",
                    relativePath: "memory.md",
                    byteCount: 20
                )
            ],
            composerDraft: composerDraft,
            worktree: WorktreeBinding(path: "/tmp/worktree", branch: "feature/side")
        )
    }

    private func model(selectedThread: ChatThread) -> QuillCodeWorkspaceModel {
        QuillCodeWorkspaceModel(root: QuillCodeRootState(
            threads: [selectedThread],
            selectedThreadID: selectedThread.id
        ))
    }

    private func command(
        _ id: String,
        in commands: [WorkspaceCommandSurface]
    ) -> WorkspaceCommandSurface? {
        commands.first { $0.id == id }
    }
}
