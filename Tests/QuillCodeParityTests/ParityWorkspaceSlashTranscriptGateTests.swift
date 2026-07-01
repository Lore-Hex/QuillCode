import XCTest

final class ParityWorkspaceSlashTranscriptGateTests: QuillCodeParityTestCase {
    func testWorkspaceModelDelegatesSlashCommandTranscriptPlanning() throws {
        let sources = try Sources()

        Self.assertSource(sources.planner, containsAll: Self.plannerContracts)
        Self.assertSource(sources.appender, containsAll: Self.appenderContracts)
        Self.assertSource(sources.environmentPlanner, containsAll: Self.environmentPlannerContracts)
        Self.assertSource(sources.dispatchPlanner, containsAll: Self.dispatchPlannerContracts)
        Self.assertSource(sources.composer, containsAll: Self.composerContracts)
        Self.assertSource(sources.localEnvironmentModel, containsAll: Self.localEnvironmentContracts)

        Self.assertSource(sources.model, excludesAll: Self.modelForbiddenTranscriptOwnership)
        Self.assertSource(sources.planner, excludesAll: Self.plannerForbiddenMemoryCopy)

        for plannerCall in Self.actionExecutorPlannerCalls {
            Self.assertSource(sources.actionExecutor, contains: plannerCall)
            Self.assertSource(sources.model, excludes: plannerCall)
        }

        for plannerCall in Self.composerPlannerCalls {
            Self.assertSource(sources.composer, contains: plannerCall)
            Self.assertSource(sources.model, excludes: plannerCall)
        }

        Self.assertSource(sources.model, excludesAll: Self.dispatchPlannerCalls)
    }
}

private extension ParityWorkspaceSlashTranscriptGateTests {
    struct Sources {
        let model: String
        let composer: String
        let actionExecutor: String
        let planner: String
        let appender: String
        let environmentPlanner: String
        let localEnvironmentModel: String
        let dispatchPlanner: String

        init() throws {
            model = try TestCase.appSourceText(named: "WorkspaceModel.swift")
            composer = try TestCase.appSourceText(named: "WorkspaceModelComposer.swift")
            actionExecutor = try TestCase.appSourceText(named: "WorkspaceSlashCommandActionExecutor.swift")
            planner = try TestCase.appSourceText(named: "WorkspaceSlashCommandTranscriptPlanner.swift")
            appender = try TestCase.appSourceText(named: "WorkspaceLocalCommandTranscriptAppender.swift")
            environmentPlanner = try TestCase.appSourceText(
                named: "WorkspaceEnvironmentSlashCommandPlanner.swift"
            )
            localEnvironmentModel = try TestCase.appSourceText(named: "WorkspaceModelLocalEnvironment.swift")
            dispatchPlanner = try TestCase.appSourceText(named: "WorkspaceSlashCommandDispatchPlanner.swift")
        }
    }

    typealias TestCase = ParityWorkspaceSlashTranscriptGateTests

    static let plannerContracts = [
        "struct WorkspaceLocalCommandTranscript",
        "struct WorkspaceSlashCommandTranscriptPlanner",
        "static func sshProjectAdded",
        "static func workspaceCommandFailed",
        "SlashCommandCatalog.helpText()"
    ]

    static let appenderContracts = [
        "enum WorkspaceLocalCommandTranscriptAppender",
        "thread.messages.append(ChatMessage(role: .user",
        "thread.messages.append(ChatMessage(role: .assistant"
    ]

    static let environmentPlannerContracts = [
        "struct WorkspaceEnvironmentSlashCommandPlanner",
        "WorkspaceSlashCommandTranscriptPlanner.environmentActions",
        "WorkspaceSlashCommandTranscriptPlanner.environmentActionNotFound"
    ]

    static let dispatchPlannerContracts = [
        "WorkspaceSlashCommandTranscriptPlanner.help",
        "WorkspaceSlashCommandTranscriptPlanner.status",
        "WorkspaceSlashCommandTranscriptPlanner.invalid",
        "WorkspaceSlashCommandTranscriptPlanner.unknown"
    ]

    static let composerContracts = [
        "WorkspaceLocalCommandTranscriptAppender.append"
    ]

    static let localEnvironmentContracts = [
        "public func runLocalEnvironmentAction",
        "func runEnvironmentSlashCommand",
        "WorkspaceEnvironmentSlashCommandPlanner.plan"
    ]

    static let actionExecutorPlannerCalls = [
        "WorkspaceSlashCommandTranscriptPlanner.mode",
        "WorkspaceSlashCommandTranscriptPlanner.model",
        "WorkspaceSlashCommandTranscriptPlanner.renameThread",
        "WorkspaceSlashCommandTranscriptPlanner.renameProject",
        "WorkspaceSlashCommandTranscriptPlanner.sshProjectAdded",
        "WorkspaceSlashCommandTranscriptPlanner.workspaceCommandFailed"
    ]

    static let composerPlannerCalls = [
        "WorkspaceSlashCommandTranscriptPlanner.threadFollowUpScheduled",
        "WorkspaceSlashCommandTranscriptPlanner.workspaceScheduleScheduled"
    ]

    static let dispatchPlannerCalls = [
        "WorkspaceSlashCommandTranscriptPlanner.help",
        "WorkspaceSlashCommandTranscriptPlanner.status",
        "WorkspaceSlashCommandTranscriptPlanner.invalid",
        "WorkspaceSlashCommandTranscriptPlanner.unknown"
    ]

    static let modelForbiddenTranscriptOwnership = [
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
    ]

    static let plannerForbiddenMemoryCopy = [
        "memorySaved(",
        "memoryNotSaved(",
        "memorySavedSummary("
    ]
}
