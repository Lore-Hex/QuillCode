import XCTest
import QuillCodeAgent
import QuillCodeCore
import QuillCodePersistence
import QuillCodeSafety
import QuillComputerUseKit
@testable import QuillCodeApp

@MainActor
final class WorkspaceModelTests: XCTestCase {
    func testNewChatSelectsThreadAndRefreshesTopBar() {
        let project = ProjectRef(name: "QuillCode", path: "/tmp/QuillCode")
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(projects: [project]))

        let id = model.newChat(projectID: project.id)

        XCTAssertEqual(model.root.selectedThreadID, id)
        XCTAssertEqual(model.root.topBar.projectName, "QuillCode")
        XCTAssertEqual(model.root.topBar.threadTitle, "New chat")
        XCTAssertEqual(model.root.topBar.model, TrustedRouterDefaults.defaultModel)
        XCTAssertEqual(model.root.topBar.mode, .auto)
    }

    func testSelectingProjectControlsNextChatAndWorkspaceRoot() throws {
        let root = try makeTempDirectory()
        let model = QuillCodeWorkspaceModel()

        let projectID = model.addProject(path: root, name: "QuillCode")
        model.selectProject(projectID)
        let threadID = model.newChat()

        XCTAssertEqual(model.root.selectedProjectID, projectID)
        XCTAssertEqual(model.root.selectedThreadID, threadID)
        XCTAssertEqual(model.selectedThread?.projectID, projectID)
        XCTAssertEqual(model.selectedProject?.name, "QuillCode")
        XCTAssertEqual(model.activeWorkspaceRoot?.path, root.standardizedFileURL.path)
        XCTAssertEqual(model.root.topBar.projectName, "QuillCode")
    }

    func testProjectLifecycleActionsRenameRefreshNewChatAndRemove() throws {
        let root = try makeTempDirectory()
        try "Use focused tests.".write(
            to: root.appendingPathComponent("AGENTS.md"),
            atomically: true,
            encoding: .utf8
        )
        let model = QuillCodeWorkspaceModel()
        let projectID = model.addProject(path: root, name: "Original")
        let threadID = model.newChat(projectID: projectID)

        XCTAssertTrue(model.renameProject(projectID, to: "Renamed Project"))
        XCTAssertEqual(model.selectedProject?.name, "Renamed Project")
        XCTAssertEqual(model.root.topBar.projectName, "Renamed Project")

        XCTAssertTrue(model.refreshProjectContext(projectID))
        XCTAssertEqual(model.selectedThread?.instructions.map(\.title), ["Project AGENTS.md"])
        XCTAssertEqual(model.selectedThread?.events.last?.summary, "Refreshed project context")

        XCTAssertTrue(model.runWorkspaceCommand("project-new-chat", workspaceRoot: root))
        XCTAssertNotEqual(model.root.selectedThreadID, threadID)
        XCTAssertEqual(model.selectedThread?.projectID, projectID)

        XCTAssertTrue(model.runWorkspaceCommand("project-remove", workspaceRoot: root))
        XCTAssertTrue(model.root.projects.isEmpty)
        XCTAssertNil(model.root.selectedProjectID)
        XCTAssertNil(model.selectedThread?.projectID)
        XCTAssertNil(model.activeWorkspaceRoot)
    }

    func testNewChatIgnoresUnknownProjectID() {
        let model = QuillCodeWorkspaceModel()

        let threadID = model.newChat(projectID: UUID())

        XCTAssertEqual(model.root.selectedThreadID, threadID)
        XCTAssertNil(model.root.selectedProjectID)
        XCTAssertNil(model.selectedThread?.projectID)
        XCTAssertNil(model.root.topBar.projectName)
    }

    func testForkFromLastCreatesBoundedThreadFromLatestUserTurn() throws {
        let project = ProjectRef(name: "QuillCode", path: "/tmp/QuillCode")
        let instructions = [
            ProjectInstruction(
                path: "AGENTS.md",
                title: "Project AGENTS.md",
                content: "Prefer focused tests.",
                byteCount: 21
            )
        ]
        let source = ChatThread(
            title: "Long thread",
            projectID: project.id,
            mode: .review,
            model: "z-ai/glm-5.2",
            messages: [
                .init(role: .user, content: "old question"),
                .init(role: .assistant, content: "old answer"),
                .init(role: .user, content: "latest question"),
                .init(role: .tool, content: #"{"result":"hidden continuation feedback"}"#),
                .init(role: .assistant, content: "latest answer")
            ],
            instructions: instructions
        )
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            projects: [project],
            selectedProjectID: project.id,
            threads: [source],
            selectedThreadID: source.id
        ))

        let forkID = try XCTUnwrap(model.forkFromLast())
        let fork = try XCTUnwrap(model.root.threads.first { $0.id == forkID })

        XCTAssertEqual(fork.title, "Fork: Long thread")
        XCTAssertEqual(fork.projectID, project.id)
        XCTAssertEqual(fork.mode, .review)
        XCTAssertEqual(fork.model, "z-ai/glm-5.2")
        XCTAssertEqual(fork.instructions, instructions)
        XCTAssertEqual(fork.messages.map(\.content), ["latest question", "latest answer"])
        XCTAssertFalse(fork.messages.contains { $0.role == .tool })
        XCTAssertEqual(fork.events.first?.kind, .notice)
        XCTAssertEqual(fork.events.first?.payloadJSON, source.id.uuidString)
        XCTAssertEqual(model.root.selectedThreadID, forkID)
        XCTAssertEqual(model.root.selectedProjectID, project.id)
    }

    func testWorkspaceCommandForkFromLastSelectsFork() throws {
        let source = ChatThread(title: "Active", messages: [
            .init(role: .user, content: "run whoami"),
            .init(role: .assistant, content: "Output:\nquill")
        ])
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            threads: [source],
            selectedThreadID: source.id
        ))

        XCTAssertTrue(model.runWorkspaceCommand("fork-from-last", workspaceRoot: try makeTempDirectory()))

        XCTAssertEqual(model.selectedThread?.title, "Fork: Active")
        XCTAssertEqual(model.selectedThread?.messages.map(\.content), ["run whoami", "Output:\nquill"])
    }

    func testWorkspaceCommandCompactContextCreatesBoundedThread() throws {
        let project = ProjectRef(name: "QuillCode", path: "/tmp/QuillCode")
        let instructions = [
            ProjectInstruction(
                path: "AGENTS.md",
                title: "Project AGENTS.md",
                content: "Use Swift.",
                byteCount: 10
            )
        ]
        let source = ChatThread(
            title: "Long context",
            projectID: project.id,
            mode: .review,
            model: "z-ai/glm-5.2",
            messages: [
                .init(role: .user, content: "old question one"),
                .init(role: .assistant, content: "old answer one"),
                .init(role: .user, content: "old question two"),
                .init(role: .assistant, content: "old answer two"),
                .init(role: .user, content: "latest request"),
                .init(role: .tool, content: #"{"result":"hidden continuation feedback"}"#),
                .init(role: .assistant, content: "latest answer")
            ],
            instructions: instructions
        )
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            projects: [project],
            selectedProjectID: project.id,
            threads: [source],
            selectedThreadID: source.id
        ))

        XCTAssertTrue(model.runWorkspaceCommand("compact-context", workspaceRoot: try makeTempDirectory()))
        let compacted = try XCTUnwrap(model.selectedThread)

        XCTAssertEqual(compacted.title, "Compact: Long context")
        XCTAssertEqual(compacted.projectID, project.id)
        XCTAssertEqual(compacted.mode, .review)
        XCTAssertEqual(compacted.model, "z-ai/glm-5.2")
        XCTAssertEqual(compacted.instructions, instructions)
        XCTAssertEqual(compacted.messages.count, 3)
        XCTAssertTrue(compacted.messages[0].content.contains("Context compacted from \"Long context\""))
        XCTAssertTrue(compacted.messages[0].content.contains("summarized 4 earlier messages"))
        XCTAssertEqual(compacted.messages[1].content, "latest request")
        XCTAssertEqual(compacted.messages[2].content, "latest answer")
        XCTAssertFalse(compacted.messages.contains { $0.role == .tool })
        XCTAssertFalse(compacted.messages[0].content.contains("hidden continuation feedback"))
        XCTAssertEqual(compacted.events.first?.kind, .notice)
        XCTAssertEqual(compacted.events.first?.payloadJSON, source.id.uuidString)
    }

    func testSlashCommandsRouteToWorkspaceActions() async throws {
        let root = try makeTempGitRepoWithInitialCommit()
        let model = QuillCodeWorkspaceModel()
        let projectID = model.addProject(path: root, name: "Slash Project")
        model.selectProject(projectID)

        model.setDraft("/terminal")
        await model.submitComposer(workspaceRoot: root)
        XCTAssertTrue(model.terminal.isVisible)

        model.setDraft("/browser")
        await model.submitComposer(workspaceRoot: root)
        XCTAssertTrue(model.browser.isVisible)

        model.setDraft("/worktrees")
        await model.submitComposer(workspaceRoot: root)
        XCTAssertEqual(model.currentToolCards.last?.title, "host.git.worktree.list")

        model.setDraft("/pr")
        await model.submitComposer(workspaceRoot: root)
        XCTAssertEqual(model.composer.draft, "Create a pull request titled ")

        model.setDraft("/project rename Slash Renamed")
        await model.submitComposer(workspaceRoot: root)
        XCTAssertEqual(model.selectedProject?.name, "Slash Renamed")
        XCTAssertEqual(model.selectedThread?.messages.last?.content, "Renamed project to Slash Renamed.")

        model.setDraft("/project new")
        await model.submitComposer(workspaceRoot: root)
        XCTAssertEqual(model.selectedThread?.projectID, projectID)
    }

    func testSlashEnvironmentActionListsAndRunsByName() async throws {
        let root = try makeTempDirectory()
        let actionsDirectory = root.appendingPathComponent(".quillcode/actions")
        try FileManager.default.createDirectory(at: actionsDirectory, withIntermediateDirectories: true)
        try "printf slash-env-ok".write(
            to: actionsDirectory.appendingPathComponent("bootstrap-env.sh"),
            atomically: true,
            encoding: .utf8
        )

        let model = QuillCodeWorkspaceModel()
        let projectID = model.addProject(path: root, name: "Slash Env Project")
        model.selectProject(projectID)

        model.setDraft("/env")
        await model.submitComposer(workspaceRoot: root)
        XCTAssertEqual(model.selectedThread?.title, "Local environment actions")
        XCTAssertTrue(model.selectedThread?.messages.last?.content.contains("/env Bootstrap Env") == true)

        model.setDraft("/env bootstrap env")
        await model.submitComposer(workspaceRoot: root)
        let card = try XCTUnwrap(model.currentToolCards.last)
        XCTAssertEqual(card.title, "host.shell.run")
        let outputJSON = try XCTUnwrap(card.outputJSON)
        let result = try JSONHelpers.decode(ToolResult.self, from: outputJSON)
        XCTAssertEqual(result.stdout, "slash-env-ok")
    }

    func testSelectingProjectSelectsNewestThreadForThatProject() {
        let firstProject = ProjectRef(name: "One", path: "/tmp/one")
        let secondProject = ProjectRef(name: "Two", path: "/tmp/two")
        let older = ChatThread(
            title: "Older",
            projectID: firstProject.id,
            updatedAt: Date(timeIntervalSince1970: 1)
        )
        let newer = ChatThread(
            title: "Newer",
            projectID: firstProject.id,
            updatedAt: Date(timeIntervalSince1970: 2)
        )
        let other = ChatThread(title: "Other", projectID: secondProject.id)
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            projects: [firstProject, secondProject],
            threads: [older, newer, other]
        ))

        model.selectProject(firstProject.id)

        XCTAssertEqual(model.root.selectedProjectID, firstProject.id)
        XCTAssertEqual(model.root.selectedThreadID, newer.id)
        XCTAssertEqual(model.root.topBar.threadTitle, "Newer")
        XCTAssertEqual(model.root.topBar.projectName, "One")
        XCTAssertEqual(model.selectedThread?.title, "Newer")
    }

    func testSubmitComposerRunsToolAndBuildsToolCard() async throws {
        let root = try makeTempDirectory()
        let model = QuillCodeWorkspaceModel()

        model.setDraft("run whoami")
        await model.submitComposer(workspaceRoot: root)

        XCTAssertEqual(model.composer.draft, "")
        XCTAssertFalse(model.composer.isSending)
        XCTAssertNil(model.lastError)
        XCTAssertEqual(model.root.topBar.agentStatus, "Idle")
        XCTAssertEqual(model.selectedThread?.messages.last?.role, .assistant)
        XCTAssertTrue(model.selectedThread?.messages.last?.content.hasPrefix("You are `") == true)

        let cards = model.currentToolCards
        XCTAssertEqual(cards.count, 1)
        XCTAssertEqual(cards[0].title, "host.shell.run")
        XCTAssertEqual(cards[0].status, .done)
        XCTAssertTrue(cards[0].inputJSON?.contains("whoami") == true)
        XCTAssertTrue(cards[0].outputJSON?.contains("\"ok\" : true") == true)

        let thread = try XCTUnwrap(model.selectedThread)
        XCTAssertEqual(thread.messages.map(\.role), [.user, .tool, .assistant])
        XCTAssertEqual(QuillCodeWorkspaceModel.messageSurfaces(for: thread).map(\.role), [.user, .assistant])
        let timeline = QuillCodeWorkspaceModel.transcriptTimelineItems(for: thread)
        XCTAssertEqual(timeline.map(\.kind), [.message, .toolCard, .message])
        XCTAssertEqual(timeline[0].message?.role, .user)
        XCTAssertEqual(timeline[1].toolCard?.title, "host.shell.run")
        XCTAssertEqual(timeline[2].message?.role, .assistant)
    }

    func testMessageFeedbackIsStoredAndSurfaced() async throws {
        let root = try makeTempDirectory()
        let model = QuillCodeWorkspaceModel()

        model.setDraft("run whoami")
        await model.submitComposer(workspaceRoot: root)

        let assistantMessage = try XCTUnwrap(model.selectedThread?.messages.last)
        XCTAssertEqual(assistantMessage.role, .assistant)
        XCTAssertTrue(model.setMessageFeedback(messageID: assistantMessage.id, value: .helpful))

        let thread = try XCTUnwrap(model.selectedThread)
        XCTAssertEqual(thread.events.last?.kind, .messageFeedback)
        XCTAssertEqual(QuillCodeWorkspaceModel.messageSurfaces(for: thread).last?.feedback, .helpful)
        XCTAssertEqual(QuillCodeWorkspaceModel.transcriptTimelineItems(for: thread).last?.message?.feedback, .helpful)
        XCTAssertFalse(model.setMessageFeedback(messageID: thread.messages[0].id, value: .notHelpful))
    }

    func testSubmitComposerSurfacesToolArtifacts() async throws {
        let root = try makeTempDirectory()
        let model = QuillCodeWorkspaceModel()

        model.setDraft("Can you write a file that says hello world")
        await model.submitComposer(workspaceRoot: root)

        let card = try XCTUnwrap(model.currentToolCards.last)
        XCTAssertEqual(card.title, "host.file.write")
        XCTAssertEqual(card.status, .done)
        XCTAssertEqual(card.artifacts.map(\.label), ["hello.txt"])
        XCTAssertEqual(card.artifacts.map(\.kind), [.file])
        XCTAssertEqual(card.artifacts.map(\.detail), [root.path])
        XCTAssertEqual(card.artifacts.first?.value, root.appendingPathComponent("hello.txt").path)
    }

    func testArtifactStateDerivesLinksAndImagePreviews() {
        let imageFile = ToolArtifactState(value: "/tmp/quillcode/screenshot.png")
        XCTAssertEqual(imageFile.kind, .file)
        XCTAssertEqual(imageFile.href, "file:///tmp/quillcode/screenshot.png")
        XCTAssertTrue(imageFile.isImagePreview)
        XCTAssertEqual(imageFile.previewURL, imageFile.href)

        let imageURL = ToolArtifactState(value: "https://example.com/assets/mock.webp?size=large")
        XCTAssertEqual(imageURL.kind, .url)
        XCTAssertEqual(imageURL.href, "https://example.com/assets/mock.webp?size=large")
        XCTAssertEqual(imageURL.label, "example.com/assets/mock.webp")
        XCTAssertTrue(imageURL.isImagePreview)
        XCTAssertEqual(imageURL.previewURL, imageURL.href)

        let inlineImage = ToolArtifactState(value: "data:image/png;base64,AAAA")
        XCTAssertEqual(inlineImage.kind, .url)
        XCTAssertEqual(inlineImage.label, "Inline image")
        XCTAssertEqual(inlineImage.detail, "Image artifact")
        XCTAssertTrue(inlineImage.isImagePreview)
        XCTAssertEqual(inlineImage.previewURL, "data:image/png;base64,AAAA")

        let nonImageData = ToolArtifactState(value: "data:text/plain;base64,SGVsbG8=")
        XCTAssertEqual(nonImageData.kind, .path)
        XCTAssertEqual(nonImageData.label, "data:text/plain;base64,SGVsbG8=")
        XCTAssertFalse(nonImageData.isImagePreview)
        XCTAssertNil(nonImageData.previewURL)
        XCTAssertNil(nonImageData.href)
    }

    func testSubmitComposerDispatchesComputerUseToolThroughBackend() async throws {
        let root = try makeTempDirectory()
        let backend = StubComputerUseBackend()
        let call = ToolCall(
            name: ToolDefinition.computerClick.name,
            argumentsJSON: #"{"x":42,"y":84}"#
        )
        let model = QuillCodeWorkspaceModel(
            runner: AgentRunner(llm: FixedToolLLMClient(call: call)),
            computerUseBackend: backend
        )

        model.setDraft("click 42 84")
        await model.submitComposer(workspaceRoot: root)

        let actions = await backend.recordedActions()
        XCTAssertEqual(actions, ["leftClick:42,84"])
        let card = try XCTUnwrap(model.currentToolCards.last)
        XCTAssertEqual(card.title, "host.computer.click")
        XCTAssertEqual(card.status, .done)
        XCTAssertEqual(
            model.selectedThread?.messages.last?.content,
            "Computer Use completed: Clicked 42 84."
        )
    }

    func testSubmitComposerCapturesComputerUseScreenshotThroughBackend() async throws {
        let root = try makeTempDirectory()
        let backend = StubComputerUseBackend()
        let call = ToolCall(name: ToolDefinition.computerScreenshot.name, argumentsJSON: "{}")
        let model = QuillCodeWorkspaceModel(
            runner: AgentRunner(llm: FixedToolLLMClient(call: call)),
            computerUseBackend: backend
        )

        model.setDraft("take a screenshot")
        await model.submitComposer(workspaceRoot: root)

        let actions = await backend.recordedActions()
        XCTAssertEqual(actions, ["screenshot"])
        let card = try XCTUnwrap(model.currentToolCards.last)
        XCTAssertEqual(card.title, "host.computer.screenshot")
        XCTAssertEqual(card.status, .done)
        let outputJSON = try XCTUnwrap(card.outputJSON)
        let result = try JSONHelpers.decode(ToolResult.self, from: outputJSON)
        XCTAssertTrue(result.stdout.contains(#""width" : 1"#))
        XCTAssertFalse(result.stdout.contains("pngBase64"))
        let screenshotArtifact = try XCTUnwrap(result.artifacts.first)
        defer {
            try? FileManager.default.removeItem(atPath: screenshotArtifact)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: screenshotArtifact))
        let artifact = try XCTUnwrap(card.artifacts.first)
        XCTAssertEqual(artifact.kind, .file)
        XCTAssertTrue(artifact.isImagePreview)
        XCTAssertEqual(artifact.previewURL, URL(fileURLWithPath: screenshotArtifact).absoluteString)
        XCTAssertEqual(
            model.selectedThread?.messages.last?.content,
            "Captured a screenshot (1 x 1)."
        )
    }

    func testSubmitComposerStreamsQueuedToolBeforeCompletion() async throws {
        let root = try makeTempDirectory()
        let model = QuillCodeWorkspaceModel(runner: AgentRunner(
            llm: ImmediateToolLLMClient(),
            safety: SlowApprovingSafetyReviewer()
        ))

        model.setDraft("run pwd")
        let task = Task {
            await model.submitComposer(workspaceRoot: root)
        }

        try await waitUntil(timeoutSeconds: 1) {
            model.currentToolCards.first?.status == .queued
        }
        XCTAssertTrue(model.composer.isSending)
        XCTAssertEqual(model.root.topBar.agentStatus, "Queued")

        await task.value

        XCTAssertFalse(model.composer.isSending)
        XCTAssertEqual(model.currentToolCards.first?.status, .done)
        XCTAssertEqual(model.root.topBar.agentStatus, "Idle")
    }

    func testComposerShowsStreamingStatusForStreamingLLM() async throws {
        let root = try makeTempDirectory()
        let model = QuillCodeWorkspaceModel(runner: AgentRunner(
            llm: DelayedStreamingSayLLMClient(chunks: [
                #"{"type":"say","text":"stream"#,
                #"ed response"}"#
            ])
        ))

        model.setDraft("say hello")
        let task = Task {
            await model.submitComposer(workspaceRoot: root)
        }

        try await waitUntil(timeoutSeconds: 1) {
            model.root.topBar.agentStatus == "Streaming"
        }
        XCTAssertTrue(model.composer.isSending)
        try await waitUntil(timeoutSeconds: 1) {
            model.selectedThread?.messages.last?.content == "stream"
        }
        XCTAssertEqual(model.surface().transcript.timelineItems.last?.message?.text, "stream")

        await task.value

        XCTAssertFalse(model.composer.isSending)
        XCTAssertEqual(model.root.topBar.agentStatus, "Idle")
        XCTAssertEqual(model.selectedThread?.messages.last?.content, "streamed response")
        XCTAssertEqual(model.selectedThread?.events.map(\.kind), [.message, .notice, .message])
        XCTAssertEqual(model.selectedThread?.events[1].summary, AgentRunner.streamingNotice)
    }

    func testCancellingComposerRunStopsStateAndRecordsNotice() async throws {
        let root = try makeTempDirectory()
        let model = QuillCodeWorkspaceModel(runner: AgentRunner(llm: SlowLLMClient()))

        model.setDraft("run a long task")
        let task = Task {
            await model.submitComposer(workspaceRoot: root)
        }
        try await waitUntil(timeoutSeconds: 1) {
            model.composer.isSending
        }

        task.cancel()
        await task.value

        XCTAssertFalse(model.composer.isSending)
        XCTAssertNil(model.lastError)
        XCTAssertEqual(model.root.topBar.agentStatus, "Stopped")
        let thread = try XCTUnwrap(model.selectedThread)
        XCTAssertEqual(thread.messages.map(\.role), [.user])
        XCTAssertEqual(thread.messages.first?.content, "run a long task")
        XCTAssertTrue(thread.events.contains { $0.kind == .notice && $0.summary == "Stopped by user" })
    }

    func testCancelledComposerRunRecordsNoticeOnOriginalThread() async throws {
        let root = try makeTempDirectory()
        let model = QuillCodeWorkspaceModel(runner: AgentRunner(llm: SlowLLMClient()))
        let firstThreadID = model.newChat()

        model.setDraft("run a long task")
        let task = Task {
            await model.submitComposer(workspaceRoot: root)
        }
        try await waitUntil(timeoutSeconds: 1) {
            model.composer.isSending
        }
        let secondThreadID = model.newChat()

        task.cancel()
        await task.value

        XCTAssertEqual(model.root.selectedThreadID, secondThreadID)
        let firstThread = try XCTUnwrap(model.root.threads.first { $0.id == firstThreadID })
        let secondThread = try XCTUnwrap(model.root.threads.first { $0.id == secondThreadID })
        XCTAssertTrue(firstThread.events.contains { $0.kind == .notice && $0.summary == "Stopped by user" })
        XCTAssertFalse(secondThread.events.contains { $0.kind == .notice && $0.summary == "Stopped by user" })
    }

    func testTerminalCommandRunsInWorkspaceRootAndRecordsOutput() async throws {
        let root = try makeTempDirectory()
        let model = QuillCodeWorkspaceModel()
        let projectID = model.addProject(path: root, name: "Terminal Project")
        model.selectProject(projectID)

        model.toggleTerminal()
        await model.runTerminalCommand("printf terminal-ok", workspaceRoot: root)

        XCTAssertTrue(model.terminal.isVisible)
        XCTAssertFalse(model.terminal.isRunning)
        XCTAssertEqual(model.terminal.entries.count, 1)
        XCTAssertEqual(model.terminal.entries[0].command, "printf terminal-ok")
        XCTAssertEqual(model.terminal.entries[0].stdout, "terminal-ok")
        XCTAssertEqual(model.terminal.entries[0].exitCode, 0)
        XCTAssertTrue(model.terminal.entries[0].ok)

        let surface = model.surface().terminal
        XCTAssertTrue(surface.isVisible)
        XCTAssertEqual(surface.cwdLabel, root.path)
        XCTAssertEqual(surface.entries.first?.statusLabel, "Done")
        XCTAssertEqual(surface.entries.first?.exitCodeLabel, "exit 0")
    }

    func testTerminalCommandAppearsAsRunningBeforeCompletion() async throws {
        let root = try makeTempDirectory()
        let model = QuillCodeWorkspaceModel()

        let task = Task {
            await model.runTerminalCommand("sleep 0.2 && printf terminal-done", workspaceRoot: root)
        }
        try await waitUntil(timeoutSeconds: 1) {
            model.terminal.isRunning && model.terminal.entries.first?.status == .running
        }

        XCTAssertEqual(model.terminal.entries.count, 1)
        XCTAssertEqual(model.terminal.entries[0].command, "sleep 0.2 && printf terminal-done")
        XCTAssertEqual(model.surface().terminal.entries.first?.statusLabel, "Running")
        XCTAssertEqual(model.surface().terminal.entries.first?.exitCodeLabel, "running")

        await task.value

        XCTAssertFalse(model.terminal.isRunning)
        XCTAssertEqual(model.terminal.entries.count, 1)
        XCTAssertEqual(model.terminal.entries[0].status, .done)
        XCTAssertEqual(model.terminal.entries[0].stdout, "terminal-done")
    }

    func testTerminalCancellationMarksRunningEntryStopped() async throws {
        let root = try makeTempDirectory()
        let model = QuillCodeWorkspaceModel()

        let task = Task {
            await model.runTerminalCommand("sleep 5", workspaceRoot: root)
        }
        try await waitUntil(timeoutSeconds: 1) {
            model.terminal.entries.first?.status == .running
        }

        task.cancel()
        model.cancelActiveWork()
        await task.value

        XCTAssertFalse(model.terminal.isRunning)
        XCTAssertEqual(model.terminal.entries.count, 1)
        XCTAssertEqual(model.terminal.entries[0].status, .stopped)
        XCTAssertEqual(model.surface().terminal.entries.first?.statusLabel, "Stopped")
        XCTAssertEqual(model.surface().terminal.entries.first?.exitCodeLabel, "stopped")
        XCTAssertTrue(model.terminal.entries[0].stderr.contains("Command stopped."))
    }

    func testTerminalStopAllKeepsEntryStoppedAfterProcessExits() async throws {
        let root = try makeTempDirectory()
        let model = QuillCodeWorkspaceModel()

        let task = Task {
            await model.runTerminalCommand("sleep 0.2 && printf late-result", workspaceRoot: root)
        }
        try await waitUntil(timeoutSeconds: 1) {
            model.terminal.entries.first?.status == .running
        }

        model.cancelActiveWork()
        await task.value

        XCTAssertFalse(model.terminal.isRunning)
        XCTAssertEqual(model.terminal.entries.count, 1)
        XCTAssertEqual(model.terminal.entries[0].status, .stopped)
        XCTAssertEqual(model.terminal.entries[0].stdout, "")
        XCTAssertEqual(model.terminal.entries[0].stderr, "Command stopped.")
        XCTAssertNil(model.terminal.entries[0].exitCode)
    }

    func testBrowserPreviewNormalizesURLsAndStoresComments() throws {
        let root = try makeTempDirectory()
        let previewFile = root.appendingPathComponent("preview.html")
        try """
        <!doctype html>
        <html>
          <head><title>Preview Page</title><script src="/app.js"></script></head>
          <body>
            <h1>Hero Preview</h1>
            <a href="/next">Next</a>
            <img src="/hero.png" alt="">
            <form><input name="email"></form>
          </body>
        </html>
        """.write(to: previewFile, atomically: true, encoding: .utf8)
        let model = QuillCodeWorkspaceModel()

        XCTAssertTrue(model.runWorkspaceCommand("toggle-browser", workspaceRoot: root))
        XCTAssertTrue(model.browser.isVisible)

        XCTAssertTrue(model.openBrowserPreview("localhost:3000", workspaceRoot: root))
        XCTAssertEqual(model.browser.currentURL, "http://localhost:3000")
        XCTAssertEqual(model.browser.title, "localhost")
        XCTAssertEqual(model.browser.status, "Preview ready")
        XCTAssertEqual(model.browser.snapshot?.sourceLabel, "Local web app")
        XCTAssertEqual(model.browser.snapshot?.details, [
            "Host: localhost",
            "Scheme: HTTP",
            "Path: /"
        ])

        XCTAssertTrue(model.openBrowserPreview("preview.html", workspaceRoot: root))
        XCTAssertEqual(model.browser.currentURL, previewFile.standardizedFileURL.resolvingSymlinksInPath().absoluteString)
        XCTAssertEqual(model.browser.title, "Preview Page")
        XCTAssertEqual(model.browser.snapshot?.sourceLabel, "Local HTML")
        XCTAssertEqual(model.browser.snapshot?.summary, "HTML snapshot captured for browser review.")
        XCTAssertEqual(model.browser.snapshot?.details.filter { $0 == "Title: Preview Page" }.count, 1)
        XCTAssertEqual(model.browser.snapshot?.details.filter { $0 == "Heading: Hero Preview" }.count, 1)
        XCTAssertEqual(model.browser.snapshot.map { Array($0.details.suffix(4)) }, [
            "Links: 1",
            "Scripts: 1",
            "Images: 1",
            "Forms: 1"
        ])

        XCTAssertTrue(model.addBrowserComment("Check the hero spacing"))
        XCTAssertEqual(model.browser.comments.count, 1)
        XCTAssertEqual(model.browser.comments[0].text, "Check the hero spacing")
        XCTAssertEqual(model.browser.comments[0].url, model.browser.currentURL)

        XCTAssertFalse(model.openBrowserPreview("not-a-valid-target", workspaceRoot: root))
        XCTAssertEqual(model.browser.status, "Invalid address")
        XCTAssertEqual(model.lastError, "Enter an http, https, file, localhost, or project file URL.")
    }

    func testWorkspaceCommandListsGitWorktrees() throws {
        let root = try makeTempDirectory()
        try initializeGitRepository(at: root)
        let model = QuillCodeWorkspaceModel()
        let projectID = model.addProject(path: root, name: "Worktree Project")
        model.selectProject(projectID)

        XCTAssertTrue(model.runWorkspaceCommand("git-worktree-list", workspaceRoot: root))

        let cards = model.currentToolCards
        XCTAssertEqual(cards.count, 1)
        XCTAssertEqual(cards[0].title, "host.git.worktree.list")
        XCTAssertEqual(cards[0].status, .done)
        let outputJSON = try XCTUnwrap(cards[0].outputJSON)
        let result = try JSONHelpers.decode(ToolResult.self, from: outputJSON)
        XCTAssertTrue(result.stdout.contains(root.standardizedFileURL.path), result.stdout)
        XCTAssertEqual(model.root.topBar.agentStatus, "Idle")
    }

    func testWorkspaceWorktreeCommandsPrefillComposer() throws {
        let root = try makeTempDirectory()
        let model = QuillCodeWorkspaceModel()

        XCTAssertTrue(model.runWorkspaceCommand("git-pr-create", workspaceRoot: root))
        XCTAssertEqual(model.composer.draft, "Create a pull request titled ")

        XCTAssertTrue(model.runWorkspaceCommand("git-worktree-create", workspaceRoot: root))
        XCTAssertEqual(model.composer.draft, "Create a git worktree named ")

        XCTAssertTrue(model.runWorkspaceCommand("git-worktree-remove", workspaceRoot: root))
        XCTAssertEqual(model.composer.draft, "Remove git worktree at ")
    }

    func testWorkspaceCreateWorktreeOpensFocusedThreadAndKeepsToolAudit() throws {
        let root = try makeTempGitRepoWithInitialCommit()
        let parent = root.deletingLastPathComponent()
        let worktreeName = "quillcode-ui-\(UUID().uuidString)"
        let branch = "quillcode-ui-\(UUID().uuidString.prefix(8))"
        let worktree = parent.appendingPathComponent(worktreeName).standardizedFileURL
        let model = QuillCodeWorkspaceModel()
        let projectID = model.addProject(path: root, name: "Worktree Project")
        model.selectProject(projectID)

        model.createWorktree(.init(path: worktreeName, branch: String(branch)), workspaceRoot: root)

        XCTAssertTrue(FileManager.default.fileExists(atPath: worktree.path))
        XCTAssertEqual(model.selectedProject?.path, worktree.path)
        XCTAssertEqual(model.selectedProject?.name, worktreeName)
        XCTAssertEqual(model.selectedThread?.projectID, model.selectedProject?.id)
        XCTAssertEqual(model.selectedThread?.title, "Worktree: \(branch)")
        XCTAssertTrue(model.selectedThread?.messages.last?.content.contains("Opened worktree `\(worktreeName)`") == true)
        XCTAssertEqual(model.root.topBar.projectName, worktreeName)
        XCTAssertEqual(model.root.topBar.threadTitle, "Worktree: \(branch)")

        let createThread = try XCTUnwrap(model.root.threads.first { thread in
            QuillCodeWorkspaceModel.toolCards(for: thread).contains { card in
                card.title == "host.git.worktree.create"
            }
        })
        XCTAssertNotEqual(createThread.id, model.selectedThread?.id)
        let createCard = try XCTUnwrap(QuillCodeWorkspaceModel.toolCards(for: createThread).last)
        XCTAssertEqual(createCard.status, .done)
        XCTAssertTrue(createCard.inputJSON?.contains(worktreeName) == true)

        model.removeWorktree(.init(path: worktreeName), workspaceRoot: root)

        XCTAssertFalse(FileManager.default.fileExists(atPath: worktree.path))
        XCTAssertEqual(model.currentToolCards.last?.title, "host.git.worktree.remove")
        XCTAssertEqual(model.currentToolCards.last?.status, .done)
    }

    func testApplyPatchToolRunRefreshesReviewDiff() throws {
        let root = try makeTempDirectory()
        try initializeGitRepository(at: root)
        let fileURL = root.appendingPathComponent("hello.txt")
        try "old\n".write(to: fileURL, atomically: true, encoding: .utf8)
        _ = try runGit(["add", "hello.txt"], cwd: root)
        _ = try runGit(["commit", "-m", "Initial"], cwd: root)
        let patch = """
        diff --git a/hello.txt b/hello.txt
        --- a/hello.txt
        +++ b/hello.txt
        @@ -1 +1 @@
        -old
        +new
        """
        let model = QuillCodeWorkspaceModel()

        model.runToolCall(
            ToolCall(
                name: ToolDefinition.applyPatch.name,
                argumentsJSON: ToolArguments.json(["patch": patch])
            ),
            workspaceRoot: root
        )

        XCTAssertEqual(try String(contentsOf: fileURL, encoding: .utf8), "new\n")
        XCTAssertEqual(model.root.topBar.agentStatus, "Idle")
        XCTAssertEqual(model.currentToolCards.map(\.title), [
            "host.apply_patch",
            "host.git.diff"
        ])
        XCTAssertTrue(model.currentToolCards.allSatisfy { $0.status == .done })
        XCTAssertTrue(model.surface().review.isVisible)
        XCTAssertEqual(model.surface().review.files.map(\.path), ["hello.txt"])
        let lines = try XCTUnwrap(model.surface().review.files.first?.hunkItems.first?.lines)
        XCTAssertTrue(lines.contains(where: {
            $0.content == "new" && $0.kind == .insertion
        }))
    }

    func testProjectInstructionsLoadIntoNewThreadsAndRefreshBeforeRun() async throws {
        let root = try makeTempDirectory()
        try "Prefer Swift tests before final answers.\n".write(
            to: root.appendingPathComponent("AGENTS.md"),
            atomically: true,
            encoding: .utf8
        )
        let quillcodeDirectory = root.appendingPathComponent(".quillcode")
        try FileManager.default.createDirectory(at: quillcodeDirectory, withIntermediateDirectories: true)
        try "Use small focused commits.\n".write(
            to: quillcodeDirectory.appendingPathComponent("rules.md"),
            atomically: true,
            encoding: .utf8
        )

        let model = QuillCodeWorkspaceModel()
        let projectID = model.addProject(path: root, name: "Rules Project")
        let threadID = model.newChat(projectID: projectID)

        XCTAssertEqual(model.root.projects.first?.instructions.map(\.path), [
            "AGENTS.md",
            ".quillcode/rules.md"
        ])
        XCTAssertEqual(model.root.threads.first { $0.id == threadID }?.instructions.count, 2)
        XCTAssertEqual(model.surface().topBar.instructionLabel, "2 instruction files loaded")

        try "Prefer targeted unit tests.\n".write(
            to: root.appendingPathComponent("AGENTS.md"),
            atomically: true,
            encoding: .utf8
        )
        model.setDraft("run whoami")
        await model.submitComposer(workspaceRoot: root)

        XCTAssertTrue(model.selectedThread?.instructions.first?.content.contains("targeted unit tests") == true)
    }

    func testProjectInstructionLoaderBoundsFilesAndRejectsSymlinkEscape() throws {
        let root = try makeTempDirectory()
        let outside = try makeTempDirectory().appendingPathComponent("outside.md")
        try "outside rules\n".write(to: outside, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("AGENTS.md"),
            withDestinationURL: outside
        )
        let quillcodeDirectory = root.appendingPathComponent(".quillcode")
        try FileManager.default.createDirectory(at: quillcodeDirectory, withIntermediateDirectories: true)
        try String(repeating: "x", count: 64).write(
            to: quillcodeDirectory.appendingPathComponent("rules.md"),
            atomically: true,
            encoding: .utf8
        )

        let instructions = ProjectInstructionLoader.load(
            from: root,
            maxFileBytes: 12,
            maxTotalBytes: 20
        )

        XCTAssertEqual(instructions.map(\.path), [".quillcode/rules.md"])
        XCTAssertTrue(instructions[0].wasTruncated)
        XCTAssertTrue(instructions[0].content.contains("truncated"))
        XCTAssertFalse(instructions[0].content.contains("outside rules"))
    }

    func testProjectInstructionLoaderLoadsNestedInstructionsInPrecedenceOrder() throws {
        let root = try makeTempDirectory()
        try "Root rules\n".write(
            to: root.appendingPathComponent("AGENTS.md"),
            atomically: true,
            encoding: .utf8
        )

        let feature = root.appendingPathComponent("Sources/Feature")
        try FileManager.default.createDirectory(at: feature, withIntermediateDirectories: true)
        try "Sources rules\n".write(
            to: root.appendingPathComponent("Sources/AGENTS.md"),
            atomically: true,
            encoding: .utf8
        )
        try "Feature rules\n".write(
            to: feature.appendingPathComponent("AGENTS.md"),
            atomically: true,
            encoding: .utf8
        )

        let featureQuillCode = feature.appendingPathComponent(".quillcode")
        try FileManager.default.createDirectory(at: featureQuillCode, withIntermediateDirectories: true)
        try "Feature QuillCode rules\n".write(
            to: featureQuillCode.appendingPathComponent("rules.md"),
            atomically: true,
            encoding: .utf8
        )

        let generated = root.appendingPathComponent(".build/generated")
        try FileManager.default.createDirectory(at: generated, withIntermediateDirectories: true)
        try "Generated rules should not load\n".write(
            to: generated.appendingPathComponent("AGENTS.md"),
            atomically: true,
            encoding: .utf8
        )

        let instructions = ProjectInstructionLoader.load(from: root)

        XCTAssertEqual(instructions.map(\.path), [
            "AGENTS.md",
            "Sources/AGENTS.md",
            "Sources/Feature/AGENTS.md",
            "Sources/Feature/.quillcode/rules.md"
        ])
        XCTAssertTrue(instructions.last?.content.contains("Feature QuillCode rules") == true)
        XCTAssertFalse(instructions.contains { $0.content.contains("Generated rules") })
    }

    func testProjectInstructionLoaderCapsNestedInstructionCount() throws {
        let root = try makeTempDirectory()
        for index in 0..<5 {
            let directory = root.appendingPathComponent("Area\(index)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try "Rules \(index)\n".write(
                to: directory.appendingPathComponent("AGENTS.md"),
                atomically: true,
                encoding: .utf8
            )
        }

        let instructions = ProjectInstructionLoader.load(
            from: root,
            maxInstructionFiles: 2
        )

        XCTAssertEqual(instructions.map(\.path), [
            "Area0/AGENTS.md",
            "Area1/AGENTS.md"
        ])
    }

    func testLocalEnvironmentActionsLoadAndRunFromCommandPaletteIDs() throws {
        let root = try makeTempDirectory()
        let actionsDirectory = root.appendingPathComponent(".quillcode/actions")
        try FileManager.default.createDirectory(at: actionsDirectory, withIntermediateDirectories: true)
        try "printf local-env-ok".write(
            to: actionsDirectory.appendingPathComponent("bootstrap-env.sh"),
            atomically: true,
            encoding: .utf8
        )

        let model = QuillCodeWorkspaceModel()
        let projectID = model.addProject(path: root, name: "Local Env Project")
        model.selectProject(projectID)

        let action = try XCTUnwrap(model.selectedProject?.localActions.first)
        XCTAssertEqual(action.title, "Bootstrap Env")
        XCTAssertEqual(action.relativePath, ".quillcode/actions/bootstrap-env.sh")
        XCTAssertTrue(model.runWorkspaceCommand(action.id, workspaceRoot: root))

        let card = try XCTUnwrap(model.currentToolCards.last)
        XCTAssertEqual(card.title, "host.shell.run")
        XCTAssertEqual(card.status, .done)
        let outputJSON = try XCTUnwrap(card.outputJSON)
        let result = try JSONHelpers.decode(ToolResult.self, from: outputJSON)
        XCTAssertEqual(result.stdout, "local-env-ok")
    }

    func testLocalEnvironmentActionLoaderBoundsScriptsAndRejectsSymlinkEscape() throws {
        let root = try makeTempDirectory()
        let outside = try makeTempDirectory().appendingPathComponent("outside.sh")
        try "printf bad".write(to: outside, atomically: true, encoding: .utf8)
        let actionsDirectory = root.appendingPathComponent(".quillcode/actions")
        try FileManager.default.createDirectory(at: actionsDirectory, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: actionsDirectory.appendingPathComponent("outside.sh"),
            withDestinationURL: outside
        )
        try "printf one".write(
            to: actionsDirectory.appendingPathComponent("one.sh"),
            atomically: true,
            encoding: .utf8
        )
        try "printf two".write(
            to: actionsDirectory.appendingPathComponent("two.sh"),
            atomically: true,
            encoding: .utf8
        )

        let actions = LocalEnvironmentActionLoader.load(from: root, maxActions: 1)

        XCTAssertEqual(actions.map(\.relativePath), [".quillcode/actions/one.sh"])
        XCTAssertEqual(actions[0].command, #"sh '.quillcode/actions/one.sh'"#)
    }

    func testProjectExtensionManifestLoaderLoadsKindsAndRejectsUnsafeFiles() throws {
        let root = try makeTempDirectory()
        let pluginDirectory = root.appendingPathComponent(".quillcode/plugins")
        let skillDirectory = root.appendingPathComponent(".quillcode/skills")
        let mcpDirectory = root.appendingPathComponent(".quillcode/mcp")
        try FileManager.default.createDirectory(at: pluginDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: skillDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: mcpDirectory, withIntermediateDirectories: true)

        try #"{"id":"github","name":"GitHub","description":"PR and issue helpers."}"#.write(
            to: pluginDirectory.appendingPathComponent("github.json"),
            atomically: true,
            encoding: .utf8
        )
        try #"{"id":"review","name":"Code Review","summary":"Review defects first.","enabled":false}"#.write(
            to: skillDirectory.appendingPathComponent("review.json"),
            atomically: true,
            encoding: .utf8
        )
        try #"{"id":"filesystem","name":"Filesystem MCP","command":"quill-mcp","args":["--root","."]}"#.write(
            to: mcpDirectory.appendingPathComponent("filesystem.json"),
            atomically: true,
            encoding: .utf8
        )
        try #"{"id":"broken""#.write(
            to: pluginDirectory.appendingPathComponent("broken.json"),
            atomically: true,
            encoding: .utf8
        )
        let outside = try makeTempDirectory().appendingPathComponent("outside.json")
        try #"{"id":"outside","name":"Outside"}"#.write(to: outside, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(
            at: pluginDirectory.appendingPathComponent("outside.json"),
            withDestinationURL: outside
        )

        let manifests = ProjectExtensionManifestLoader.load(from: root)

        XCTAssertEqual(manifests.map(\.id), [
            "plugin:github",
            "skill:review",
            "mcp_server:filesystem"
        ])
        XCTAssertEqual(manifests.map(\.kind), [.plugin, .skill, .mcpServer])
        XCTAssertEqual(manifests[0].summary, "PR and issue helpers.")
        XCTAssertEqual(manifests[1].isEnabled, false)
        XCTAssertEqual(manifests[2].transport, .stdio)
        XCTAssertEqual(manifests[2].launchExecutable, "quill-mcp")
        XCTAssertEqual(manifests[2].launchCommand, "quill-mcp --root .")
        XCTAssertEqual(manifests[2].launchArguments, ["--root", "."])
    }

    func testProjectExtensionManifestsLoadIntoProjectSurface() throws {
        let root = try makeTempDirectory()
        let pluginDirectory = root.appendingPathComponent(".quillcode/plugins")
        try FileManager.default.createDirectory(at: pluginDirectory, withIntermediateDirectories: true)
        try #"{"id":"github","name":"GitHub","description":"PR workflow helpers."}"#.write(
            to: pluginDirectory.appendingPathComponent("github.json"),
            atomically: true,
            encoding: .utf8
        )

        let model = QuillCodeWorkspaceModel()
        let projectID = model.addProject(path: root, name: "Extension Project")
        model.selectProject(projectID)
        XCTAssertTrue(model.runWorkspaceCommand("toggle-extensions", workspaceRoot: root))

        let extensions = model.surface().extensions

        XCTAssertTrue(extensions.isVisible)
        XCTAssertEqual(extensions.pluginCount, 1)
        XCTAssertEqual(extensions.skillCount, 0)
        XCTAssertEqual(extensions.mcpServerCount, 0)
        XCTAssertEqual(extensions.items.first?.name, "GitHub")
        XCTAssertEqual(extensions.items.first?.relativePath, ".quillcode/plugins/github.json")
    }

    func testMCPServerLifecycleStartsStopsAndStopAllTerminatesProcesses() throws {
        let root = try makeTempDirectory()
        let mcpDirectory = root.appendingPathComponent(".quillcode/mcp")
        try FileManager.default.createDirectory(at: mcpDirectory, withIntermediateDirectories: true)
        let server = try writeFixtureMCPServer(in: root)
        try #"{"id":"filesystem","name":"Filesystem MCP","command":""#
            .appending(server.path)
            .appending(#""}"#)
            .write(
            to: mcpDirectory.appendingPathComponent("filesystem.json"),
            atomically: true,
            encoding: .utf8
        )

        let model = QuillCodeWorkspaceModel()
        let projectID = model.addProject(path: root, name: "MCP Project")
        model.selectProject(projectID)
        _ = model.newChat(projectID: projectID)
        model.toggleExtensions()

        XCTAssertEqual(model.surface().extensions.items.first?.statusLabel, "Stopped")
        XCTAssertTrue(model.runWorkspaceCommand("mcp-start:mcp_server:filesystem", workspaceRoot: root))

        var surface = model.surface()
        XCTAssertEqual(surface.extensions.items.first?.statusLabel, "Ready")
        XCTAssertEqual(surface.extensions.items.first?.serverLabel, "Fixture MCP 1.0.0")
        XCTAssertEqual(surface.extensions.items.first?.protocolLabel, "MCP 2024-11-05")
        XCTAssertEqual(surface.extensions.items.first?.toolCountLabel, "2 tools")
        XCTAssertEqual(surface.extensions.items.first?.toolNames, ["read_file", "write_file"])
        XCTAssertEqual(surface.extensions.items.first?.stopCommandID, "mcp-stop:mcp_server:filesystem")
        XCTAssertEqual(surface.commands.first { $0.id == "stop-all" }?.isEnabled, true)
        XCTAssertTrue(model.selectedThread?.events.contains {
            $0.summary == "MCP server Filesystem MCP ready (2 tools: read_file, write_file)"
        } == true)

        model.cancelActiveWork()
        surface = model.surface()
        XCTAssertEqual(surface.extensions.items.first?.statusLabel, "Stopped")
        XCTAssertEqual(surface.commands.first { $0.id == "stop-all" }?.isEnabled, false)

        XCTAssertTrue(model.runWorkspaceCommand("mcp-start:mcp_server:filesystem", workspaceRoot: root))
        XCTAssertTrue(model.runWorkspaceCommand("mcp-stop:mcp_server:filesystem", workspaceRoot: root))
        surface = model.surface()
        XCTAssertEqual(surface.extensions.items.first?.statusLabel, "Stopped")
        XCTAssertEqual(surface.extensions.items.first?.startCommandID, "mcp-start:mcp_server:filesystem")
        XCTAssertTrue(model.selectedThread?.events.contains { $0.summary == "MCP server Filesystem MCP stopped" } == true)
    }

    func testReadyMCPServerCanBeCalledFromAgentTurn() async throws {
        let root = try makeTempDirectory()
        let mcpDirectory = root.appendingPathComponent(".quillcode/mcp")
        try FileManager.default.createDirectory(at: mcpDirectory, withIntermediateDirectories: true)
        let server = try writeFixtureMCPServer(in: root, callText: "hello from MCP")
        try #"{"id":"filesystem","name":"Filesystem MCP","command":""#
            .appending(server.path)
            .appending(#""}"#)
            .write(
                to: mcpDirectory.appendingPathComponent("filesystem.json"),
                atomically: true,
                encoding: .utf8
            )

        let call = ToolCall(
            name: ToolDefinition.mcpCall.name,
            argumentsJSON: """
            {"serverID":"mcp_server:filesystem","toolName":"read_file","arguments":{"path":"README.md"}}
            """
        )
        let model = QuillCodeWorkspaceModel(runner: AgentRunner(llm: FixedToolLLMClient(call: call)))
        let projectID = model.addProject(path: root, name: "MCP Project")
        model.selectProject(projectID)
        _ = model.newChat(projectID: projectID)

        XCTAssertTrue(model.runWorkspaceCommand("mcp-start:mcp_server:filesystem", workspaceRoot: root))
        model.setDraft("run MCP read_file on README")
        await model.submitComposer(workspaceRoot: root)

        XCTAssertEqual(Array(model.selectedThread?.events.map(\.kind).suffix(5) ?? []), [
            .message,
            .toolQueued,
            .toolRunning,
            .toolCompleted,
            .message
        ])
        XCTAssertEqual(model.selectedThread?.messages.last?.content, "Output:\nhello from MCP")
    }

    func testMCPToolCallRejectsUnadvertisedTools() async throws {
        let root = try makeTempDirectory()
        let mcpDirectory = root.appendingPathComponent(".quillcode/mcp")
        try FileManager.default.createDirectory(at: mcpDirectory, withIntermediateDirectories: true)
        let server = try writeFixtureMCPServer(in: root, callText: "should not run")
        try #"{"id":"filesystem","name":"Filesystem MCP","command":""#
            .appending(server.path)
            .appending(#""}"#)
            .write(
                to: mcpDirectory.appendingPathComponent("filesystem.json"),
                atomically: true,
                encoding: .utf8
            )

        let call = ToolCall(
            name: ToolDefinition.mcpCall.name,
            argumentsJSON: """
            {"serverID":"mcp_server:filesystem","toolName":"delete_everything","arguments":{}}
            """
        )
        let model = QuillCodeWorkspaceModel(runner: AgentRunner(llm: FixedToolLLMClient(call: call)))
        let projectID = model.addProject(path: root, name: "MCP Project")
        model.selectProject(projectID)
        _ = model.newChat(projectID: projectID)

        XCTAssertTrue(model.runWorkspaceCommand("mcp-start:mcp_server:filesystem", workspaceRoot: root))
        model.setDraft("run MCP delete_everything")
        await model.submitComposer(workspaceRoot: root)

        XCTAssertEqual(model.selectedThread?.events.suffix(2).first?.kind, .toolFailed)
        XCTAssertEqual(
            model.selectedThread?.messages.last?.content,
            "Command failed:\nMCP tool delete_everything was not advertised by mcp_server:filesystem."
        )
    }

    func testMemoryNotesLoadGlobalAndProjectIntoThreadAndSurface() async throws {
        let root = try makeTempDirectory()
        let globalMemories = try makeTempDirectory()
        try "Prefer concise progress updates.\n".write(
            to: globalMemories.appendingPathComponent("preferences.md"),
            atomically: true,
            encoding: .utf8
        )
        let projectMemoryDirectory = root.appendingPathComponent(".quillcode/memories")
        try FileManager.default.createDirectory(at: projectMemoryDirectory, withIntermediateDirectories: true)
        try "This project uses SwiftUI.\n".write(
            to: projectMemoryDirectory.appendingPathComponent("project.md"),
            atomically: true,
            encoding: .utf8
        )

        let model = QuillCodeWorkspaceModel(globalMemoryDirectory: globalMemories)
        let projectID = model.addProject(path: root, name: "Memory Project")
        let threadID = model.newChat(projectID: projectID)

        XCTAssertEqual(model.root.globalMemories.map(\.relativePath), ["memories/preferences.md"])
        XCTAssertEqual(model.root.projects.first?.memories.map(\.relativePath), [".quillcode/memories/project.md"])
        XCTAssertEqual(model.root.threads.first { $0.id == threadID }?.memories.map(\.title), ["Preferences", "Project"])

        XCTAssertTrue(model.runWorkspaceCommand("toggle-memories", workspaceRoot: root))
        let memories = model.surface().memories
        XCTAssertTrue(memories.isVisible)
        XCTAssertEqual(memories.globalCount, 1)
        XCTAssertEqual(memories.projectCount, 1)
        XCTAssertEqual(memories.items.map { $0.scope }, [MemoryScope.global, .project])
        XCTAssertEqual(memories.items.first?.canDelete, true)
        XCTAssertNotNil(memories.items.first?.deleteCommandID)
        XCTAssertEqual(memories.items.last?.canDelete, false)
        XCTAssertNil(memories.items.last?.deleteCommandID)
        XCTAssertEqual(model.surface().topBar.memoryLabel, "2 memories")
    }

    func testSlashRememberWritesGlobalMemoryAndRefreshesThreadSurface() async throws {
        let root = try makeTempDirectory()
        let globalMemories = try makeTempDirectory()
        let model = QuillCodeWorkspaceModel(globalMemoryDirectory: globalMemories)
        let projectID = model.addProject(path: root, name: "Memory Write Project")
        model.selectProject(projectID)

        model.setDraft("/remember Prefer small reviewable commits")
        await model.submitComposer(workspaceRoot: root)

        XCTAssertEqual(model.root.globalMemories.count, 1)
        let memory = try XCTUnwrap(model.root.globalMemories.first)
        XCTAssertEqual(memory.content, "Prefer small reviewable commits")
        XCTAssertTrue(memory.relativePath.hasPrefix("memories/manual-"))
        XCTAssertTrue(memory.relativePath.hasSuffix("-prefer-small-reviewable-commits.md"))
        XCTAssertEqual(model.selectedThread?.title, "Memory: \(memory.title)")
        XCTAssertEqual(model.selectedThread?.memories.map(\.content), ["Prefer small reviewable commits"])
        XCTAssertEqual(model.selectedThread?.events.last?.summary, "Saved memory: \(memory.title)")
        XCTAssertEqual(model.selectedThread?.events.last?.payloadJSON, memory.relativePath)
        XCTAssertEqual(model.selectedThread?.messages.last?.role, .assistant)
        XCTAssertTrue(model.selectedThread?.messages.last?.content.contains("Saved memory: \(memory.title)") == true)
        XCTAssertEqual(model.surface().topBar.memoryLabel, "1 memory")
        XCTAssertEqual(model.surface().memories.items.first?.canDelete, true)
        XCTAssertEqual(model.surface().memories.items.first?.deleteCommandID, "memory-delete:\(memory.id)")

        let filename = memory.relativePath.replacingOccurrences(of: "memories/", with: "")
        let savedURL = globalMemories.appendingPathComponent(filename)
        XCTAssertEqual(try String(contentsOf: savedURL, encoding: .utf8), "Prefer small reviewable commits\n")
    }

    func testMemoryDeleteWorkspaceCommandRemovesGlobalMemoryAndRefreshesThreadSurface() throws {
        let root = try makeTempDirectory()
        let globalMemories = try makeTempDirectory()
        try "Prefer concise progress updates.\n".write(
            to: globalMemories.appendingPathComponent("preferences.md"),
            atomically: true,
            encoding: .utf8
        )
        let projectMemoryDirectory = root.appendingPathComponent(".quillcode/memories")
        try FileManager.default.createDirectory(at: projectMemoryDirectory, withIntermediateDirectories: true)
        try "This project uses SwiftUI.\n".write(
            to: projectMemoryDirectory.appendingPathComponent("project.md"),
            atomically: true,
            encoding: .utf8
        )

        let model = QuillCodeWorkspaceModel(globalMemoryDirectory: globalMemories)
        let projectID = model.addProject(path: root, name: "Memory Delete Project")
        model.selectProject(projectID)
        _ = model.newChat(projectID: projectID)

        let global = try XCTUnwrap(model.root.globalMemories.first)
        XCTAssertTrue(model.runWorkspaceCommand("memory-delete:\(global.id)", workspaceRoot: root))

        XCTAssertFalse(FileManager.default.fileExists(
            atPath: globalMemories.appendingPathComponent("preferences.md").path
        ))
        XCTAssertEqual(model.root.globalMemories, [])
        XCTAssertEqual(model.selectedThread?.memories.map(\.relativePath), [".quillcode/memories/project.md"])
        XCTAssertEqual(model.selectedThread?.events.last?.summary, "Forgot memory: Preferences")
        XCTAssertEqual(model.selectedThread?.events.last?.payloadJSON, "memories/preferences.md")
        XCTAssertEqual(model.selectedThread?.messages.last?.role, .assistant)
        XCTAssertTrue(model.selectedThread?.messages.last?.content.contains("Forgot memory: Preferences") == true)
        XCTAssertEqual(model.surface().topBar.memoryLabel, "1 memory")
        XCTAssertEqual(model.surface().memories.items.map(\.scope), [.project])
    }

    func testMemoryDeleteRejectsUnknownGlobalMemoryIDWithoutRemovingFiles() throws {
        let root = try makeTempDirectory()
        let globalMemories = try makeTempDirectory()
        try "Prefer concise progress updates.\n".write(
            to: globalMemories.appendingPathComponent("preferences.md"),
            atomically: true,
            encoding: .utf8
        )

        let model = QuillCodeWorkspaceModel(globalMemoryDirectory: globalMemories)
        _ = model.newChat()

        XCTAssertTrue(model.runWorkspaceCommand("memory-delete:missing-memory", workspaceRoot: root))

        XCTAssertTrue(FileManager.default.fileExists(
            atPath: globalMemories.appendingPathComponent("preferences.md").path
        ))
        XCTAssertEqual(model.root.globalMemories.map(\.relativePath), ["memories/preferences.md"])
        XCTAssertEqual(model.selectedThread?.title, "Memory not deleted")
        XCTAssertTrue(model.selectedThread?.messages.last?.content.contains("not found") == true)
    }

    func testSlashRememberRejectsCredentialLikeMemory() async throws {
        let root = try makeTempDirectory()
        let globalMemories = try makeTempDirectory()
        let model = QuillCodeWorkspaceModel(globalMemoryDirectory: globalMemories)

        model.setDraft("/remember api_key=sk-qc-v1-ob4rbJAb9WOqdNIhSsT8oumjqaLZUX8p2zLHr1WOGn8")
        await model.submitComposer(workspaceRoot: root)

        XCTAssertEqual(model.root.globalMemories, [])
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: globalMemories.path)
                .filter { $0.hasSuffix(".md") },
            []
        )
        XCTAssertEqual(model.selectedThread?.title, "Memory not saved")
        XCTAssertTrue(model.selectedThread?.messages.last?.content.contains("credential") == true)
        XCTAssertEqual(model.surface().topBar.memoryLabel, "No memories")
    }

    func testMemoryAddWorkspaceCommandPrefillsRememberSlash() throws {
        let model = QuillCodeWorkspaceModel()

        XCTAssertTrue(model.runWorkspaceCommand("memory-add", workspaceRoot: try makeTempDirectory()))

        XCTAssertEqual(model.composer.draft, "/remember ")
    }

    func testMemoryNoteLoaderBoundsFilesAndRejectsSymlinkEscape() throws {
        let root = try makeTempDirectory()
        let outside = try makeTempDirectory().appendingPathComponent("outside.md")
        try "outside memory\n".write(to: outside, atomically: true, encoding: .utf8)
        let memoryDirectory = root.appendingPathComponent(".quillcode/memories")
        try FileManager.default.createDirectory(at: memoryDirectory, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: memoryDirectory.appendingPathComponent("outside.md"),
            withDestinationURL: outside
        )
        try String(repeating: "x", count: 64).write(
            to: memoryDirectory.appendingPathComponent("one.md"),
            atomically: true,
            encoding: .utf8
        )
        try "ignored binary".write(
            to: memoryDirectory.appendingPathComponent("ignored.bin"),
            atomically: true,
            encoding: .utf8
        )

        let notes = MemoryNoteLoader.loadProject(
            from: root,
            maxNotes: 1,
            maxFileBytes: 12,
            maxTotalBytes: 12
        )

        XCTAssertEqual(notes.map(\.relativePath), [".quillcode/memories/one.md"])
        XCTAssertTrue(notes[0].wasTruncated)
        XCTAssertTrue(notes[0].content.contains("truncated"))
        XCTAssertFalse(notes[0].content.contains("outside memory"))
    }

    func testEmptyDraftDoesNotCreateThread() async throws {
        let model = QuillCodeWorkspaceModel()
        model.setDraft("   ")
        await model.submitComposer(workspaceRoot: try makeTempDirectory())
        XCTAssertTrue(model.root.threads.isEmpty)
    }

    func testSlashNewCreatesFreshThreadWithoutAgentRun() async throws {
        let existing = ChatThread(title: "Existing")
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            threads: [existing],
            selectedThreadID: existing.id
        ))

        model.setDraft("/new")
        await model.submitComposer(workspaceRoot: try makeTempDirectory())

        XCTAssertEqual(model.composer.draft, "")
        XCTAssertEqual(model.root.threads.count, 2)
        XCTAssertEqual(model.selectedThread?.title, "New chat")
        XCTAssertTrue(model.selectedThread?.messages.isEmpty == true)
        XCTAssertTrue(model.currentToolCards.isEmpty)
    }

    func testSlashModeChangesModeAndWritesLocalTranscript() async throws {
        let model = QuillCodeWorkspaceModel()

        model.setDraft("/mode review")
        await model.submitComposer(workspaceRoot: try makeTempDirectory())

        XCTAssertEqual(model.root.config.mode, .review)
        XCTAssertEqual(model.selectedThread?.mode, .review)
        XCTAssertEqual(model.selectedThread?.title, "Set mode")
        XCTAssertEqual(model.selectedThread?.messages.map(\.role), [.user, .assistant])
        XCTAssertEqual(model.selectedThread?.messages.last?.content, "Mode set to Review.")
        XCTAssertTrue(model.currentToolCards.isEmpty)
    }

    func testSlashModelChangesModelAndWritesLocalTranscript() async throws {
        let model = QuillCodeWorkspaceModel()

        model.setDraft("/model z-ai/glm-5.2")
        await model.submitComposer(workspaceRoot: try makeTempDirectory())

        XCTAssertEqual(model.root.config.defaultModel, "z-ai/glm-5.2")
        XCTAssertEqual(model.selectedThread?.model, "z-ai/glm-5.2")
        XCTAssertEqual(model.selectedThread?.messages.last?.content, "Model set to z-ai/glm-5.2.")
        XCTAssertTrue(model.currentToolCards.isEmpty)
    }

    func testSlashCompactRoutesToContextCompaction() async throws {
        let source = ChatThread(title: "Long slash thread", messages: [
            .init(role: .user, content: "old question"),
            .init(role: .assistant, content: "old answer"),
            .init(role: .user, content: "latest question"),
            .init(role: .assistant, content: "latest answer")
        ])
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            threads: [source],
            selectedThreadID: source.id
        ))

        model.setDraft("/compact")
        await model.submitComposer(workspaceRoot: try makeTempDirectory())

        XCTAssertEqual(model.selectedThread?.title, "Compact: Long slash thread")
        XCTAssertEqual(Array(model.selectedThread?.messages.map(\.content).suffix(2) ?? []), ["latest question", "latest answer"])
        XCTAssertTrue(model.selectedThread?.messages.first?.content.contains("Context compacted") == true)
    }

    func testSlashThreadLifecycleCommands() async throws {
        let source = ChatThread(title: "Original", messages: [
            .init(role: .user, content: "run whoami")
        ])
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            threads: [source],
            selectedThreadID: source.id
        ))
        let root = try makeTempDirectory()

        model.setDraft("/rename Better name")
        await model.submitComposer(workspaceRoot: root)
        XCTAssertEqual(model.selectedThread?.title, "Better name")
        XCTAssertEqual(model.selectedThread?.messages.last?.content, "Renamed chat to Better name.")

        model.setDraft("/duplicate")
        await model.submitComposer(workspaceRoot: root)
        let duplicateID = try XCTUnwrap(model.root.selectedThreadID)
        XCTAssertEqual(model.selectedThread?.title, "Copy: Better name")

        model.setDraft("/archive")
        await model.submitComposer(workspaceRoot: root)
        XCTAssertEqual(model.root.selectedThreadID, source.id)
        XCTAssertTrue(model.root.threads.first { $0.id == duplicateID }?.isArchived == true)

        model.selectThread(duplicateID)
        model.setDraft("/unarchive")
        await model.submitComposer(workspaceRoot: root)
        XCTAssertEqual(model.root.selectedThreadID, duplicateID)
        XCTAssertFalse(model.selectedThread?.isArchived ?? true)
    }

    func testSlashStatusReportsWorkspaceState() async throws {
        let project = ProjectRef(name: "QuillCode", path: "/tmp/QuillCode")
        let thread = ChatThread(title: "Status thread", projectID: project.id)
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            projects: [project],
            selectedProjectID: project.id,
            threads: [thread],
            selectedThreadID: thread.id
        ))

        model.setDraft("/status")
        await model.submitComposer(workspaceRoot: try makeTempDirectory())

        let message = try XCTUnwrap(model.selectedThread?.messages.last?.content)
        XCTAssertTrue(message.contains("Project: QuillCode"))
        XCTAssertTrue(message.contains("Thread: Status thread"))
        XCTAssertTrue(message.contains("Mode: Auto"))
        XCTAssertTrue(message.contains("Model: trustedrouter/fast"))
    }

    func testPinnedThreadsSortBeforeRecentThreads() {
        let older = ChatThread(
            title: "Older",
            updatedAt: Date(timeIntervalSince1970: 1)
        )
        var newer = ChatThread(
            title: "Newer",
            updatedAt: Date(timeIntervalSince1970: 2)
        )
        newer.isPinned = true
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(threads: [older, newer]))

        XCTAssertEqual(model.root.sidebarItems.map(\.title), ["Newer", "Older"])
    }

    func testArchiveSelectedThreadRemovesItFromSidebar() {
        let first = ChatThread(title: "First")
        let second = ChatThread(title: "Second")
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            threads: [first, second],
            selectedThreadID: first.id
        ))

        model.archiveSelectedThread()

        XCTAssertEqual(model.root.sidebarItems.map(\.title), ["Second"])
        XCTAssertEqual(model.root.selectedThreadID, second.id)
    }

    func testPinAndArchiveThreadByIDPersistChanges() throws {
        let root = try makeTempDirectory()
        let threadStore = JSONThreadStore(directory: root)
        let first = ChatThread(title: "First")
        let second = ChatThread(title: "Second")
        try threadStore.save(first)
        try threadStore.save(second)
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(
                threads: [first, second],
                selectedThreadID: first.id
            ),
            threadStore: threadStore
        )

        model.togglePinThread(second.id)
        model.archiveThread(first.id)

        XCTAssertEqual(model.root.sidebarItems.map(\.title), ["Second"])
        XCTAssertEqual(model.root.selectedThreadID, second.id)
        XCTAssertTrue(try threadStore.load(second.id).isPinned)
        XCTAssertTrue(try threadStore.load(first.id).isArchived)
    }

    func testRenameDuplicateUnarchiveAndDeleteThreadLifecycle() throws {
        let root = try makeTempDirectory()
        let threadStore = JSONThreadStore(directory: root)
        var archived = ChatThread(title: "Archived", messages: [
            .init(role: .user, content: "old task")
        ])
        archived.isArchived = true
        let active = ChatThread(title: "Active", messages: [
            .init(role: .user, content: "run whoami"),
            .init(role: .assistant, content: "quill")
        ])
        try threadStore.save(archived)
        try threadStore.save(active)
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(
                threads: [archived, active],
                selectedThreadID: active.id
            ),
            threadStore: threadStore
        )

        XCTAssertTrue(model.renameThread(active.id, to: "Renamed Active"))
        XCTAssertEqual(model.selectedThread?.title, "Renamed Active")
        XCTAssertEqual(try threadStore.load(active.id).title, "Renamed Active")

        let duplicateID = try XCTUnwrap(model.duplicateThread(active.id))
        let duplicate = try threadStore.load(duplicateID)
        XCTAssertEqual(duplicate.title, "Copy: Renamed Active")
        XCTAssertEqual(duplicate.messages.map(\.content), ["run whoami", "quill"])
        XCTAssertEqual(duplicate.events.last?.summary, "Duplicated from Renamed Active")
        XCTAssertEqual(model.root.selectedThreadID, duplicateID)

        XCTAssertTrue(model.unarchiveThread(archived.id))
        XCTAssertEqual(model.root.selectedThreadID, archived.id)
        XCTAssertFalse(try threadStore.load(archived.id).isArchived)
        XCTAssertEqual(model.root.sidebarItems.map(\.title), ["Archived", "Copy: Renamed Active", "Renamed Active"])

        XCTAssertTrue(model.deleteThread(archived.id))
        XCTAssertThrowsError(try threadStore.load(archived.id))
        XCTAssertFalse(model.root.threads.contains { $0.id == archived.id })
        XCTAssertEqual(model.root.selectedThreadID, duplicateID)
    }

    func testModeAndModelUpdateSelectedThreadAndTopBar() {
        let thread = ChatThread()
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            threads: [thread],
            selectedThreadID: thread.id
        ))

        model.setMode(.review)
        model.setModel("provider/model")

        XCTAssertEqual(model.selectedThread?.mode, .review)
        XCTAssertEqual(model.selectedThread?.model, "provider/model")
        XCTAssertEqual(model.root.topBar.mode, .review)
        XCTAssertEqual(model.root.topBar.model, "provider/model")
    }

    func testToggleModelFavoriteUpdatesConfigAndSurface() {
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            config: AppConfig(favoriteModels: ["provider/old"]),
            topBar: TopBarState(model: "trustedrouter/fusion"),
            modelCatalog: TrustedRouterModelCatalog.defaultModels
        ))

        model.toggleModelFavorite(" z-ai/glm-5.2 ")

        XCTAssertEqual(model.root.config.favoriteModels, ["provider/old", "z-ai/glm-5.2"])
        XCTAssertEqual(model.surface().topBar.modelCategories.first?.category, "Favorites")
        XCTAssertEqual(model.surface().topBar.modelCategories.first?.models.map(\.id), ["provider/old", "z-ai/glm-5.2"])

        model.toggleModelFavorite("provider/old")

        XCTAssertEqual(model.root.config.favoriteModels, ["z-ai/glm-5.2"])
        XCTAssertEqual(model.surface().topBar.modelCategories.first?.models.map(\.id), ["z-ai/glm-5.2"])
    }

    func testApplySettingsUpdatesConfigThreadAndSettingsSurface() {
        let thread = ChatThread()
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            threads: [thread],
            selectedThreadID: thread.id
        ))
        let config = AppConfig(
            defaultModel: "z-ai/glm-5.2",
            mode: .review,
            apiBaseURL: "https://api.trustedrouter.test/v1",
            developerOverrideEnabled: true
        )

        model.applySettings(config: config, trustedRouterAPIKeyConfigured: true)

        XCTAssertEqual(model.root.config, config)
        XCTAssertEqual(model.selectedThread?.mode, .review)
        XCTAssertEqual(model.selectedThread?.model, "z-ai/glm-5.2")
        XCTAssertEqual(model.surface().settings.apiBaseURL, "https://api.trustedrouter.test/v1")
        XCTAssertTrue(model.surface().settings.developerOverrideEnabled)
        XCTAssertTrue(model.surface().settings.hasStoredAPIKey)
        XCTAssertEqual(model.surface().settings.apiKeyStatusLabel, "API key configured")
    }

    func testApplyRuntimeRefreshesAgentStatus() {
        let model = QuillCodeWorkspaceModel()

        model.applyRuntime(QuillCodeRuntime(
            runner: AgentRunner(),
            mode: .trustedRouter,
            statusLabel: "TrustedRouter ready"
        ))

        XCTAssertEqual(model.root.topBar.agentStatus, "TrustedRouter ready")
    }

    func testRuntimeIssueSurfacesMissingTrustedRouterSignIn() {
        let model = QuillCodeWorkspaceModel()

        model.applyRuntime(QuillCodeRuntime(
            runner: AgentRunner(),
            mode: .trustedRouter,
            statusLabel: "Sign in with TrustedRouter"
        ))

        let surface = model.surface()
        XCTAssertEqual(surface.runtimeIssue?.severity, .warning)
        XCTAssertEqual(surface.runtimeIssue?.title, "TrustedRouter sign-in needed")
        XCTAssertEqual(surface.runtimeIssue?.actionLabel, "Open Settings")
        XCTAssertEqual(surface.topBar.runtimeIssueLabel, "TrustedRouter sign-in needed")
        XCTAssertEqual(surface.topBar.runtimeIssueSeverity, .warning)
        XCTAssertEqual(surface.settings.runtimeIssue?.title, "TrustedRouter sign-in needed")
    }

    func testRuntimeIssueNormalizesRejectedTrustedRouterKey() throws {
        let model = QuillCodeWorkspaceModel()

        model.setAgentStatus(
            "Failed",
            lastError: "TrustedRouter OAuth exchange failed with HTTP 401: Invalid API key"
        )

        let issue = try XCTUnwrap(model.surface().runtimeIssue)
        XCTAssertEqual(issue.severity, .error)
        XCTAssertEqual(issue.title, "TrustedRouter key rejected")
        XCTAssertEqual(issue.actionLabel, "Fix key")
        XCTAssertTrue(issue.message.contains("Sign in again"))
    }

    func testRuntimeIssueNormalizesMalformedModelAction() throws {
        let model = QuillCodeWorkspaceModel()

        model.setAgentStatus(
            "Failed",
            lastError: "Expected valid QuillCode action JSON but received an empty argument object."
        )

        let issue = try XCTUnwrap(model.surface().runtimeIssue)
        XCTAssertEqual(issue.severity, .warning)
        XCTAssertEqual(issue.title, "Model response was malformed")
        XCTAssertEqual(issue.actionLabel, "Switch model")
    }

    func testRuntimeIssueNormalizesTrustedRouterRateLimit() throws {
        let config = AppConfig(
            defaultModel: "trustedrouter/fusion",
            apiBaseURL: "https://api.trustedrouter.test/v1"
        )
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            config: config,
            topBar: TopBarState(model: "trustedrouter/fusion"),
            trustedRouterAPIKeyConfigured: true
        ))

        model.setAgentStatus(
            "Failed",
            lastError: "TrustedRouter request failed with HTTP 429: Rate limit exceeded. Retry-After: 120. x-ratelimit-remaining: 0"
        )

        let issue = try XCTUnwrap(model.surface().runtimeIssue)
        XCTAssertEqual(issue.severity, .warning)
        XCTAssertEqual(issue.title, "TrustedRouter rate limit reached")
        XCTAssertEqual(issue.actionLabel, "Switch model")
        XCTAssertTrue(issue.message.contains("switch models"))

        let diagnostics = Dictionary(uniqueKeysWithValues: issue.diagnostics.map { ($0.label, $0.value) })
        XCTAssertEqual(diagnostics["Provider status"], "Rate limited")
        XCTAssertEqual(diagnostics["Retry after"], "120s")
        XCTAssertEqual(diagnostics["Rate limit remaining"], "0")
        XCTAssertEqual(diagnostics["Last error"], "TrustedRouter request failed with HTTP 429: Rate limit exceeded. Retry-After: 120. x-ratelimit-remaining: 0")
    }

    func testRuntimeIssueIncludesRedactedDiagnostics() throws {
        let config = AppConfig(
            defaultModel: "z-ai/glm-5.2",
            apiBaseURL: "https://api.trustedrouter.test/v1",
            developerOverrideEnabled: true
        )
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            config: config,
            topBar: TopBarState(model: "z-ai/glm-5.2"),
            trustedRouterAPIKeyConfigured: true
        ))

        model.setAgentStatus(
            "Failed",
            lastError: "TrustedRouter request timed out with Bearer sk-tr-v1-superSecretDiagnosticKey"
        )

        let issue = try XCTUnwrap(model.surface().runtimeIssue)
        let diagnostics = Dictionary(uniqueKeysWithValues: issue.diagnostics.map { ($0.label, $0.value) })
        XCTAssertEqual(diagnostics["API base URL"], "https://api.trustedrouter.test/v1")
        XCTAssertEqual(diagnostics["Authentication"], "Developer override")
        XCTAssertEqual(diagnostics["Key state"], "Configured")
        XCTAssertEqual(diagnostics["Model"], "z-ai/glm-5.2")
        XCTAssertEqual(diagnostics["Agent status"], "Failed")
        XCTAssertTrue(diagnostics["Last error"]?.contains("Bearer ...redacted") == true)
        XCTAssertFalse(diagnostics["Last error"]?.contains("superSecretDiagnosticKey") == true)
        XCTAssertEqual(model.surface().settings.runtimeIssue?.diagnostics, issue.diagnostics)
    }

    func testPrepareRetryLastUserTurnUsesLatestUserPromptAndClearsError() throws {
        let thread = ChatThread(messages: [
            ChatMessage(role: .user, content: "run whoami"),
            ChatMessage(role: .assistant, content: "Network failed."),
            ChatMessage(role: .user, content: "run pwd")
        ])
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            threads: [thread],
            selectedThreadID: thread.id
        ))
        model.setAgentStatus("Failed", lastError: "Network is unreachable")

        XCTAssertTrue(model.prepareRetryLastUserTurn())

        XCTAssertEqual(model.composer.draft, "run pwd")
        XCTAssertNil(model.lastError)
        XCTAssertNil(model.surface().runtimeIssue)
    }

    func testRetryLastTurnCommandReflectsTranscriptAvailability() throws {
        let emptyModel = QuillCodeWorkspaceModel()
        let emptyRetry = try XCTUnwrap(emptyModel.surface().commands.first { $0.id == "retry-last-turn" })
        XCTAssertFalse(emptyRetry.isEnabled)

        let thread = ChatThread(messages: [
            ChatMessage(role: .assistant, content: "I can help."),
            ChatMessage(role: .user, content: "run whoami")
        ])
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            threads: [thread],
            selectedThreadID: thread.id
        ))

        let retry = try XCTUnwrap(model.surface().commands.first { $0.id == "retry-last-turn" })
        XCTAssertTrue(retry.isEnabled)
        XCTAssertEqual(retry.category, WorkspaceCommandPalette.controlCategory)
    }

    func testToolCardsRepresentSafetyReview() {
        let event = ThreadEvent(kind: .approvalRequested, summary: "clarify: needs target")
        let thread = ChatThread(events: [event])

        let cards = QuillCodeWorkspaceModel.toolCards(for: thread)

        XCTAssertEqual(cards.count, 1)
        XCTAssertEqual(cards[0].title, "Safety Check")
        XCTAssertEqual(cards[0].status, .review)
        XCTAssertTrue(cards[0].isExpanded)
    }

    func testToolCardsRepresentStoppedActiveToolAsFailed() throws {
        let call = ToolCall(
            name: ToolDefinition.shellRun.name,
            argumentsJSON: ToolArguments.json(["cmd": "sleep 10"])
        )
        let callJSON = try JSONHelpers.encodePretty(call)
        let thread = ChatThread(events: [
            ThreadEvent(kind: .toolQueued, summary: "queued", payloadJSON: callJSON),
            ThreadEvent(kind: .toolRunning, summary: "running"),
            ThreadEvent(
                kind: .toolFailed,
                summary: "Stopped by user",
                payloadJSON: #"{"ok":false,"error":"Stopped by user"}"#
            ),
            ThreadEvent(kind: .notice, summary: "Stopped by user")
        ])

        let cards = QuillCodeWorkspaceModel.toolCards(for: thread)
        let timeline = QuillCodeWorkspaceModel.transcriptTimelineItems(for: thread)

        XCTAssertEqual(cards.count, 1)
        XCTAssertEqual(cards[0].status, .failed)
        XCTAssertEqual(cards[0].subtitle, "Failed")
        XCTAssertEqual(cards[0].outputJSON, #"{"ok":false,"error":"Stopped by user"}"#)
        XCTAssertEqual(timeline.compactMap(\.toolCard).first?.status, .failed)
    }

    func testBootstrapLoadsConfigAndPersistedThreads() throws {
        let root = try makeTempDirectory()
        let paths = QuillCodePaths(home: root.appendingPathComponent(".quillcode"))
        try paths.ensure()
        try ConfigStore(fileURL: paths.configFile).save(AppConfig(
            defaultModel: "trustedrouter/glm-5.2",
            mode: .review
        ))
        let project = ProjectRef(name: "QuillCode", path: root.path)
        try JSONProjectStore(fileURL: paths.projectsFile).save([project])
        let store = JSONThreadStore(directory: paths.threadsDirectory)
        let older = ChatThread(
            title: "Older",
            projectID: project.id,
            mode: .review,
            model: "trustedrouter/glm-5.2",
            updatedAt: Date(timeIntervalSince1970: 1)
        )
        let newer = ChatThread(
            title: "Newer",
            projectID: project.id,
            mode: .review,
            model: "trustedrouter/glm-5.2",
            updatedAt: Date(timeIntervalSince1970: 2)
        )
        try store.save(older)
        try store.save(newer)

        let model = try QuillCodeWorkspaceBootstrap(paths: paths).makeModel()

        XCTAssertEqual(model.root.config.defaultModel, "trustedrouter/glm-5.2")
        XCTAssertEqual(model.root.config.mode, .review)
        XCTAssertEqual(model.root.projects.map(\.name), ["QuillCode"])
        XCTAssertEqual(model.root.selectedProjectID, project.id)
        XCTAssertEqual(model.root.threads.map(\.title), ["Newer", "Older"])
        XCTAssertEqual(model.root.selectedThreadID, newer.id)
        XCTAssertEqual(model.surface().topBar.primaryTitle, "Newer")
        XCTAssertEqual(model.surface().topBar.subtitle, "QuillCode - Review - trustedrouter/glm-5.2")

        let nextConfig = AppConfig(defaultModel: "trustedrouter/fusion", mode: .auto)
        try QuillCodeWorkspaceBootstrap(paths: paths).saveConfig(nextConfig)
        XCTAssertEqual(try ConfigStore(fileURL: paths.configFile).load(), nextConfig)
    }

    func testModelPersistsProjectRegistryChanges() throws {
        let root = try makeTempDirectory()
        let paths = QuillCodePaths(home: root.appendingPathComponent(".quillcode"))
        try paths.ensure()
        let projectStore = JSONProjectStore(fileURL: paths.projectsFile)
        let model = QuillCodeWorkspaceModel(projectStore: projectStore)

        _ = model.addProject(path: root, name: "QuillCode")

        XCTAssertEqual(try projectStore.load().map(\.name), ["QuillCode"])
    }

    func testBootstrapPersistsAndClearsTrustedRouterAPIKey() throws {
        let paths = QuillCodePaths(home: try makeTempDirectory())
        let bootstrap = QuillCodeWorkspaceBootstrap(paths: paths)

        XCTAssertFalse(bootstrap.hasTrustedRouterAPIKey())
        try bootstrap.saveTrustedRouterAPIKey("  sk-tr-v1-test  ")
        XCTAssertTrue(bootstrap.hasTrustedRouterAPIKey())

        let model = try bootstrap.makeModel()
        XCTAssertTrue(model.surface().settings.hasStoredAPIKey)

        try bootstrap.clearTrustedRouterAPIKey()
        XCTAssertFalse(bootstrap.hasTrustedRouterAPIKey())
    }

    func testRuntimeFactoryUsesTrustedRouterWhenEnvironmentKeyExists() throws {
        let paths = QuillCodePaths(home: try makeTempDirectory())
        try paths.ensure()

        let runtime = QuillCodeRuntimeFactory(
            paths: paths,
            environment: ["TRUSTEDROUTER_API_KEY": "sk-test"]
        ).makeRuntime(config: AppConfig())

        XCTAssertEqual(runtime.mode, .trustedRouter)
        XCTAssertEqual(runtime.statusLabel, "TrustedRouter signed in")
    }

    func testRuntimeFactoryUsesTrustedRouterWhenSecretExists() throws {
        let paths = QuillCodePaths(home: try makeTempDirectory())
        try paths.ensure()
        try FileSecretStore(directory: paths.secretsDirectory).write(
            "sk-test",
            for: QuillSecretKeys.trustedRouterAPIKey
        )

        let runtime = QuillCodeRuntimeFactory(paths: paths, environment: [:])
            .makeRuntime(config: AppConfig())

        XCTAssertEqual(runtime.mode, .trustedRouter)
    }

    func testRuntimeFactoryCanForceMockForDeterministicRuns() throws {
        let paths = QuillCodePaths(home: try makeTempDirectory())
        try paths.ensure()

        let runtime = QuillCodeRuntimeFactory(
            paths: paths,
            environment: [
                "TRUSTEDROUTER_API_KEY": "sk-test",
                "QUILLCODE_USE_MOCK_LLM": "true"
            ]
        ).makeRuntime(config: AppConfig())

        XCTAssertEqual(runtime.mode, .mock)
        XCTAssertEqual(runtime.statusLabel, "Mock LLM")
    }

    func testRunReviewStageActionStagesFileAndRefreshesDiff() throws {
        let root = try makeTempDirectory()
        try initializeGitRepository(at: root)
        try "old\n".write(to: root.appendingPathComponent("hello.txt"), atomically: true, encoding: .utf8)
        _ = try runGit(["add", "hello.txt"], cwd: root)
        _ = try runGit(["commit", "-m", "Initial"], cwd: root)
        try "new\n".write(to: root.appendingPathComponent("hello.txt"), atomically: true, encoding: .utf8)
        let thread = ChatThread(title: "Review")
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            threads: [thread],
            selectedThreadID: thread.id
        ))

        model.runReviewAction(
            WorkspaceReviewActionSurface(kind: .stage, path: "hello.txt"),
            workspaceRoot: root
        )

        XCTAssertEqual(model.root.topBar.agentStatus, "Idle")
        XCTAssertEqual(model.currentToolCards.map(\.title), [
            "host.git.stage",
            "host.git.diff"
        ])
        XCTAssertTrue(model.currentToolCards.allSatisfy { $0.status == .done })
        XCTAssertFalse(model.surface().review.isVisible)
        XCTAssertEqual(try runGit(["status", "--short"], cwd: root), "M  hello.txt\n")
    }

    func testAddReviewCommentAppendsThreadEventForVisibleDiffFile() throws {
        let diff = """
        diff --git a/hello.txt b/hello.txt
        --- a/hello.txt
        +++ b/hello.txt
        @@ -1 +1,2 @@
        +new
         old
        """
        let call = ToolCall(name: "host.git.diff", argumentsJSON: "{}")
        let result = ToolResult(ok: true, stdout: diff)
        let thread = ChatThread(
            title: "Review",
            events: [
                ThreadEvent(kind: .toolQueued, summary: "host.git.diff queued", payloadJSON: try JSONHelpers.encodePretty(call)),
                ThreadEvent(kind: .toolCompleted, summary: "host.git.diff completed", payloadJSON: try JSONHelpers.encodePretty(result))
            ]
        )
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            threads: [thread],
            selectedThreadID: thread.id
        ))

        XCTAssertTrue(model.addReviewComment(path: "hello.txt", text: "Keep this wording direct."))
        XCTAssertTrue(model.addReviewComment(
            path: "hello.txt",
            lineNumber: 1,
            lineKind: .insertion,
            text: "Check the new line."
        ))
        XCTAssertTrue(model.addReviewComment(
            path: "hello.txt",
            lineNumber: 1,
            endLineNumber: 2,
            lineKind: nil,
            text: "Keep these lines together."
        ))
        XCTAssertFalse(model.addReviewComment(path: "README.md", text: "Stale file"))
        XCTAssertFalse(model.addReviewComment(
            path: "hello.txt",
            lineNumber: 1,
            endLineNumber: 4,
            lineKind: nil,
            text: "Invalid range"
        ))

        XCTAssertEqual(model.selectedThread?.events.filter { $0.kind == .reviewComment }.count, 3)
        XCTAssertEqual(model.surface().review.files.first?.comments.map(\.text), ["Keep this wording direct."])
        XCTAssertEqual(
            model.surface().review.files.first?.hunkItems.first?.lines.first?.comments.map(\.text),
            ["Check the new line.", "Keep these lines together."]
        )
        XCTAssertEqual(
            model.surface().review.files.first?.hunkItems.first?.lines.first?.comments.last?.lineRangeLabel,
            "Lines 1-2"
        )
    }

    func testRunReviewRestoreActionRestoresFileAndRefreshesDiff() throws {
        let root = try makeTempDirectory()
        try initializeGitRepository(at: root)
        let fileURL = root.appendingPathComponent("hello.txt")
        try "old\n".write(to: fileURL, atomically: true, encoding: .utf8)
        _ = try runGit(["add", "hello.txt"], cwd: root)
        _ = try runGit(["commit", "-m", "Initial"], cwd: root)
        try "new\n".write(to: fileURL, atomically: true, encoding: .utf8)
        let thread = ChatThread(title: "Review")
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            threads: [thread],
            selectedThreadID: thread.id
        ))

        model.runReviewAction(
            WorkspaceReviewActionSurface(kind: .restore, path: "hello.txt"),
            workspaceRoot: root
        )

        XCTAssertEqual(model.root.topBar.agentStatus, "Idle")
        XCTAssertEqual(model.currentToolCards.map(\.title), [
            "host.git.restore",
            "host.git.diff"
        ])
        XCTAssertTrue(model.currentToolCards.allSatisfy { $0.status == .done })
        XCTAssertEqual(try String(contentsOf: fileURL, encoding: .utf8), "old\n")
        XCTAssertEqual(try runGit(["status", "--short"], cwd: root), "")
        XCTAssertFalse(model.surface().review.isVisible)
    }

    func testRunReviewStageHunkActionStagesPatchAndRefreshesDiff() throws {
        let root = try makeTempDirectory()
        try initializeGitRepository(at: root)
        let fileURL = root.appendingPathComponent("hello.txt")
        try "one\ntwo\nthree\n".write(to: fileURL, atomically: true, encoding: .utf8)
        _ = try runGit(["add", "hello.txt"], cwd: root)
        _ = try runGit(["commit", "-m", "Initial"], cwd: root)
        try "one\nTWO\nthree\n".write(to: fileURL, atomically: true, encoding: .utf8)
        let patch = """
        diff --git a/hello.txt b/hello.txt
        --- a/hello.txt
        +++ b/hello.txt
        @@ -1,3 +1,3 @@
         one
        -two
        +TWO
         three
        """
        let thread = ChatThread(title: "Review")
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            threads: [thread],
            selectedThreadID: thread.id
        ))

        model.runReviewAction(
            WorkspaceReviewActionSurface(
                kind: .stageHunk,
                path: "hello.txt",
                patch: patch,
                targetID: "hello.txt:hunk-1"
            ),
            workspaceRoot: root
        )

        XCTAssertEqual(model.root.topBar.agentStatus, "Idle")
        XCTAssertEqual(model.currentToolCards.map(\.title), [
            "host.git.stage_hunk",
            "host.git.diff"
        ])
        XCTAssertTrue(model.currentToolCards.allSatisfy { $0.status == .done })
        XCTAssertTrue(try runGit(["diff", "--staged"], cwd: root).contains("+TWO"))
        XCTAssertFalse(model.surface().review.isVisible)
    }

    func testRuntimeFactoryModelCatalogFallsBackWithoutKey() async throws {
        let paths = QuillCodePaths(home: try makeTempDirectory())
        try paths.ensure()

        let catalog = await QuillCodeRuntimeFactory(paths: paths, environment: [:])
            .fetchModelCatalog(config: AppConfig())

        XCTAssertEqual(catalog.defaultModelID, TrustedRouterDefaults.defaultModel)
        XCTAssertTrue(catalog.models.contains { $0.id == "trustedrouter/fast" })
        XCTAssertTrue(catalog.models.contains { $0.id == "trustedrouter/fusion" })
        XCTAssertTrue(catalog.models.contains { $0.id == "z-ai/glm-5.2" })
    }

    private func makeTempDirectory() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("QuillCodeAppTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func initializeGitRepository(at root: URL) throws {
        _ = try runGit(["init"], cwd: root)
        _ = try runGit(["config", "user.email", "quillcode-tests@example.com"], cwd: root)
        _ = try runGit(["config", "user.name", "QuillCode Tests"], cwd: root)
    }

    private func makeTempGitRepoWithInitialCommit() throws -> URL {
        let parent = try makeTempDirectory()
        let root = parent.appendingPathComponent("repo")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try initializeGitRepository(at: root)
        try "# Test repo\n".write(to: root.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        _ = try runGit(["add", "README.md"], cwd: root)
        _ = try runGit(["commit", "-m", "initial"], cwd: root)
        return root
    }

    private func writeFixtureMCPServer(in root: URL, callText: String? = nil) throws -> URL {
        let script = root.appendingPathComponent("fixture-mcp.sh")
        let callResponse = callText.map {
            "emit '{\"jsonrpc\":\"2.0\",\"id\":3,\"result\":{\"content\":[{\"type\":\"text\",\"text\":\"\($0)\"}],\"isError\":false}}'"
        } ?? ""
        let content = """
        #!/bin/sh
        emit() {
          body="$1"
          length=$(printf "%s" "$body" | wc -c | tr -d ' ')
          printf "Content-Length: %s\\r\\n\\r\\n%s" "$length" "$body"
        }
        emit '{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2024-11-05","serverInfo":{"name":"Fixture MCP","version":"1.0.0"},"capabilities":{"tools":{}}}}'
        emit '{"jsonrpc":"2.0","id":2,"result":{"tools":[{"name":"read_file","description":"Read a file","inputSchema":{"type":"object"}},{"name":"write_file","inputSchema":{"type":"object"}}]}}'
        \(callResponse)
        sleep 60
        """
        try content.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        return script
    }

    private func runGit(_ arguments: [String], cwd: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git"] + arguments
        process.currentDirectoryURL = cwd

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()

        let out = String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let err = String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        guard process.terminationStatus == 0 else {
            throw NSError(
                domain: "QuillCodeAppTests.Git",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: err.isEmpty ? out : err]
            )
        }
        return out
    }

    private func waitUntil(
        timeoutSeconds: TimeInterval,
        condition: @MainActor @escaping () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while !condition() {
            if Date() > deadline {
                XCTFail("Timed out waiting for condition")
                return
            }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
    }
}

