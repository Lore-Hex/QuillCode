import XCTest
import QuillCodeCore
@testable import QuillCodeApp

final class WorkspaceSlashCommandDispatchPlannerTests: XCTestCase {
    func testHelpAndStatusBuildLocalTranscripts() {
        XCTAssertEqual(
            WorkspaceSlashCommandDispatchPlanner.action(
                for: .help,
                userText: "/help",
                statusText: "unused"
            ),
            .appendTranscript(WorkspaceSlashCommandTranscriptPlanner.help(userText: "/help"))
        )
        XCTAssertEqual(
            WorkspaceSlashCommandDispatchPlanner.action(
                for: .status,
                userText: "/status",
                statusText: "Ready"
            ),
            .appendTranscript(WorkspaceSlashCommandTranscriptPlanner.status(
                userText: "/status",
                statusText: "Ready"
            ))
        )
    }

    func testStatefulCommandsKeepUserTextForModelApplication() {
        XCTAssertEqual(
            WorkspaceSlashCommandDispatchPlanner.action(
                for: .mode(.auto),
                userText: "/mode auto",
                statusText: "unused"
            ),
            .setMode(.auto, userText: "/mode auto")
        )
        XCTAssertEqual(
            WorkspaceSlashCommandDispatchPlanner.action(
                for: .model("/prometheus"),
                userText: "/model /prometheus",
                statusText: "unused"
            ),
            .setModel("/prometheus", userText: "/model /prometheus")
        )
        XCTAssertEqual(
            WorkspaceSlashCommandDispatchPlanner.action(
                for: .renameThread("Ship it"),
                userText: "/rename Ship it",
                statusText: "unused"
            ),
            .renameThread("Ship it", userText: "/rename Ship it")
        )
        XCTAssertEqual(
            WorkspaceSlashCommandDispatchPlanner.action(
                for: .renameProject("QuillCode"),
                userText: "/project rename QuillCode",
                statusText: "unused"
            ),
            .renameProject("QuillCode", userText: "/project rename QuillCode")
        )
    }

    func testExternalCommandFamiliesMapToTypedActions() {
        let toolCall = ToolCall(id: "call-1", name: "shell.run", argumentsJSON: #"{"cmd":"whoami"}"#)
        let createWorktree = WorkspaceWorktreeCreateRequest(path: "../feature", branch: "feature/test", base: "main")
        let openWorktree = WorkspaceWorktreeOpenRequest(path: "../feature")
        let removeWorktree = WorkspaceWorktreeRemoveRequest(path: "../feature", force: true)
        let pruneWorktrees = WorkspaceWorktreePruneRequest(dryRun: true, verbose: true)
        let subagents = WorkspaceSubagentRunRequest(
            objective: "audit release",
            workers: [.init(name: "Verifier", role: "run checks")]
        )

        XCTAssertEqual(
            WorkspaceSlashCommandDispatchPlanner.action(
                for: .sshProject("quill@example.com:/repo"),
                userText: "/ssh quill@example.com:/repo",
                statusText: "unused"
            ),
            .addSSHProject("quill@example.com:/repo", userText: "/ssh quill@example.com:/repo")
        )
        XCTAssertEqual(
            WorkspaceSlashCommandDispatchPlanner.action(
                for: .remember("Use Prometheus 1.0"),
                userText: "/remember Use Prometheus 1.0",
                statusText: "unused"
            ),
            .remember("Use Prometheus 1.0", userText: "/remember Use Prometheus 1.0")
        )
        XCTAssertEqual(
            WorkspaceSlashCommandDispatchPlanner.action(
                for: .threadFollowUp("tomorrow"),
                userText: "/follow-up tomorrow",
                statusText: "unused"
            ),
            .threadFollowUp("tomorrow", userText: "/follow-up tomorrow")
        )
        XCTAssertEqual(
            WorkspaceSlashCommandDispatchPlanner.action(
                for: .workspaceSchedule("hourly"),
                userText: "/workspace-check hourly",
                statusText: "unused"
            ),
            .workspaceSchedule("hourly", userText: "/workspace-check hourly")
        )
        XCTAssertEqual(
            WorkspaceSlashCommandDispatchPlanner.action(
                for: .subagents(subagents),
                userText: "/subagents audit release | Verifier: run checks",
                statusText: "unused"
            ),
            .subagents(subagents, userText: "/subagents audit release | Verifier: run checks")
        )
        XCTAssertEqual(
            WorkspaceSlashCommandDispatchPlanner.action(
                for: .workspaceCommand("toggle-browser"),
                userText: "/browser",
                statusText: "unused"
            ),
            .workspaceCommand("toggle-browser", userText: "/browser")
        )
        XCTAssertEqual(
            WorkspaceSlashCommandDispatchPlanner.action(
                for: .worktreeCreate(createWorktree),
                userText: "/worktree create ../feature --branch feature/test --base main",
                statusText: "unused"
            ),
            .worktreeCreate(createWorktree, userText: "/worktree create ../feature --branch feature/test --base main")
        )
        XCTAssertEqual(
            WorkspaceSlashCommandDispatchPlanner.action(
                for: .worktreeOpen(openWorktree),
                userText: "/worktree open ../feature",
                statusText: "unused"
            ),
            .worktreeOpen(openWorktree, userText: "/worktree open ../feature")
        )
        XCTAssertEqual(
            WorkspaceSlashCommandDispatchPlanner.action(
                for: .worktreeRemove(removeWorktree),
                userText: "/worktree remove ../feature --force",
                statusText: "unused"
            ),
            .worktreeRemove(removeWorktree, userText: "/worktree remove ../feature --force")
        )
        XCTAssertEqual(
            WorkspaceSlashCommandDispatchPlanner.action(
                for: .worktreePrune(pruneWorktrees),
                userText: "/worktree prune --dry-run --verbose",
                statusText: "unused"
            ),
            .worktreePrune(pruneWorktrees, userText: "/worktree prune --dry-run --verbose")
        )
        XCTAssertEqual(
            WorkspaceSlashCommandDispatchPlanner.action(
                for: .toolCall(toolCall),
                userText: "/pr view 12",
                statusText: "unused"
            ),
            .toolCall(toolCall)
        )
        XCTAssertEqual(
            WorkspaceSlashCommandDispatchPlanner.action(
                for: .environmentAction("build"),
                userText: "/env build",
                statusText: "unused"
            ),
            .environmentAction("build", userText: "/env build")
        )
        XCTAssertEqual(
            WorkspaceSlashCommandDispatchPlanner.action(
                for: .environmentSchedule("build in 30 minutes"),
                userText: "/env schedule build in 30 minutes",
                statusText: "unused"
            ),
            .environmentSchedule("build in 30 minutes", userText: "/env schedule build in 30 minutes")
        )
    }

    func testInvalidAndUnknownBuildLocalTranscripts() {
        XCTAssertEqual(
            WorkspaceSlashCommandDispatchPlanner.action(
                for: .invalid("Missing model"),
                userText: "/model",
                statusText: "unused"
            ),
            .appendTranscript(WorkspaceSlashCommandTranscriptPlanner.invalid(
                userText: "/model",
                message: "Missing model"
            ))
        )
        XCTAssertEqual(
            WorkspaceSlashCommandDispatchPlanner.action(
                for: .unknown("wat"),
                userText: "/wat",
                statusText: "unused"
            ),
            .appendTranscript(WorkspaceSlashCommandTranscriptPlanner.unknown(
                userText: "/wat",
                name: "wat"
            ))
        )
    }
}
