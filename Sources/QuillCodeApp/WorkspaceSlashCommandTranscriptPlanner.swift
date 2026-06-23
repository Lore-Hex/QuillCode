import Foundation
import QuillCodeCore

struct WorkspaceLocalCommandTranscript: Sendable, Hashable {
    let userText: String
    let assistantText: String
    let title: String
}

struct WorkspaceSlashCommandTranscriptPlanner {
    static func help(userText: String) -> WorkspaceLocalCommandTranscript {
        transcript(
            userText: userText,
            assistantText: SlashCommandCatalog.helpText(),
            title: "Slash commands"
        )
    }

    static func status(userText: String, statusText: String) -> WorkspaceLocalCommandTranscript {
        transcript(
            userText: userText,
            assistantText: statusText,
            title: "Status"
        )
    }

    static func mode(userText: String, mode: AgentMode) -> WorkspaceLocalCommandTranscript {
        transcript(
            userText: userText,
            assistantText: "Mode set to \(WorkspaceStatusTextBuilder.modeLabel(mode)).",
            title: "Set mode"
        )
    }

    static func model(userText: String, model: String) -> WorkspaceLocalCommandTranscript {
        transcript(
            userText: userText,
            assistantText: "Model set to \(model).",
            title: "Set model"
        )
    }

    static func renameThread(userText: String, requestedTitle: String, succeeded: Bool) -> WorkspaceLocalCommandTranscript {
        transcript(
            userText: userText,
            assistantText: succeeded
                ? "Renamed chat to \(requestedTitle.trimmingCharacters(in: .whitespacesAndNewlines))."
                : "Could not rename this chat. Try /rename New chat title.",
            title: "Rename chat"
        )
    }

    static func renameProject(userText: String, requestedName: String, succeeded: Bool) -> WorkspaceLocalCommandTranscript {
        transcript(
            userText: userText,
            assistantText: succeeded
                ? "Renamed project to \(requestedName.trimmingCharacters(in: .whitespacesAndNewlines))."
                : "Could not rename this project. Try /project rename New project name.",
            title: "Rename project"
        )
    }

    static func sshProjectAdded(userText: String, projectName: String, displayPath: String) -> WorkspaceLocalCommandTranscript {
        transcript(
            userText: userText,
            assistantText: "Added SSH Remote \(projectName) at \(displayPath). Shell, file read/write, apply patch, git status/diff/stage/restore/commit/push/PR checkout/reviewers/labels/merge/worktree, and project context refresh run through SSH.",
            title: "Add SSH Remote"
        )
    }

    static func sshProjectFailed(userText: String, message: String?) -> WorkspaceLocalCommandTranscript {
        transcript(
            userText: userText,
            assistantText: message ?? "Use SSH format user@host:/path or ssh://user@host/path.",
            title: "Add SSH Remote"
        )
    }

    static func threadFollowUpScheduled(userText: String, scheduleDescription: String) -> WorkspaceLocalCommandTranscript {
        transcript(
            userText: userText,
            assistantText: "Scheduled a thread follow-up for \(scheduleDescription).",
            title: "Schedule follow-up"
        )
    }

    static func threadFollowUpFailed(userText: String, message: String?) -> WorkspaceLocalCommandTranscript {
        transcript(
            userText: userText,
            assistantText: message ?? "Could not schedule this follow-up.",
            title: "Schedule follow-up"
        )
    }

    static func workspaceScheduleScheduled(userText: String, scheduleDescription: String) -> WorkspaceLocalCommandTranscript {
        transcript(
            userText: userText,
            assistantText: "Scheduled a workspace check for \(scheduleDescription).",
            title: "Schedule workspace check"
        )
    }

    static func workspaceScheduleFailed(userText: String, message: String?) -> WorkspaceLocalCommandTranscript {
        transcript(
            userText: userText,
            assistantText: message ?? "Could not schedule this workspace check.",
            title: "Schedule workspace check"
        )
    }

    static func workspaceCommandFailed(userText: String) -> WorkspaceLocalCommandTranscript {
        transcript(
            userText: userText,
            assistantText: "Could not run /\(userText.dropFirst()). Try /help.",
            title: "Slash command"
        )
    }

    static func invalid(userText: String, message: String) -> WorkspaceLocalCommandTranscript {
        transcript(
            userText: userText,
            assistantText: message,
            title: "Slash command"
        )
    }

    static func unknown(userText: String, name: String) -> WorkspaceLocalCommandTranscript {
        transcript(
            userText: userText,
            assistantText: "Unknown slash command '/\(name)'. Try /help.",
            title: "Slash command"
        )
    }

    private static func transcript(userText: String, assistantText: String, title: String) -> WorkspaceLocalCommandTranscript {
        WorkspaceLocalCommandTranscript(
            userText: userText,
            assistantText: assistantText,
            title: title
        )
    }
}