private struct SlowLLMClient: LLMClient {
    func nextAction(thread: ChatThread, userMessage: String, tools: [ToolDefinition]) async throws -> AgentAction {
        try await Task.sleep(nanoseconds: 5_000_000_000)
        return .say("late response")
    }
}

private enum DelayedStreamingSayLLMError: Error {
    case nonStreamingPathUsed
}

private struct DelayedStreamingSayLLMClient: StreamingLLMClient {
    var chunks: [String]

    func nextAction(thread: ChatThread, userMessage: String, tools: [ToolDefinition]) async throws -> AgentAction {
        throw DelayedStreamingSayLLMError.nonStreamingPathUsed
    }

    func actionTextStream(
        thread: ChatThread,
        userMessage: String,
        tools: [ToolDefinition]
    ) async throws -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    try await Task.sleep(nanoseconds: 150_000_000)
                    for (index, chunk) in chunks.enumerated() {
                        continuation.yield(chunk)
                        if index < chunks.count - 1 {
                            try await Task.sleep(nanoseconds: 150_000_000)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

private struct ImmediateToolLLMClient: LLMClient {
    func nextAction(thread: ChatThread, userMessage: String, tools: [ToolDefinition]) async throws -> AgentAction {
        .tool(ToolCall(
            name: ToolDefinition.shellRun.name,
            argumentsJSON: ToolArguments.json(["cmd": "pwd"])
        ))
    }
}

private struct FixedToolLLMClient: LLMClient {
    var call: ToolCall

    func nextAction(thread: ChatThread, userMessage: String, tools: [ToolDefinition]) async throws -> AgentAction {
        .tool(call)
    }
}

private struct SlowApprovingSafetyReviewer: SafetyReviewer {
    func review(_ context: SafetyContext) async -> SafetyReview {
        try? await Task.sleep(nanoseconds: 200_000_000)
        return SafetyReview(
            verdict: .approve,
            rationale: "The tool call is bounded and matches the current user request.",
            userIntentMatched: true
        )
    }
}
