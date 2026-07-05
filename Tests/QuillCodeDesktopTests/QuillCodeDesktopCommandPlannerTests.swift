import XCTest
import QuillCodeApp
@testable import quill_code_desktop

@MainActor
final class QuillCodeDesktopCommandPlannerTests: XCTestCase {
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
}
