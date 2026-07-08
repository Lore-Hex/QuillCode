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
            assistantText: "Model set to \(modelConfirmationLabel(for: model)).",
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
            assistantText: "Added SSH Remote \(projectName) at \(displayPath). Shell, file read/list/write, apply patch, git status/diff/stage/restore/commit/push/PR checkout/reviewers/labels/merge/worktree, and project context refresh run through SSH.",
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

    static func monitorScheduled(
        userText: String,
        title: String,
        sourceLabel: String,
        sourcePath: String
    ) -> WorkspaceLocalCommandTranscript {
        transcript(
            userText: userText,
            assistantText: "Created \(title) using \(sourceLabel): \(sourcePath).",
            title: "Create monitor"
        )
    }

    static func monitorFailed(userText: String, message: String?) -> WorkspaceLocalCommandTranscript {
        transcript(
            userText: userText,
            assistantText: message ?? "Could not create this monitor. Try `/monitor file path`, `/monitor directory path`, `/monitor last-modified https://example.com`, or `/monitor feed https://example.com/feed.xml`.",
            title: "Create monitor"
        )
    }

    static func browserOpened(userText: String, title: String, url: String) -> WorkspaceLocalCommandTranscript {
        let label = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let location = url.trimmingCharacters(in: .whitespacesAndNewlines)
        let page = label.isEmpty || label == location ? location : "\(label) at \(location)"
        return transcript(
            userText: userText,
            assistantText: "Opened browser preview for \(page).",
            title: "Open browser"
        )
    }

    static func browserOpenFailed(userText: String, message: String?) -> WorkspaceLocalCommandTranscript {
        transcript(
            userText: userText,
            assistantText: message ?? "Enter an http, https, file, localhost, or project file URL.",
            title: "Open browser"
        )
    }

    static func browserSessionRequested(userText: String, title: String, url: String) -> WorkspaceLocalCommandTranscript {
        let label = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let location = url.trimmingCharacters(in: .whitespacesAndNewlines)
        let page = label.isEmpty || label == location ? location : "\(label) at \(location)"
        return transcript(
            userText: userText,
            assistantText: "Opened browser session for \(page).",
            title: "Open browser session"
        )
    }

    static func browserSessionFailed(userText: String, message: String?) -> WorkspaceLocalCommandTranscript {
        transcript(
            userText: userText,
            assistantText: message ?? "Enter an http, https, file, localhost, or project file URL.",
            title: "Open browser session"
        )
    }

    static func environmentScheduleScheduled(
        userText: String,
        actionTitle: String,
        scheduleDescription: String
    ) -> WorkspaceLocalCommandTranscript {
        transcript(
            userText: userText,
            assistantText: "Scheduled \(actionTitle) for \(scheduleDescription).",
            title: "Schedule local environment action"
        )
    }

    static func environmentScheduleFailed(userText: String, message: String?) -> WorkspaceLocalCommandTranscript {
        transcript(
            userText: userText,
            assistantText: message ?? "Could not schedule this local environment action. Try `/env schedule Build in 30 minutes`.",
            title: "Schedule local environment action"
        )
    }

    static func workspaceCommandFailed(userText: String) -> WorkspaceLocalCommandTranscript {
        transcript(
            userText: userText,
            assistantText: "Could not run /\(userText.dropFirst()). Try /help.",
            title: "Slash command"
        )
    }

    static func environmentActions(userText: String, actions: [LocalEnvironmentAction]) -> WorkspaceLocalCommandTranscript {
        let message: String
        if actions.isEmpty {
            message = "No local environment actions found. Add scripts under `.quillcode/actions` or `.quillcode/local-env`."
        } else {
            let rows = actions
                .map(environmentActionRow)
                .joined(separator: "\n")
            message = "Local environment actions:\n\(rows)"
        }
        return transcript(
            userText: userText,
            assistantText: message,
            title: "Local environment actions"
        )
    }

    static func environmentActionNotFound(userText: String, query: String) -> WorkspaceLocalCommandTranscript {
        transcript(
            userText: userText,
            assistantText: "No local environment action matches `\(query)`. Run `/env` to see available actions.",
            title: "Local environment actions"
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

    private static func environmentActionRow(_ action: LocalEnvironmentAction) -> String {
        let detail = action.detail.map { " — \($0)" } ?? ""
        let cwd = action.workingDirectory.map { " — cwd: \($0)" } ?? ""
        let timeout = action.timeoutSeconds.map { " — timeout: \($0)s" } ?? ""
        return "- `/env \(action.title)` — \(action.relativePath)\(cwd)\(timeout)\(detail)"
    }

    private static func modelConfirmationLabel(for model: String) -> String {
        let modelID = TrustedRouterDefaults.canonicalModelID(model)
        guard TrustedRouterDefaults.recommendedRank(for: modelID) != nil else {
            return modelID
        }
        let displayName = TrustedRouterDefaults.displayName(fromModelID: modelID)
        let preferredID = TrustedRouterDefaults.preferredDisplayModelID(modelID)
        return "\(displayName) (\(preferredID))"
    }

    private static func transcript(userText: String, assistantText: String, title: String) -> WorkspaceLocalCommandTranscript {
        WorkspaceLocalCommandTranscript(
            userText: userText,
            assistantText: assistantText,
            title: title
        )
    }
}
