import Foundation
import QuillCodeAgent
import QuillCodeCore
import QuillCodePersistence
import QuillCodeReview

struct CLIReviewCommand: Sendable {
    let runnerFactory: CLIAgentRunnerFactory
    let interruptSource: any CLIInterruptSource
    var promptResolver = CLIReviewPromptResolver()

    func run(
        _ request: CLIReviewRequest,
        environment: [String: String],
        input: any CLIInputReading,
        output: any CLIOutputWriting
    ) async -> Int32 {
        if request.showsHelp {
            await output.writeStandardOutput(Self.help + "\n")
            return 0
        }

        let reporter = CLIProgressReporter(emitsJSONLines: false, output: output)
        do {
            try CLIRepositoryGuard().validate(request.cwd)
            let paths = request.home.map { QuillCodePaths(home: $0) } ?? QuillCodePaths()
            try paths.ensure()
            let appConfig = request.ignoresUserConfig
                ? AppConfig()
                : try ConfigStore(fileURL: paths.configFile).load()
            let reviewRequest = try promptResolver.resolve(request: request, input: input)
            let prompt = WorkspaceCodeReviewPromptBuilder(request: reviewRequest).prompt()
            let thread = ChatThread(
                title: reviewRequest.transcriptPrompt,
                mode: .readOnly,
                model: request.model ?? appConfig.reviewModel ?? appConfig.defaultModel
            )
            let runtimeRequest = CLIRunRequest(
                style: .exec,
                prompt: prompt,
                live: request.live,
                apiKey: request.apiKey,
                model: thread.model,
                baseURL: request.baseURL,
                cwd: request.cwd,
                home: request.home,
                ephemeral: true,
                sandbox: .readOnly,
                ignoresUserConfig: request.ignoresUserConfig,
                ignoresPermissionRules: true,
                skipsGitRepositoryCheck: false
            )
            let runtime = CLIRuntimeConfiguration(
                request: runtimeRequest,
                appConfig: appConfig,
                paths: paths,
                imageAttachmentStore: ImageAttachmentStore(directory: paths.attachmentsDirectory),
                environment: environment
            )
            let collector = WorkspaceCodeReviewReportCollector()
            let baseRunner = runtime.applyingInvocationPolicy(to: try runnerFactory(runtime))
            let reviewer = WorkspaceCodeReviewRunner.configure(
                baseRunner,
                reportCollector: collector
            )

            await reporter.begin(thread: thread)
            let result = try await runUntilInterrupted(source: interruptSource) {
                try await reviewer.send(
                    prompt,
                    in: thread,
                    workspaceRoot: request.cwd,
                    onProgress: { snapshot in await reporter.report(snapshot) }
                )
            }
            await reporter.finish(result)
            guard result.stopReason == .finished else {
                throw CLIReviewCommandError.incomplete(result.stopReason)
            }
            guard let report = await collector.report else {
                throw CLIReviewCommandError.missingReport
            }
            await output.writeStandardOutputLine(report.markdown(title: reviewRequest.title))
            return 0
        } catch is CancellationError {
            await reporter.interrupted()
            return 1
        } catch {
            await reporter.fail(error)
            return 1
        }
    }

    static let help = """
    Run a code review non-interactively

    Usage:
      quill-code review --uncommitted [OPTIONS]
      quill-code review --base BRANCH [OPTIONS]
      quill-code review --commit SHA [--title TITLE] [OPTIONS]
      quill-code review [OPTIONS] PROMPT
      quill-code review [OPTIONS] -

    Review targets (choose exactly one):
      --uncommitted                 Review staged, unstaged, and untracked changes
      --base BRANCH                 Review changes against the given base branch
      --commit SHA                  Review the changes introduced by a commit
      --title TITLE                 Commit title shown in the summary; requires --commit
      PROMPT                        Custom review instructions; use - to read stdin

    Runtime options:
      -C, --cwd PATH                Review the Git repository at PATH
      -m, --model MODEL             Select a TrustedRouter review model
      --ignore-user-config          Use built-in defaults instead of config.toml
      --mock                        Use the deterministic local test model
      --live                        Use TrustedRouter (default)
      -h, --help                    Show this help
    """
}

private enum CLIReviewCommandError: LocalizedError {
    case incomplete(AgentRunStopReason)
    case missingReport

    var errorDescription: String? {
        switch self {
        case .incomplete(let reason):
            "The reviewer stopped before completing its report (\(reason))."
        case .missingReport:
            "The reviewer returned without submitting the required structured report."
        }
    }
}
