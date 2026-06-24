import Foundation
import XCTest
import QuillCodeCore
@testable import QuillCodeApp

final class WorkspaceWorktreeOpenEngineTests: XCTestCase {
    func testLocalThreadUsesBranchAsTitleAndPreservesContext() {
        let projectID = UUID()
        let instruction = ProjectInstruction(
            path: "AGENTS.md",
            title: "Agent Rules",
            content: "Use Swift.",
            byteCount: 10
        )
        let memory = MemoryNote(
            id: "memory-1",
            scope: .project,
            title: "Preference",
            content: "Prefer small PRs.",
            relativePath: ".quillcode/memories/preference.md",
            byteCount: 17
        )
        let context = WorkspaceWorktreeOpenContext(
            request: .init(path: "feature", branch: " feature/login "),
            projectID: projectID,
            mode: .review,
            model: TrustedRouterDefaults.synthModel,
            instructions: [instruction],
            memories: [memory]
        )

        let opened = WorkspaceWorktreeOpenEngine.localThread(
            worktreeURL: URL(fileURLWithPath: "/tmp/QuillCode/feature").standardizedFileURL,
            context: context
        )

        XCTAssertEqual(opened.displayName, "feature")
        XCTAssertEqual(opened.noticePayload, "/tmp/QuillCode/feature")
        XCTAssertEqual(opened.thread.title, "Worktree: feature/login")
        XCTAssertEqual(opened.thread.projectID, projectID)
        XCTAssertEqual(opened.thread.mode, .review)
        XCTAssertEqual(opened.thread.model, TrustedRouterDefaults.synthModel)
        XCTAssertEqual(opened.thread.instructions, [instruction])
        XCTAssertEqual(opened.thread.memories, [memory])
        XCTAssertEqual(opened.thread.messages.map(\.content), [
            "Opened worktree `feature` at `/tmp/QuillCode/feature`."
        ])
        XCTAssertEqual(opened.thread.events.map(\.kind), [.notice, .message])
        XCTAssertEqual(opened.thread.events.first?.summary, "Opened worktree feature")
        XCTAssertEqual(opened.thread.events.first?.payloadJSON, "/tmp/QuillCode/feature")
    }

    func testLocalThreadFallsBackToDirectoryNameWhenBranchIsBlank() {
        let opened = WorkspaceWorktreeOpenEngine.localThread(
            worktreeURL: URL(fileURLWithPath: "/tmp/QuillCode/ui-polish").standardizedFileURL,
            context: context(request: .init(path: "ui-polish", branch: "   "))
        )

        XCTAssertEqual(opened.thread.title, "Worktree: ui-polish")
    }

    func testRemoteThreadUsesConnectionDisplayLabelForMessageAndPayload() throws {
        let connection = try XCTUnwrap(ProjectConnection.parseSSH("ssh://quill@feather.local:2222/srv/quill/feature"))

        let opened = WorkspaceWorktreeOpenEngine.remoteThread(
            connection: connection,
            context: context(request: .init(path: "feature", branch: "remote/feature"))
        )

        XCTAssertEqual(opened.displayName, "feature")
        XCTAssertEqual(opened.noticePayload, "ssh://quill@feather.local:2222/srv/quill/feature")
        XCTAssertEqual(opened.thread.title, "Worktree: remote/feature")
        XCTAssertEqual(opened.thread.messages.map(\.content), [
            "Opened remote worktree `feature` at `ssh://quill@feather.local:2222/srv/quill/feature`."
        ])
        XCTAssertEqual(opened.thread.events.first?.summary, "Opened remote worktree feature")
        XCTAssertEqual(opened.thread.events.first?.payloadJSON, "ssh://quill@feather.local:2222/srv/quill/feature")
    }

    func testRemoteThreadUsesRootPathAsDisplayName() {
        let connection = ProjectConnection.ssh(path: "/", host: "feather.local", user: "quill")

        let opened = WorkspaceWorktreeOpenEngine.remoteThread(
            connection: connection,
            context: context(request: .init(path: "root"))
        )

        XCTAssertEqual(opened.displayName, "/")
        XCTAssertEqual(opened.thread.title, "Worktree: /")
        XCTAssertEqual(opened.thread.events.first?.summary, "Opened remote worktree /")
    }

    private func context(request: WorkspaceWorktreeCreateRequest) -> WorkspaceWorktreeOpenContext {
        WorkspaceWorktreeOpenContext(
            request: request,
            projectID: UUID(),
            mode: .auto,
            model: TrustedRouterDefaults.fastModel
        )
    }
}
