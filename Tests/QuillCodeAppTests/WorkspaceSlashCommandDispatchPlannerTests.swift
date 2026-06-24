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
                for: .model("/synth"),
                userText: "/model /synth",
                statusText: "unused"
            ),
            .setModel("/synth", userText: "/model /synth")
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
                for: .remember("Use Synth"),
                userText: "/remember Use Synth",
                statusText: "unused"
            ),
            .remember("Use Synth", userText: "/remember Use Synth")
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
                for: .workspaceCommand("toggle-browser"),
                userText: "/browser",
                statusText: "unused"
            ),
            .workspaceCommand("toggle-browser", userText: "/browser")
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
