import Foundation
import QuillCodeAgent
import QuillCodeCore
import QuillCodePersistence

public struct QuillCodeCommandRunner: Sendable {
    public static let version = "0.1.0"

    private let parser: CLIArgumentParser
    private let runnerFactory: CLIAgentRunnerFactory
    private let interruptSource: any CLIInterruptSource
    private let mcpSessionPreparer: CLIMCPAgentSessionPreparer
    private let doctor: CLIDoctor

    public init(
        parser: CLIArgumentParser = CLIArgumentParser(),
        runnerFactory: @escaping CLIAgentRunnerFactory = CLIRuntimeFactory.make
    ) {
        self.init(
            parser: parser,
            runnerFactory: runnerFactory,
            interruptSource: ProcessCLIInterruptSource(),
            mcpSessionPreparer: CLIMCPAgentSessionPreparer(),
            doctor: CLIDoctor()
        )
    }

    init(
        parser: CLIArgumentParser,
        runnerFactory: @escaping CLIAgentRunnerFactory,
        interruptSource: any CLIInterruptSource,
        mcpSessionPreparer: CLIMCPAgentSessionPreparer = CLIMCPAgentSessionPreparer(),
        doctor: CLIDoctor = CLIDoctor()
    ) {
        self.parser = parser
        self.runnerFactory = runnerFactory
        self.interruptSource = interruptSource
        self.mcpSessionPreparer = mcpSessionPreparer
        self.doctor = doctor
    }

    public func run(
        arguments: [String],
        environment: [String: String] = ProcessInfo.processInfo.environment,
        currentDirectory: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
        input: any CLIInputReading = StandardCLIInput(),
        output: any CLIOutputWriting = FileHandleCLIOutput()
    ) async -> Int32 {
        let command: CLICommand
        do {
            command = try parser.parse(arguments, currentDirectory: currentDirectory)
        } catch {
            await output.writeStandardErrorLine("quill-code: \(error.localizedDescription)")
            return 2
        }

        do {
            switch command {
            case .help:
                await output.writeStandardOutput(Self.usage + "\n")
                return 0
            case .version:
                await output.writeStandardOutputLine("quill-code \(Self.version)")
                return 0
            case .auth(let auth, let home):
                try await runAuth(auth, home: home, output: output)
                return 0
            case .doctor(let request):
                return try await runDoctor(
                    request,
                    environment: environment,
                    currentDirectory: currentDirectory,
                    inputIsTerminal: input.isTerminal,
                    output: output
                )
            case .review(let request):
                return await CLIReviewCommand(
                    runnerFactory: runnerFactory,
                    interruptSource: interruptSource
                ).run(
                    request,
                    environment: environment,
                    input: input,
                    output: output
                )
            case .appServer(let request):
                return await runAppServer(
                    request,
                    environment: environment,
                    currentDirectory: currentDirectory,
                    input: input,
                    output: output
                )
            case .mcpServer(let request):
                return await runMCPServer(
                    request,
                    environment: environment,
                    currentDirectory: currentDirectory,
                    input: input,
                    output: output
                )
            case .run(let request):
                return await runAgent(
                    request,
                    environment: environment,
                    input: input,
                    output: output
                )
            }
        } catch {
            await output.writeStandardErrorLine("quill-code: \(error.localizedDescription)")
            return 1
        }
    }

    private func runDoctor(
        _ request: CLIDoctorRequest,
        environment: [String: String],
        currentDirectory: URL,
        inputIsTerminal: Bool,
        output: any CLIOutputWriting
    ) async throws -> Int32 {
        if request.showsHelp {
            await output.writeStandardOutput(CLIDoctorRenderer.help + "\n")
            return 0
        }
        let report = await doctor.collect(
            request: request,
            environment: environment,
            currentDirectory: currentDirectory,
            inputIsTerminal: inputIsTerminal
        )
        if request.emitsJSON {
            let json = try CLIDoctorRenderer.json(report)
            await output.writeStandardOutput(json)
        } else {
            await output.writeStandardOutput(
                CLIDoctorRenderer.human(report, request: request, environment: environment)
            )
        }
        return report.exitStatus
    }

    private func runAuth(
        _ command: CLIAuthCommand,
        home: URL?,
        output: any CLIOutputWriting
    ) async throws {
        let paths = home.map { QuillCodePaths(home: $0) } ?? QuillCodePaths()
        try paths.ensure()
        let store = FileSecretStore(directory: paths.secretsDirectory)
        switch command {
        case .status:
            let key = try store.read(QuillSecretKeys.trustedRouterAPIKey)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let status = key?.isEmpty == false
                ? "TrustedRouter key configured."
                : "TrustedRouter key not configured."
            await output.writeStandardOutputLine(status)
        case .setKey(let key):
            try store.write(key, for: QuillSecretKeys.trustedRouterAPIKey)
            await output.writeStandardOutputLine("TrustedRouter key saved.")
        case .clear:
            try store.delete(QuillSecretKeys.trustedRouterAPIKey)
            await output.writeStandardOutputLine("TrustedRouter key cleared.")
        }
    }

