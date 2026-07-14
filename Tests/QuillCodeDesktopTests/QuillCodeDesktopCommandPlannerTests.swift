import XCTest
import QuillCodeApp
@testable import quill_code_desktop

@MainActor
final class QuillCodeDesktopCommandPlannerTests: XCTestCase {
    func testDesktopOwnedPresentationCommandsUseDedicatedActions() {
        let commandIDs = ["search", "find-in-chat", "dictation"]

        let actions = commandIDs.map {
            QuillCodeDesktopCommandPlanner.action(
                for: WorkspaceCommandSurface(id: $0, title: $0)
            )
        }

        guard case .search = actions[0],
              case .find = actions[1],
              case .dictation = actions[2]
        else {
            return XCTFail("Expected search, find, and dictation to use desktop presentation actions.")
        }
    }

    func testSecondaryCodexAliasesResolveWithoutDuplicatingPrimaryMenuBindings() {
        let profile = WorkspaceShortcutRegistry.defaults

        XCTAssertEqual(
            QuillCodeSecondaryShortcutResolver.commandID(
                for: QuillCodeDesktopShortcutEvent(
                    key: "p",
                    modifiers: [.command, .shift]
                ),
                profile: profile
            ),
            "command-palette"
        )
        XCTAssertEqual(
            QuillCodeSecondaryShortcutResolver.commandID(
                for: QuillCodeDesktopShortcutEvent(
                    key: "o",
                    modifiers: [.command, .shift]
                ),
                profile: profile
            ),
            "new-chat"
        )
        XCTAssertNil(QuillCodeSecondaryShortcutResolver.commandID(
            for: QuillCodeDesktopShortcutEvent(key: "k", modifiers: [.command]),
            profile: profile
        ))
    }

    func testCopyConversationUsesDedicatedDesktopAction() {
        let command = WorkspaceCommandSurface(
            id: "copy-conversation",
            title: "Copy conversation",
            shortcut: "Cmd+Shift+C",
            category: "Navigation",
            keywords: ["copy"],
            isEnabled: true
        )

        guard case .copyConversation = QuillCodeDesktopCommandPlanner.action(for: command) else {
            return XCTFail("Expected copy-conversation to copy the current transcript markdown.")
        }
    }

    func testStopWorkflowRecordingUsesImmediateDesktopAction() {
        let command = WorkspaceCommandSurface(
            id: "workflow-recording-stop",
            title: "Stop recording",
            isEnabled: true
        )

        guard case .stopWorkflowRecording = QuillCodeDesktopCommandPlanner.action(for: command) else {
            return XCTFail("Expected workflow recording to stop before the drafting turn is queued.")
        }
    }
}
