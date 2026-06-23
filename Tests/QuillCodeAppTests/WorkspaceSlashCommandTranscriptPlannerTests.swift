import XCTest
import QuillCodeCore
@testable import QuillCodeApp

final class WorkspaceSlashCommandTranscriptPlannerTests: XCTestCase {
    func testHelpAndStatusTranscriptsUseExpectedTitles() {
        let help = WorkspaceSlashCommandTranscriptPlanner.help(userText: "/help")
        XCTAssertEqual(help.userText, "/help")
        XCTAssertEqual(help.title, "Slash commands")
        XCTAssertTrue(help.assistantText.contains("/status"))

        let status = WorkspaceSlashCommandTranscriptPlanner.status(
            userText: "/status",
            statusText: "Project: QuillCode"
        )
        XCTAssertEqual(status.title, "Status")
        XCTAssertEqual(status.assistantText, "Project: QuillCode")
    }

    func testModeAndModelTranscriptsUseSharedModeLabel() {
        XCTAssertEqual(
            WorkspaceSlashCommandTranscriptPlanner.mode(userText: "/mode read-only", mode: .readOnly).assistantText,
            "Mode set to Read-only."
        )
        XCTAssertEqual(
            WorkspaceSlashCommandTranscriptPlanner.mode(userText: "/mode review", mode: .review).assistantText,
            "Mode set to Review."
        )
        XCTAssertEqual(
            WorkspaceSlashCommandTranscriptPlanner.model(
                userText: "/model trustedrouter/fusion",
                model: TrustedRouterDefaults.fusionModel
            ).assistantText,
            "Model set to \(TrustedRouterDefaults.fusionModel)."
        )
    }

    func testRenameTranscriptsTrimSuccessfulNamesAndPreserveFallbackCopy() {
        XCTAssertEqual(
            WorkspaceSlashCommandTranscriptPlanner.renameThread(
                userText: "/rename  Launch plan  ",
                requestedTitle: "  Launch plan  ",
                succeeded: true
            ).assistantText,
            "Renamed chat to Launch plan."
        )
        XCTAssertEqual(
            WorkspaceSlashCommandTranscriptPlanner.renameThread(
                userText: "/rename",
                requestedTitle: "",
                succeeded: false
            ).assistantText,
            "Could not rename this chat. Try /rename New chat title."
        )
        XCTAssertEqual(
            WorkspaceSlashCommandTranscriptPlanner.renameProject(
                userText: "/project rename  QuillCode  ",
                requestedName: "  QuillCode  ",
                succeeded: true
            ).assistantText,
            "Renamed project to QuillCode."
        )
        XCTAssertEqual(
            WorkspaceSlashCommandTranscriptPlanner.renameProject(
                userText: "/project rename",
                requestedName: "",
                succeeded: false
            ).assistantText,
            "Could not rename this project. Try /project rename New project name."
        )
    }

    func testSSHProjectTranscriptsDescribeSuccessAndFallback() {
        XCTAssertEqual(
            WorkspaceSlashCommandTranscriptPlanner.sshProjectAdded(
                userText: "/ssh quill@feather:/Quill",
                projectName: "Feather",
                displayPath: "quill@feather:/Quill"
            ),
            WorkspaceLocalCommandTranscript(
                userText: "/ssh quill@feather:/Quill",
                assistantText: "Added SSH Remote Feather at quill@feather:/Quill. Shell, file read/write, apply patch, git status/diff/stage/restore/commit/push/PR checkout/reviewers/labels/merge/worktree, and project context refresh run through SSH.",
                title: "Add SSH Remote"
            )
        )
        XCTAssertEqual(
            WorkspaceSlashCommandTranscriptPlanner.sshProjectFailed(userText: "/ssh", message: nil).assistantText,
            "Use SSH format user@host:/path or ssh://user@host/path."
        )
        XCTAssertEqual(
            WorkspaceSlashCommandTranscriptPlanner.sshProjectFailed(
                userText: "/ssh bad",
                message: "Invalid remote"
            ).assistantText,
            "Invalid remote"
        )
    }

    func testScheduleTranscriptsUseConcreteDescriptionsAndFallbackCopy() {
        XCTAssertEqual(
            WorkspaceSlashCommandTranscriptPlanner.threadFollowUpScheduled(
                userText: "/follow-up in 45 minutes",
                scheduleDescription: "In 45 minutes"
            ).assistantText,
            "Scheduled a thread follow-up for In 45 minutes."
        )
        XCTAssertEqual(
            WorkspaceSlashCommandTranscriptPlanner.threadFollowUpFailed(
                userText: "/follow-up eventually",
                message: nil
            ).assistantText,
            "Could not schedule this follow-up."
        )
        XCTAssertEqual(
            WorkspaceSlashCommandTranscriptPlanner.workspaceScheduleScheduled(
                userText: "/workspace-check tomorrow",
                scheduleDescription: "Tomorrow at 9:00 AM"
            ).assistantText,
            "Scheduled a workspace check for Tomorrow at 9:00 AM."
        )
        XCTAssertEqual(
            WorkspaceSlashCommandTranscriptPlanner.workspaceScheduleFailed(
                userText: "/workspace-check",
                message: "Select a project first."
            ).assistantText,
            "Select a project first."
        )
    }

    func testGenericSlashCommandTranscripts() {
        XCTAssertEqual(
            WorkspaceSlashCommandTranscriptPlanner.workspaceCommandFailed(userText: "/browser").assistantText,
            "Could not run /browser. Try /help."
        )
        XCTAssertEqual(
            WorkspaceSlashCommandTranscriptPlanner.invalid(userText: "/mode", message: "Missing mode"),
            WorkspaceLocalCommandTranscript(
                userText: "/mode",
                assistantText: "Missing mode",
                title: "Slash command"
            )
        )
        XCTAssertEqual(
            WorkspaceSlashCommandTranscriptPlanner.unknown(userText: "/wat", name: "wat").assistantText,
            "Unknown slash command '/wat'. Try /help."
        )
    }
}
