import XCTest

final class ParityWorkspaceSlashTranscriptGateTests: QuillCodeParityTestCase {
    func testWorkspaceModelDelegatesSlashCommandTranscriptPlanning() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let slashText = try Self.appSourceText(named: "WorkspaceModelSlashCommands.swift")
        let actionExecutorText = try Self.appSourceText(named: "WorkspaceSlashCommandActionExecutor.swift")
        let plannerText = try Self.appSourceText(named: "WorkspaceSlashCommandTranscriptPlanner.swift")
        let appenderText = try Self.appSourceText(named: "WorkspaceLocalCommandTranscriptAppender.swift")
        let environmentPlannerText = try Self.appSourceText(named: "WorkspaceEnvironmentSlashCommandPlanner.swift")
        let localEnvironmentModelText = try Self.appSourceText(named: "WorkspaceModelLocalEnvironment.swift")
        let dispatchPlannerText = try Self.appSourceText(named: "WorkspaceSlashCommandDispatchPlanner.swift")

        let actionExecutorCalls = [
            "WorkspaceSlashCommandTranscriptPlanner.mode",
            "WorkspaceSlashCommandTranscriptPlanner.model",
            "WorkspaceSlashCommandTranscriptPlanner.renameThread",
            "WorkspaceSlashCommandTranscriptPlanner.renameProject",
            "WorkspaceSlashCommandTranscriptPlanner.sshProjectAdded",
            "WorkspaceSlashCommandTranscriptPlanner.workspaceCommandFailed"
        ]
        let scheduledCalls = [
            "WorkspaceSlashCommandTranscriptPlanner.threadFollowUpScheduled",
            "WorkspaceSlashCommandTranscriptPlanner.workspaceScheduleScheduled"
        ]
        let dispatchCalls = [
            "WorkspaceSlashCommandTranscriptPlanner.help",
            "WorkspaceSlashCommandTranscriptPlanner.status",
            "WorkspaceSlashCommandTranscriptPlanner.invalid",
            "WorkspaceSlashCommandTranscriptPlanner.unknown"
        ]

        Self.assertSource(plannerText, containsAll: [
            "struct WorkspaceLocalCommandTranscript",
            "struct WorkspaceSlashCommandTranscriptPlanner",
            "static func sshProjectAdded",
            "static func workspaceCommandFailed",
            "SlashCommandCatalog.helpText()"
        ])
        Self.assertSource(appenderText, containsAll: [
            "enum WorkspaceLocalCommandTranscriptAppender",
            "thread.messages.append(ChatMessage(role: .user",
            "thread.messages.append(ChatMessage(role: .assistant"
        ])
        Self.assertSource(environmentPlannerText, containsAll: [
            "struct WorkspaceEnvironmentSlashCommandPlanner",
            "WorkspaceSlashCommandTranscriptPlanner.environmentActions",
            "WorkspaceSlashCommandTranscriptPlanner.environmentActionNotFound"
        ])
        Self.assertSource(dispatchPlannerText, containsAll: dispatchCalls)
        Self.assertSource(slashText, containsAll: [
            "WorkspaceLocalCommandTranscriptAppender.append"
        ] + scheduledCalls)
        Self.assertSource(localEnvironmentModelText, containsAll: [
            "public func runLocalEnvironmentAction",
            "func runEnvironmentSlashCommand",
            "WorkspaceEnvironmentSlashCommandPlanner.plan"
        ])
        Self.assertSource(actionExecutorText, containsAll: actionExecutorCalls)
        Self.assertSource(modelText, excludesAll: actionExecutorCalls + scheduledCalls + dispatchCalls + [
            "public func runLocalEnvironmentAction",
            "func runEnvironmentSlashCommand",
            "WorkspaceLocalCommandTranscriptAppender.append",
            "WorkspaceEnvironmentSlashCommandPlanner.plan",
            "Could not rename this chat. Try /rename New chat title.",
            "Could not rename this project. Try /project rename New project name.",
            "Use SSH format user@host:/path or ssh://user@host/path.",
            "Scheduled a thread follow-up for",
            "Scheduled a workspace check for",
            "WorkspaceSlashCommandTranscriptPlanner.environmentActions",
            "WorkspaceSlashCommandTranscriptPlanner.environmentActionNotFound",
            "contextResolver.selectedLocalAction(matching:",
            "Local environment actions:",
            "No local environment action matches",
            "Unknown slash command",
            "thread.title = title",
            "ChatMessage(role: .user, content: userText)",
            "ChatMessage(role: .assistant, content: assistantText)"
        ])
        Self.assertSource(plannerText, excludesAll: [
            "memorySaved(",
            "memoryNotSaved(",
            "memorySavedSummary("
        ])
    }
}