    private func runAppServer(
        _ request: CLIAppServerRequest,
        environment: [String: String],
        currentDirectory: URL,
        input: any CLIInputReading,
        output: any CLIOutputWriting
    ) async -> Int32 {
        do {
            let session = try AppServerSession(
                request: request,
                environment: environment,
                currentDirectory: currentDirectory,
                runnerFactory: runnerFactory,
                sink: { line in await output.writeStandardOutput(line) }
            )
            for try await line in input.lines(maxLineBytes: AppServerSession.maximumMessageBytes) {
                await session.receive(line)
            }
            await session.finishInput()
            await session.waitForActiveTurns()
            return 0
        } catch is CancellationError {
            await output.writeStandardErrorLine("quill-code app-server: interrupted")
            return 1
        } catch {
            await output.writeStandardErrorLine("quill-code app-server: \(error.localizedDescription)")
            return 1
        }
    }

    private func runMCPServer(
        _ request: CLIMCPServerRequest,
        environment: [String: String],
        currentDirectory: URL,
        input: any CLIInputReading,
        output: any CLIOutputWriting
    ) async -> Int32 {
        do {
            let session = try MCPServerSession(
                request: request,
                environment: environment,
                currentDirectory: currentDirectory,
                runnerFactory: runnerFactory,
                sink: { line in await output.writeStandardOutput(line) }
            )
            for try await line in input.lines(maxLineBytes: MCPServerSession.maximumMessageBytes) {
                await session.receive(line)
            }
            await session.finishInput()
            await session.waitForActiveCalls()
            return 0
        } catch is CancellationError {
            await output.writeStandardErrorLine("quill-code mcp-server: interrupted")
            return 1
        } catch {
            await output.writeStandardErrorLine("quill-code mcp-server: \(error.localizedDescription)")
            return 1
        }
    }

    private func runAgent(
        _ request: CLIRunRequest,
        environment: [String: String],
        input: any CLIInputReading,
        output: any CLIOutputWriting
    ) async -> Int32 {
        let reporter = CLIProgressReporter(emitsJSONLines: request.emitsJSONLines, output: output)
        var persistence: CLIRunPersistence?
        var mcpSession: CLIMCPAgentSession?
        let status: Int32
        do {
            if request.usedDeprecatedFullAuto {
                await output.writeStandardErrorLine(
                    "warning: --full-auto is deprecated; use --sandbox workspace-write"
                )
            }
            if request.style == .exec, !request.skipsGitRepositoryCheck {
                try CLIRepositoryGuard().validate(request.cwd)
            }

            let paths = request.home.map { QuillCodePaths(home: $0) } ?? QuillCodePaths()
            try paths.ensure()
            let appConfig = request.ignoresUserConfig
                ? AppConfig()
                : try ConfigStore(fileURL: paths.configFile).load()
            let prompt = try CLIPromptResolver().resolve(request: request, input: input)
            let schema = try request.outputSchemaURL.map(CLIOutputSchema.load)
            let threadStore = JSONThreadStore(directory: paths.threadsDirectory)
            let attachmentStore = ImageAttachmentStore(directory: paths.attachmentsDirectory)
            var thread = try initialThread(
                request: request,
                appConfig: appConfig,
                threadStore: threadStore
            )
            let runtime = CLIRuntimeConfiguration(
                request: request,
                appConfig: appConfig,
                paths: paths,
                imageAttachmentStore: attachmentStore,
                environment: environment
            )
            let preparedMCPSession = try await mcpSessionPreparer.prepare(
                configuration: runtime,
                threadID: thread.id
            )
            mcpSession = preparedMCPSession
            let attachments = try request.imageURLs.map {
                try attachmentStore.importImage(from: $0, threadID: thread.id)
            }
            if let schema {
                thread.messages.append(ChatMessage(role: .system, content: schema.modelInstruction))
            }
            let recordsUserMessage = attachments.isEmpty
            if !attachments.isEmpty {
                appendUserMessage(prompt, attachments: attachments, to: &thread)
            }

            let runner = preparedMCPSession.configure(
                runtime.applyingInvocationPolicy(to: try runnerFactory(runtime))
            )
            let runPersistence = CLIRunPersistence(
                store: request.ephemeral ? nil : threadStore
            )
            persistence = runPersistence
            await reporter.begin(thread: thread)
            let runThread = thread
            let result = try await runUntilInterrupted(source: interruptSource) {
                try await runner.send(
                    prompt,
                    in: runThread,
                    workspaceRoot: request.cwd,
                    recordUserMessage: recordsUserMessage,
                    onProgress: { snapshot in
                        await runPersistence.save(snapshot)
                        await reporter.report(snapshot)
                    }
                )
            }
            await runPersistence.save(result.thread)
            try await runPersistence.requireSuccess()

            guard let finalMessage = result.thread.messages.last(where: { $0.role == .assistant })?.content else {
                throw CLIError.noFinalMessage
            }
            try schema?.validate(finalMessage: finalMessage)
            if let outputURL = request.outputLastMessageURL {
                try writeFinalMessage(finalMessage, to: outputURL)
            }
            await reporter.finish(result)
            if !request.emitsJSONLines {
                await output.writeStandardOutputLine(finalMessage)
            }
            status = result.stopReason == .finished ? 0 : 1
        } catch is CancellationError {
            do {
                try await persistence?.requireSuccess()
                await reporter.interrupted()
            } catch {
                await reporter.fail(error)
            }
            status = 1
        } catch {
            await reporter.fail(error)
            status = 1
        }
        await mcpSession?.shutdown()
        return status
    }

