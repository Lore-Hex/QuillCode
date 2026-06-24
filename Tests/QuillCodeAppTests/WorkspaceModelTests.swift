import XCTest
import QuillCodeAgent
import QuillCodeCore
import QuillCodePersistence
import QuillCodeSafety
import QuillCodeTools
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
        XCTAssertEqual(WorkspaceTranscriptSurfaceBuilder(thread: thread).messageSurfaces().map(\.role), [.user, .assistant])
        let timeline = WorkspaceTranscriptSurfaceBuilder(thread: thread).timelineItems()
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
        XCTAssertEqual(WorkspaceTranscriptSurfaceBuilder(thread: thread).messageSurfaces().last?.feedback, .helpful)
        XCTAssertEqual(WorkspaceTranscriptSurfaceBuilder(thread: thread).timelineItems().last?.message?.feedback, .helpful)
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
        XCTAssertEqual(card.artifacts.first?.textPreview, "hello world\n")
        XCTAssertEqual(card.textPreviewArtifacts.map(\.label), ["hello.txt"])
    }

    func testArtifactStateDerivesLinksAndImagePreviews() {
        let imageFile = ToolArtifactState(value: "/tmp/quillcode/screenshot.png")
        XCTAssertEqual(imageFile.kind, .file)
        XCTAssertEqual(imageFile.href, "file:///tmp/quillcode/screenshot.png")
        XCTAssertTrue(imageFile.isImagePreview)
        XCTAssertEqual(imageFile.previewURL, imageFile.href)
        XCTAssertEqual(imageFile.imagePreview?.typeLabel, "Image")
        XCTAssertEqual(imageFile.imagePreview?.extensionLabel, "PNG")
        XCTAssertEqual(imageFile.imagePreview?.detail, "/tmp/quillcode")

        let imageURL = ToolArtifactState(value: "https://example.com/assets/mock.webp?size=large")
        XCTAssertEqual(imageURL.kind, .url)
        XCTAssertEqual(imageURL.href, "https://example.com/assets/mock.webp?size=large")
        XCTAssertEqual(imageURL.label, "example.com/assets/mock.webp")
        XCTAssertTrue(imageURL.isImagePreview)
        XCTAssertEqual(imageURL.previewURL, imageURL.href)
        XCTAssertEqual(imageURL.imagePreview?.extensionLabel, "WEBP")
        XCTAssertEqual(imageURL.imagePreview?.detail, "example.com/assets/mock.webp")

        let inlineImage = ToolArtifactState(value: "data:image/png;base64,AAAA")
        XCTAssertEqual(inlineImage.kind, .url)
        XCTAssertEqual(inlineImage.label, "Inline image")
        XCTAssertEqual(inlineImage.detail, "Image artifact")
        XCTAssertTrue(inlineImage.isImagePreview)
        XCTAssertEqual(inlineImage.previewURL, "data:image/png;base64,AAAA")
        XCTAssertEqual(inlineImage.imagePreview?.extensionLabel, "PNG")
        XCTAssertEqual(inlineImage.imagePreview?.detail, "Image artifact")
        XCTAssertNil(inlineImage.textPreview)

        let nonImageData = ToolArtifactState(value: "data:text/plain;base64,SGVsbG8=")
        XCTAssertEqual(nonImageData.kind, .path)
        XCTAssertEqual(nonImageData.label, "data:text/plain;base64,SGVsbG8=")
        XCTAssertFalse(nonImageData.isImagePreview)
        XCTAssertNil(nonImageData.previewURL)
        XCTAssertNil(nonImageData.imagePreview)
        XCTAssertNil(nonImageData.href)
        XCTAssertNil(nonImageData.textPreview)
    }

    func testArtifactStateDerivesDocumentPreviews() {
        let pdfFile = ToolArtifactState(value: "/tmp/quillcode/reports/briefing.pdf")
        XCTAssertEqual(pdfFile.kind, .file)
        XCTAssertFalse(pdfFile.isImagePreview)
        XCTAssertTrue(pdfFile.isDocumentPreview)
        XCTAssertEqual(pdfFile.documentPreview?.kind, .pdf)
        XCTAssertEqual(pdfFile.documentPreview?.typeLabel, "PDF")
        XCTAssertEqual(pdfFile.documentPreview?.extensionLabel, "PDF")
        XCTAssertEqual(pdfFile.documentPreview?.detail, "/tmp/quillcode/reports")

        let spreadsheetURL = ToolArtifactState(value: "https://example.com/artifacts/budget.xlsx?download=1")
        XCTAssertEqual(spreadsheetURL.kind, .url)
        XCTAssertTrue(spreadsheetURL.isDocumentPreview)
        XCTAssertEqual(spreadsheetURL.documentPreview?.kind, .spreadsheet)
        XCTAssertEqual(spreadsheetURL.documentPreview?.typeLabel, "Spreadsheet")
        XCTAssertEqual(spreadsheetURL.documentPreview?.extensionLabel, "XLSX")
        XCTAssertEqual(spreadsheetURL.documentPreview?.detail, "example.com/artifacts/budget.xlsx")
        XCTAssertEqual(spreadsheetURL.href, "https://example.com/artifacts/budget.xlsx?download=1")

        let appshotBundle = ToolArtifactState(value: "/tmp/quillcode/appshots/checkout.appshot.json")
        XCTAssertEqual(appshotBundle.kind, .file)
        XCTAssertTrue(appshotBundle.isDocumentPreview)
        XCTAssertEqual(appshotBundle.documentPreview?.kind, .appshot)
        XCTAssertEqual(appshotBundle.documentPreview?.typeLabel, "Appshot")
        XCTAssertEqual(appshotBundle.documentPreview?.extensionLabel, "APPSHOT")
        XCTAssertEqual(appshotBundle.documentPreview?.detail, "/tmp/quillcode/appshots")

        let textFile = ToolArtifactState(value: "/tmp/quillcode/notes.md", textPreview: "# Notes\n")
        XCTAssertFalse(textFile.isDocumentPreview)
        XCTAssertTrue(textFile.hasTextPreview)
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

    func testCompletedComposerRunDoesNotStealSelectionAfterUserSwitchesThreads() async throws {
        let root = try makeTempDirectory()
        let model = QuillCodeWorkspaceModel(
            runner: AgentRunner(llm: DelayedStreamingSayLLMClient(chunks: [
                #"{"type":"say","text":"done"}"#
            ]))
        )
        let firstThreadID = model.newChat()

        model.setDraft("run a short task")
        let task = Task {
            await model.submitComposer(workspaceRoot: root)
        }
        try await waitUntil(timeoutSeconds: 1) {
            model.composer.isSending
        }
        let secondThreadID = model.newChat()

        await task.value

        XCTAssertEqual(model.root.selectedThreadID, secondThreadID)
        let firstThread = try XCTUnwrap(model.root.threads.first { $0.id == firstThreadID })
        let secondThread = try XCTUnwrap(model.root.threads.first { $0.id == secondThreadID })
        XCTAssertTrue(firstThread.messages.contains { $0.role == .assistant && $0.content == "done" })
        XCTAssertTrue(secondThread.messages.isEmpty)
    }

    func testTerminalCommandRunsThroughSSHRemoteProject() async throws {
        let root = try makeTempDirectory()
        let argumentsFile = root.appendingPathComponent("ssh-args.txt")
        let fakeSSH = try makeFakeSSH(in: root, argumentsFile: argumentsFile)
        let connection = ProjectConnection.ssh(
            path: "/srv/quill repo",
            host: "feather.local",
            user: "quill",
            port: 2222
        )
        let project = ProjectRef(name: "Feather", path: connection.path, connection: connection)
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(projects: [project], selectedProjectID: project.id),
            sshRemoteShellExecutor: SSHRemoteShellExecutor(
                sshExecutable: fakeSSH.path,
                connectTimeoutSeconds: 4
            )
        )

        await model.runTerminalCommand("printf remote-terminal", workspaceRoot: root)

        XCTAssertEqual(model.terminal.entries.count, 1)
        XCTAssertEqual(model.terminal.entries[0].status, .done)
        XCTAssertEqual(model.terminal.entries[0].stdout, "remote-terminal\n")
        XCTAssertEqual(model.terminal.currentDirectoryPath, "ssh://quill@feather.local:2222/srv/quill repo")
        let surface = model.surface()
        XCTAssertEqual(surface.terminal.cwdLabel, "ssh://quill@feather.local:2222/srv/quill repo")
        XCTAssertEqual(surface.terminal.entries.first?.executionContext?.kind, .sshRemote)
        XCTAssertEqual(surface.terminal.entries.first?.executionContext?.label, "SSH Remote")
        XCTAssertEqual(surface.terminal.entries.first?.executionContext?.detail, "feather.local")
        let arguments = try String(contentsOf: argumentsFile, encoding: .utf8)
        XCTAssertTrue(arguments.contains("-T\n-o\nBatchMode=yes\n-o\nConnectTimeout=4\n-p\n2222\nquill@feather.local\n"))
        XCTAssertTrue(arguments.contains("cd '/srv/quill repo' &&"))
        XCTAssertTrue(arguments.contains("printf remote-terminal"))
        XCTAssertTrue(arguments.contains("__QUILLCODE_TERMINAL_"))
    }

    func testTerminalCommandPersistsSSHRemoteCWDAndEnvironment() async throws {
        let root = try makeTempDirectory()
        let remoteRoot = root.appendingPathComponent("remote repo")
        try FileManager.default.createDirectory(at: remoteRoot, withIntermediateDirectories: true)
        let argumentsFile = root.appendingPathComponent("ssh-args.txt")
        let fakeSSH = try makeExecutingFakeSSH(in: root, argumentsFile: argumentsFile)
        let connection = ProjectConnection.ssh(
            path: remoteRoot.path,
            host: "feather.local",
            user: "quill"
        )
        let project = ProjectRef(name: "Feather", path: connection.path, connection: connection)
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(projects: [project], selectedProjectID: project.id),
            sshRemoteShellExecutor: SSHRemoteShellExecutor(
                sshExecutable: fakeSSH.path,
                connectTimeoutSeconds: 4
            )
        )

        await model.runTerminalCommand(
            "mkdir -p nested && cd nested && export QUILL_REMOTE_TERMINAL=works && printf remote-one",
            workspaceRoot: root
        )

        let nestedPath = remoteRoot.appendingPathComponent("nested").path
        XCTAssertEqual(model.terminal.entries[0].status, .done)
        XCTAssertEqual(model.terminal.entries[0].stdout, "remote-one")
        XCTAssertEqual(model.terminal.currentDirectoryPath, "ssh://quill@feather.local\(nestedPath)")
        XCTAssertEqual(model.terminal.environmentOverrides["QUILL_REMOTE_TERMINAL"], "works")

        await model.runTerminalCommand(
            #"pwd && printf ':' && printf "$QUILL_REMOTE_TERMINAL""#,
            workspaceRoot: root
        )

        XCTAssertEqual(model.terminal.entries[1].status, .done)
        XCTAssertEqual(model.terminal.entries[1].stdout, "\(nestedPath)\n:works")
        let arguments = try String(contentsOf: argumentsFile, encoding: .utf8)
        XCTAssertTrue(arguments.contains("cd '\(nestedPath.replacingOccurrences(of: "'", with: "'\\''"))' &&"))
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

    func testRemoteWorkspaceCommandListsGitWorktreesThroughSSH() throws {
        let root = try makeTempDirectory()
        let remoteRoot = try makeTempGitRepoWithInitialCommit()
        let argumentsFile = root.appendingPathComponent("ssh-agent-args.txt")
        let fakeSSH = try makeExecutingFakeSSH(in: root, argumentsFile: argumentsFile)
        let connection = ProjectConnection.ssh(
            path: remoteRoot.path,
            host: "feather.local",
            user: "quill",
            port: 2222
        )
        let project = ProjectRef(name: "Feather", path: connection.path, connection: connection)
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(projects: [project], selectedProjectID: project.id),
            sshRemoteShellExecutor: SSHRemoteShellExecutor(
                sshExecutable: fakeSSH.path,
                connectTimeoutSeconds: 4
            )
        )

        XCTAssertTrue(model.runWorkspaceCommand("git-worktree-list", workspaceRoot: root))

        let card = try XCTUnwrap(model.currentToolCards.last)
        XCTAssertEqual(card.title, ToolDefinition.gitWorktreeList.name)
        XCTAssertEqual(card.executionContext?.kind, .sshRemote)
        XCTAssertEqual(card.status, .done)
        let result = try JSONHelpers.decode(ToolResult.self, from: XCTUnwrap(card.outputJSON))
        XCTAssertTrue(result.stdout.contains(remoteRoot.standardizedFileURL.path), result.stdout)
        let sshArguments = try String(contentsOf: argumentsFile, encoding: .utf8)
        XCTAssertTrue(sshArguments.contains("git worktree list --porcelain"), sshArguments)
    }

    func testRemoteWorkspaceCommandsViewPullRequestAndChecksThroughSSH() throws {
        let root = try makeTempDirectory()
        let bin = root.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let ghArgumentsFile = root.appendingPathComponent("gh-args.txt")
        _ = try makeFakeGitHubCLI(in: bin, argumentsFile: ghArgumentsFile)
        let sshArgumentsFile = root.appendingPathComponent("ssh-args.txt")
        let fakeSSH = try makeExecutingFakeSSH(in: root, argumentsFile: sshArgumentsFile, pathPrefix: bin)
        let remoteRoot = try makeTempGitRepoWithInitialCommit()
        let connection = ProjectConnection.ssh(
            path: remoteRoot.path,
            host: "feather.local",
            user: "quill",
            port: 2222
        )
        let project = ProjectRef(name: "Feather", path: connection.path, connection: connection)
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(projects: [project], selectedProjectID: project.id),
            sshRemoteShellExecutor: SSHRemoteShellExecutor(
                sshExecutable: fakeSSH.path,
                connectTimeoutSeconds: 4
            )
        )

        XCTAssertTrue(model.runWorkspaceCommand("git-pr-view", workspaceRoot: root))
        var card = try XCTUnwrap(model.currentToolCards.last)
        XCTAssertEqual(card.title, ToolDefinition.gitPullRequestView.name)
        XCTAssertEqual(card.executionContext?.kind, .sshRemote)
        XCTAssertEqual(card.status, .done)
        XCTAssertEqual(card.artifacts.map(\.value), ["https://github.com/example/repo/pull/456"])
        var ghArguments = try String(contentsOf: ghArgumentsFile, encoding: .utf8)
        XCTAssertEqual(ghArguments.split(separator: "\n").map(String.init), ["pr", "view", "--comments"])

        XCTAssertTrue(model.runWorkspaceCommand("git-pr-checks", workspaceRoot: root))
        card = try XCTUnwrap(model.currentToolCards.last)
        XCTAssertEqual(card.title, ToolDefinition.gitPullRequestChecks.name)
        XCTAssertEqual(card.executionContext?.kind, .sshRemote)
        XCTAssertEqual(card.status, .done)
        ghArguments = try String(contentsOf: ghArgumentsFile, encoding: .utf8)
        XCTAssertEqual(ghArguments.split(separator: "\n").map(String.init), ["pr", "checks"])

        XCTAssertTrue(model.runWorkspaceCommand("git-pr-diff", workspaceRoot: root))
        card = try XCTUnwrap(model.currentToolCards.last)
        XCTAssertEqual(card.title, ToolDefinition.gitPullRequestDiff.name)
        XCTAssertEqual(card.executionContext?.kind, .sshRemote)
        XCTAssertEqual(card.status, .done)
        ghArguments = try String(contentsOf: ghArgumentsFile, encoding: .utf8)
        XCTAssertEqual(ghArguments.split(separator: "\n").map(String.init), ["pr", "diff"])

        XCTAssertTrue(model.runWorkspaceCommand("git-pr-checkout", workspaceRoot: root))
        XCTAssertEqual(model.composer.draft, "Checkout pull request ")
    }

    func testPullRequestSlashCommandsDispatchStructuredGitHubToolsThroughSSH() async throws {
        let root = try makeTempDirectory()
        let bin = root.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let ghArgumentsFile = root.appendingPathComponent("gh-args.txt")
        _ = try makeFakeGitHubCLI(in: bin, argumentsFile: ghArgumentsFile)
        let sshArgumentsFile = root.appendingPathComponent("ssh-args.txt")
        let fakeSSH = try makeExecutingFakeSSH(in: root, argumentsFile: sshArgumentsFile, pathPrefix: bin)
        let remoteRoot = try makeTempGitRepoWithInitialCommit()
        let connection = ProjectConnection.ssh(path: remoteRoot.path, host: "feather.local", user: "quill")
        let project = ProjectRef(name: "Feather", path: connection.path, connection: connection)
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(projects: [project], selectedProjectID: project.id),
            sshRemoteShellExecutor: SSHRemoteShellExecutor(
                sshExecutable: fakeSSH.path,
                connectTimeoutSeconds: 4
            )
        )

        func ghArguments() throws -> [String] {
            try String(contentsOf: ghArgumentsFile, encoding: .utf8)
                .split(separator: "\n")
                .map(String.init)
        }

        model.setDraft("/pr view 456")
        await model.submitComposer(workspaceRoot: root)
        XCTAssertEqual(model.currentToolCards.last?.title, ToolDefinition.gitPullRequestView.name)
        XCTAssertEqual(model.currentToolCards.last?.executionContext?.kind, .sshRemote)
        XCTAssertEqual(try ghArguments(), ["pr", "view", "456", "--comments"])

        model.setDraft("/pr checks 456")
        await model.submitComposer(workspaceRoot: root)
        XCTAssertEqual(model.currentToolCards.last?.title, ToolDefinition.gitPullRequestChecks.name)
        XCTAssertEqual(try ghArguments(), ["pr", "checks", "456"])

        model.setDraft("/pr diff 456")
        await model.submitComposer(workspaceRoot: root)
        XCTAssertEqual(model.currentToolCards.last?.title, ToolDefinition.gitPullRequestDiff.name)
        XCTAssertEqual(try ghArguments(), ["pr", "diff", "456"])

        model.setDraft("/pr checkout 456")
        await model.submitComposer(workspaceRoot: root)
        XCTAssertEqual(model.currentToolCards.last?.title, ToolDefinition.gitPullRequestCheckout.name)
        XCTAssertEqual(try ghArguments(), ["pr", "checkout", "456"])

        model.setDraft("/pr comment 456 ship it")
        await model.submitComposer(workspaceRoot: root)
        XCTAssertEqual(model.currentToolCards.last?.title, ToolDefinition.gitPullRequestComment.name)
        XCTAssertEqual(try ghArguments(), ["pr", "comment", "456", "--body", "ship it"])

        model.setDraft("/pr review approve 456")
        await model.submitComposer(workspaceRoot: root)
        XCTAssertEqual(model.currentToolCards.last?.title, ToolDefinition.gitPullRequestReview.name)
        XCTAssertEqual(try ghArguments(), ["pr", "review", "456", "--approve"])

        model.setDraft("/pr reviewers add alice bob")
        await model.submitComposer(workspaceRoot: root)
        XCTAssertEqual(model.currentToolCards.last?.title, ToolDefinition.gitPullRequestReviewers.name)
        XCTAssertEqual(try ghArguments(), ["pr", "edit", "--add-reviewer", "alice,bob"])

        model.setDraft("/pr labels add 456 merge-train, needs review")
        await model.submitComposer(workspaceRoot: root)
        XCTAssertEqual(model.currentToolCards.last?.title, ToolDefinition.gitPullRequestLabels.name)
        XCTAssertEqual(try ghArguments(), ["pr", "edit", "456", "--add-label", "merge-train,needs review"])

        model.setDraft("/pr labels remove stale")
        await model.submitComposer(workspaceRoot: root)
        XCTAssertEqual(model.currentToolCards.last?.title, ToolDefinition.gitPullRequestLabels.name)
        XCTAssertEqual(try ghArguments(), ["pr", "edit", "--remove-label", "stale"])

        model.setDraft("/pr merge 456 rebase auto delete-branch")
        await model.submitComposer(workspaceRoot: root)
        XCTAssertEqual(model.currentToolCards.last?.title, ToolDefinition.gitPullRequestMerge.name)
        XCTAssertEqual(try ghArguments(), ["pr", "merge", "456", "--rebase", "--auto", "--delete-branch"])
    }

    func testWorkspaceWorktreeCommandsPrefillComposer() throws {
        let root = try makeTempDirectory()
        let model = QuillCodeWorkspaceModel()

        XCTAssertTrue(model.runWorkspaceCommand("git-pr-create", workspaceRoot: root))
        XCTAssertEqual(model.composer.draft, "Create a pull request titled ")

        XCTAssertTrue(model.runWorkspaceCommand("git-pr-checkout", workspaceRoot: root))
        XCTAssertEqual(model.composer.draft, "Checkout pull request ")

        XCTAssertTrue(model.runWorkspaceCommand("git-pr-reviewers", workspaceRoot: root))
        XCTAssertEqual(model.composer.draft, "Request reviewers for the current pull request: ")

        XCTAssertTrue(model.runWorkspaceCommand("git-pr-comment", workspaceRoot: root))
        XCTAssertEqual(model.composer.draft, "Comment on the current pull request: ")

        XCTAssertTrue(model.runWorkspaceCommand("git-pr-review", workspaceRoot: root))
        XCTAssertEqual(model.composer.draft, "Review the current pull request: approve")

        XCTAssertTrue(model.runWorkspaceCommand("git-pr-labels", workspaceRoot: root))
        XCTAssertEqual(model.composer.draft, "Label the current pull request: ")

        XCTAssertTrue(model.runWorkspaceCommand("git-pr-merge", workspaceRoot: root))
        XCTAssertEqual(model.composer.draft, "Merge the current pull request with squash")

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
            WorkspaceTranscriptSurfaceBuilder(thread: thread).toolCards().contains { card in
                card.title == "host.git.worktree.create"
            }
        })
        XCTAssertNotEqual(createThread.id, model.selectedThread?.id)
        let createCard = try XCTUnwrap(WorkspaceTranscriptSurfaceBuilder(thread: createThread).toolCards().last)
        XCTAssertEqual(createCard.status, .done)
        XCTAssertTrue(createCard.inputJSON?.contains(worktreeName) == true)

        model.removeWorktree(.init(path: worktreeName), workspaceRoot: root)

        XCTAssertFalse(FileManager.default.fileExists(atPath: worktree.path))
        XCTAssertEqual(model.currentToolCards.last?.title, "host.git.worktree.remove")
        XCTAssertEqual(model.currentToolCards.last?.status, .done)
    }

    func testRemoteWorkspaceCreateWorktreeOpensSSHProjectAndKeepsToolAudit() throws {
        let root = try makeTempDirectory()
        let remoteRoot = try makeTempGitRepoWithInitialCommit()
        let parent = remoteRoot.deletingLastPathComponent()
        let worktreeName = "remote-ui-\(UUID().uuidString)"
        let branch = "remote-ui-\(UUID().uuidString.prefix(8))"
        let worktree = parent.appendingPathComponent(worktreeName).standardizedFileURL
        let argumentsFile = root.appendingPathComponent("ssh-agent-args.txt")
        let fakeSSH = try makeExecutingFakeSSH(in: root, argumentsFile: argumentsFile)
        let connection = ProjectConnection.ssh(
            path: remoteRoot.path,
            host: "feather.local",
            user: "quill",
            port: 2222
        )
        let project = ProjectRef(name: "Feather", path: connection.path, connection: connection)
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(projects: [project], selectedProjectID: project.id),
            sshRemoteShellExecutor: SSHRemoteShellExecutor(
                sshExecutable: fakeSSH.path,
                connectTimeoutSeconds: 4
            )
        )

        model.createWorktree(.init(path: worktreeName, branch: String(branch)), workspaceRoot: root)

        XCTAssertTrue(FileManager.default.fileExists(atPath: worktree.path))
        XCTAssertEqual(model.selectedProject?.connection.kind, .ssh)
        XCTAssertEqual(model.selectedProject?.connection.host, "feather.local")
        XCTAssertEqual(model.selectedProject?.connection.user, "quill")
        XCTAssertEqual(model.selectedProject?.connection.port, 2222)
        XCTAssertEqual(model.selectedProject?.connection.path, worktree.path)
        XCTAssertEqual(model.selectedThread?.projectID, model.selectedProject?.id)
        XCTAssertEqual(model.selectedThread?.title, "Worktree: \(branch)")
        XCTAssertTrue(model.selectedThread?.messages.last?.content.contains("Opened remote worktree `\(worktreeName)`") == true)
        XCTAssertEqual(model.root.topBar.projectName, "feather.local · \(worktreeName)")

        let createThread = try XCTUnwrap(model.root.threads.first { thread in
            WorkspaceTranscriptSurfaceBuilder(thread: thread).toolCards().contains { card in
                card.title == ToolDefinition.gitWorktreeCreate.name
            }
        })
        XCTAssertNotEqual(createThread.id, model.selectedThread?.id)
        let createCard = try XCTUnwrap(WorkspaceTranscriptSurfaceBuilder(thread: createThread).toolCards().last)
        XCTAssertEqual(createCard.status, .done)
        let createResult = try JSONHelpers.decode(ToolResult.self, from: XCTUnwrap(createCard.outputJSON))
        XCTAssertEqual(createResult.artifacts, ["ssh://quill@feather.local:2222\(worktree.path)"])
    }

    func testEmptyDraftDoesNotCreateThread() async throws {
        let model = QuillCodeWorkspaceModel()
        model.setDraft("   ")
        await model.submitComposer(workspaceRoot: try makeTempDirectory())
        XCTAssertTrue(model.root.threads.isEmpty)
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
            topBar: TopBarState(model: TrustedRouterDefaults.synthModel),
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
            statusLabel: QuillCodeRuntimeStatusLabel.trustedRouterReady
        ))

        XCTAssertEqual(model.root.topBar.agentStatus, QuillCodeRuntimeStatusLabel.trustedRouterReady)
    }

    func testRuntimeIssueSurfacesMissingTrustedRouterSignIn() {
        let model = QuillCodeWorkspaceModel()

        model.applyRuntime(QuillCodeRuntime(
            runner: AgentRunner(),
            mode: .trustedRouter,
            statusLabel: QuillCodeRuntimeStatusLabel.signInWithTrustedRouter
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
            defaultModel: TrustedRouterDefaults.synthModel,
            apiBaseURL: "https://api.trustedrouter.test/v1"
        )
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            config: config,
            topBar: TopBarState(model: TrustedRouterDefaults.synthModel),
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

    func testToolCardsRepresentActionableApprovalReview() throws {
        let call = ToolCall(
            id: "approval-tool",
            name: ToolDefinition.shellRun.name,
            argumentsJSON: ToolArguments.json(["cmd": "whoami"])
        )
        let request = ApprovalRequest(
            id: "approval-request",
            toolCall: call,
            toolDefinition: ToolDefinition.shellRun,
            reason: "review required"
        )
        let event = ThreadEvent(
            kind: .approvalRequested,
            summary: "clarify: needs target",
            payloadJSON: try JSONHelpers.encodePretty(request)
        )
        let thread = ChatThread(events: [event])

        let cards = WorkspaceTranscriptSurfaceBuilder(thread: thread).toolCards()

        XCTAssertEqual(cards.count, 1)
        XCTAssertEqual(cards[0].title, ToolDefinition.shellRun.name)
        XCTAssertEqual(cards[0].status, .review)
        XCTAssertTrue(cards[0].isExpanded)
        XCTAssertEqual(cards[0].density, .expanded)
        XCTAssertEqual(cards[0].reviewState, .ready)
        XCTAssertEqual(cards[0].inputJSON, ToolArguments.json(["cmd": "whoami"]))
        XCTAssertEqual(cards[0].actions.map(\.title), ["Run", "Skip"])
    }

    func testToolCardApprovalActionRecordsDecisionAndRunsTool() throws {
        let root = try makeTempDirectory()
        let call = ToolCall(
            id: "approval-tool-run",
            name: ToolDefinition.shellRun.name,
            argumentsJSON: ToolArguments.json(["cmd": "whoami"])
        )
        let request = ApprovalRequest(
            id: "approval-run",
            toolCall: call,
            toolDefinition: ToolDefinition.shellRun,
            reason: "review required"
        )
        let thread = ChatThread(events: [
            ThreadEvent(
                kind: .approvalRequested,
                summary: "review required",
                payloadJSON: try JSONHelpers.encodePretty(request)
            )
        ])
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            threads: [thread],
            selectedThreadID: thread.id
        ))

        let didRun = model.runToolCardAction(ToolCardActionSurface(
            title: "Run",
            kind: .approve,
            requestID: "approval-run",
            style: .primary
        ), workspaceRoot: root)

        XCTAssertTrue(didRun)
        let events = try XCTUnwrap(model.selectedThread?.events)
        XCTAssertTrue(events.contains { $0.kind == .approvalDecided })
        XCTAssertTrue(events.contains { $0.kind == .toolQueued })
        XCTAssertTrue(events.contains { $0.kind == .toolCompleted })
        let cards = model.currentToolCards
        XCTAssertTrue(cards.contains { $0.status == .done && $0.subtitle == "Approved · whoami" })
        XCTAssertTrue(cards.contains { $0.title == ToolDefinition.shellRun.name && $0.outputJSON?.contains("exitCode") == true })
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

        let cards = WorkspaceTranscriptSurfaceBuilder(thread: thread).toolCards()
        let timeline = WorkspaceTranscriptSurfaceBuilder(thread: thread).timelineItems()

        XCTAssertEqual(cards.count, 1)
        XCTAssertEqual(cards[0].status, .failed)
        XCTAssertEqual(cards[0].subtitle, "Failed · sleep 10")
        XCTAssertEqual(cards[0].density, .expanded)
        XCTAssertEqual(cards[0].outputJSON, #"{"ok":false,"error":"Stopped by user"}"#)
        XCTAssertEqual(timeline.compactMap(\.toolCard).first?.status, .failed)
        XCTAssertEqual(timeline.compactMap(\.toolCard).first?.density, .expanded)
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
        try JSONAutomationStore(fileURL: paths.automationsFile).save([
            QuillAutomation(
                title: "Ship follow-up",
                detail: "Check whether the release branch is ready.",
                kind: .threadFollowUp,
                scheduleKind: .heartbeat,
                scheduleDescription: "Tomorrow at 9:00 AM",
                projectID: project.id,
                threadID: newer.id,
                nextRunAt: Date(timeIntervalSince1970: 10)
            )
        ])

        let model = try QuillCodeWorkspaceBootstrap(paths: paths).makeModel()

        XCTAssertEqual(model.root.config.defaultModel, "trustedrouter/glm-5.2")
        XCTAssertEqual(model.root.config.mode, .review)
        XCTAssertEqual(model.root.projects.map(\.name), ["QuillCode"])
        XCTAssertEqual(model.root.selectedProjectID, project.id)
        XCTAssertEqual(model.root.threads.map(\.title), ["Newer", "Older"])
        XCTAssertEqual(model.root.selectedThreadID, newer.id)
        XCTAssertEqual(model.surface().topBar.primaryTitle, "Newer")
        XCTAssertEqual(model.surface().topBar.subtitle, "QuillCode - Review - trustedrouter/glm-5.2")
        XCTAssertEqual(model.surface().automations.statusLabel, "1 active")
        XCTAssertEqual(model.surface().automations.workflows.map(\.title), ["Ship follow-up"])
        XCTAssertEqual(model.surface().automations.workflows.first?.scheduleLabel, "Tomorrow at 9:00 AM")

        let nextConfig = AppConfig(defaultModel: TrustedRouterDefaults.synthModel, mode: .auto)
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

    func testPlanUpdateToolRecordsNormalizedActivityPlan() throws {
        let model = QuillCodeWorkspaceModel(activity: ActivityState(isVisible: true))
        _ = model.newChat()
        let update = AgentPlanUpdate(
            explanation: "  Keep the plan visible while work proceeds.  ",
            plan: [
                AgentPlanItem(step: "  Inspect state  ", status: .completed),
                AgentPlanItem(step: "Implement change", status: .inProgress, detail: "  One reviewable slice.  "),
                AgentPlanItem(step: "Validate and summarize", status: .pending)
            ]
        )
        let call = ToolCall(
            name: ToolDefinition.planUpdate.name,
            argumentsJSON: try JSONHelpers.encodePretty(update)
        )

        let result = model.runToolCall(call, workspaceRoot: try makeTempDirectory())
        let decoded = try JSONHelpers.decode(AgentPlanUpdate.self, from: result.stdout)

        XCTAssertTrue(result.ok, result.error ?? "")
        XCTAssertEqual(decoded.explanation, "Keep the plan visible while work proceeds.")
        XCTAssertEqual(decoded.plan.map(\.step), ["Inspect state", "Implement change", "Validate and summarize"])
        XCTAssertEqual(model.selectedThread?.events.last?.summary, "\(ToolDefinition.planUpdate.name) completed")
        XCTAssertEqual(model.surface().activity.planItems.map(\.title), [
            "Inspect state",
            "Implement change",
            "Validate and summarize"
        ])
        XCTAssertEqual(model.surface().activity.planItems.map(\.statusLabel), ["Done", "Running", "Pending"])
        XCTAssertEqual(model.surface().activity.planItems[1].detail, "One reviewable slice.")
    }

    func testPlanUpdateToolRejectsMultipleRunningSteps() throws {
        let model = QuillCodeWorkspaceModel()
        _ = model.newChat()
        let update = AgentPlanUpdate(
            plan: [
                AgentPlanItem(step: "First", status: .inProgress),
                AgentPlanItem(step: "Second", status: .inProgress)
            ]
        )
        let call = ToolCall(
            name: ToolDefinition.planUpdate.name,
            argumentsJSON: try JSONHelpers.encodePretty(update)
        )

        let result = model.runToolCall(call, workspaceRoot: try makeTempDirectory())

        XCTAssertFalse(result.ok)
        XCTAssertEqual(result.error, "Plan update can have at most one in_progress step.")
        XCTAssertEqual(model.root.topBar.agentStatus, "Failed")
    }

    private func makeTempDirectory() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("QuillCodeAppTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
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