    private func initialThread(
        request: CLIRunRequest,
        appConfig: AppConfig,
        threadStore: JSONThreadStore
    ) throws -> ChatThread {
        var thread: ChatThread
        switch request.resumeTarget {
        case .none:
            thread = ChatThread(
                mode: request.explicitMode ?? request.sandbox?.agentMode ?? appConfig.mode,
                model: request.model ?? appConfig.defaultModel
            )
        case .last:
            guard let latest = try threadStore.list().first else { throw CLIError.noSavedThreads }
            thread = latest
        case .id(let id):
            do {
                thread = try threadStore.load(id)
            } catch CocoaError.fileReadNoSuchFile {
                throw CLIError.threadNotFound(id)
            }
        }
        if let mode = request.explicitMode ?? request.sandbox?.agentMode { thread.mode = mode }
        if let model = request.model { thread.model = model }
        return thread
    }

    private func appendUserMessage(
        _ prompt: String,
        attachments: [ChatAttachment],
        to thread: inout ChatThread
    ) {
        thread.messages.append(ChatMessage(role: .user, content: prompt, attachments: attachments))
        let summary = prompt.isEmpty
            ? "Attached \(attachments.count) image\(attachments.count == 1 ? "" : "s")"
            : prompt
        thread.events.append(ThreadEvent(kind: .message, summary: summary))
        thread.title = prompt.isEmpty
            ? "Image: \(attachments.first?.displayName ?? "attachment")"
            : String(prompt.split(whereSeparator: \.isWhitespace).prefix(6).joined(separator: " "))
    }

    private func writeFinalMessage(_ message: String, to url: URL) throws {
        let parent = url.deletingLastPathComponent()
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: parent.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: parent.path])
        }
        try Data(message.utf8).write(to: url, options: .atomic)
    }

    public static let usage = """
    QuillCode command-line coding agent

    Usage:
      quill-code exec [OPTIONS] PROMPT
      quill-code exec resume (--last | THREAD_ID) [OPTIONS] PROMPT
      quill-code review (--uncommitted | --base BRANCH | --commit SHA | PROMPT) [OPTIONS]
      quill-code app-server [--listen stdio://] [--mock | --live]
      quill-code mcp-server [--mock | --live]
      quill-code [--home PATH] doctor [--json | --summary] [--all] [--no-color] [--ascii]
      quill-code [LEGACY OPTIONS] PROMPT
      quill-code [--home PATH] auth (status | set-key KEY | clear)

    Exec options:
      --json                         Emit JSON Lines events to stdout
      --ephemeral                    Do not persist the run transcript
      -o, --output-last-message PATH Write the final message to PATH
      --output-schema PATH           Require final JSON matching a bounded JSON Schema
      --sandbox read-only|workspace-write|danger-full-access
                                     Select host path access (default: read-only). Danger full access
                                     lets file tools and shell cwd operate outside the workspace.
      --ignore-user-config           Use built-in defaults instead of config.toml
      --ignore-rules                 Ignore persisted permission rules for this controlled run
      --skip-git-repo-check          Allow execution outside a Git repository
      -C, --cwd PATH                 Run in PATH
      -m, --model MODEL              Select a TrustedRouter model
      --image PATH                   Attach an image (repeat up to the attachment limit)
      --mock                         Use the deterministic local test model
      --live                         Use TrustedRouter (default for `exec`)

    Review:
      Run `quill-code review --help` for dedicated read-only review targets and options.

    Stdin:
      Use `-` as the prompt to read the full prompt from stdin. When a prompt argument is present,
      piped stdin is appended as explicitly delimited, untrusted context.

    App server:
      Uses newline-delimited JSON over stdio. Clients must send `initialize`, then the
      `initialized` notification, before thread and turn requests. `--mock` selects the
      deterministic local model for protocol tests; TrustedRouter is the default.

    MCP server:
      Exposes the Codex-compatible `codex` and `codex-reply` tools over JSON-RPC 2.0
      newline-delimited stdio. `--mock` selects the deterministic local model for protocol tests.

    Doctor:
      Generates bounded local installation, config, auth, runtime, Git, terminal, MCP,
      state, connectivity, app-server, and task-inventory diagnostics without mutating state.
    """
}

private actor CLIRunPersistence {
    private let store: JSONThreadStore?
    private var failure: String?

    init(store: JSONThreadStore?) {
        self.store = store
    }

    func save(_ thread: ChatThread) {
        guard failure == nil, let store else { return }
        do {
            try store.save(thread)
        } catch {
            failure = error.localizedDescription
        }
    }

    func requireSuccess() throws {
        if let failure {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSLocalizedDescriptionKey: failure])
        }
    }
}
