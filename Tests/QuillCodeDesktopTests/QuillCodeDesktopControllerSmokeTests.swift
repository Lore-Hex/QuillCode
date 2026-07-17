import XCTest
import QuillCodeAgent
import QuillCodeApp
import QuillCodeCore
import QuillCodePersistence
import QuillCodeTools
import QuillComputerUseKit
@testable import quill_code_desktop

@MainActor
final class QuillCodeDesktopControllerSmokeTests: XCTestCase {

    func testDesktopRegistersOnlyAProbedSSHProjectAndUsesResolvedFolder() async throws {
        let root = try makeTempDirectory()
        let fakeSSH = root.appendingPathComponent("fake-ssh")
        try #"""
        #!/bin/sh
        printf '__QUILLCODE_SSH_READY__\n/srv/resolved-project\n'
        """#.write(to: fakeSSH, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeSSH.path)
        let probe = SSHRemoteProjectProbe(
            remoteExecutor: SSHRemoteShellExecutor(sshExecutable: fakeSSH.path)
        )
        let controller = try makeController(
            workspaceRoot: root,
            sshRemoteProjectProbe: probe
        )

        let request = try XCTUnwrap(WorkspaceSSHProjectRequest(
            connection: .ssh(path: "~/project", host: "production"),
            name: "Production"
        ))
        let result = await controller.registerSSHProject(request)

        guard case .success(let projectID) = result else {
            return XCTFail("Expected the probed SSH project to register, got \(result)")
        }
        XCTAssertEqual(controller.model.selectedProject?.id, projectID)
        XCTAssertEqual(controller.model.selectedProject?.name, "Production")
        XCTAssertEqual(controller.model.selectedProject?.connection.host, "production")
        XCTAssertEqual(controller.model.selectedProject?.connection.path, "/srv/resolved-project")
        XCTAssertEqual(controller.surface.projects.selectedProjectID, projectID)
        XCTAssertEqual(controller.surface.terminal.cwdLabel, "ssh://production/srv/resolved-project")
    }

    func testDesktopSettingsSaveAppliesCodeReviewPreferences() throws {
        let controller = try makeController(workspaceRoot: try makeTempDirectory())

        controller.saveSettings(WorkspaceSettingsUpdate(
            apiBaseURL: controller.surface.settings.apiBaseURL,
            reviewModel: "/prometheus",
            reviewDelivery: .detached
        ))

        XCTAssertEqual(controller.surface.settings.reviewModel, TrustedRouterDefaults.prometheusModel)
        XCTAssertEqual(controller.surface.settings.reviewDelivery, .detached)
    }

    func testDesktopWindowSmokeSurfaceReportSummarizesWorkspaceChrome() throws {
        let controller = try makeController(workspaceRoot: try makeTempDirectory())
        let report = try QuillCodeDesktopWindowSmokeSurfaceReport(surface: controller.surface)

        XCTAssertEqual(report.appName, "QuillCode")
        XCTAssertFalse(report.primaryTitle.isEmpty)
        XCTAssertFalse(report.modelLabel.isEmpty)
        XCTAssertFalse(report.modeLabel.isEmpty)
        XCTAssertFalse(report.agentStatus.isEmpty)
        XCTAssertFalse(report.composerPlaceholder.isEmpty)
        XCTAssertFalse(report.composerCanSend)
        XCTAssertEqual(report.sidebarTitle, "Chats")
        XCTAssertGreaterThanOrEqual(
            report.commandIDs.count,
            QuillCodeDesktopWindowSmokeSurfaceReport.requiredCommandIDs.count
        )

        for commandID in QuillCodeDesktopWindowSmokeSurfaceReport.requiredCommandIDs {
            XCTAssertTrue(report.commandIDs.contains(commandID), commandID)
        }
        for actionID in QuillCodeDesktopWindowSmokeSurfaceReport.requiredStarterActionIDs {
            XCTAssertTrue(report.starterActionIDs.contains(actionID), actionID)
        }

        let dictionary = report.dictionary
        XCTAssertEqual(dictionary["appName"] as? String, "QuillCode")
        XCTAssertEqual(dictionary["composerCanSend"] as? Bool, false)
        XCTAssertEqual(dictionary["sidebarTitle"] as? String, "Chats")
    }

    func testDesktopComposerSendPublishesOptimisticTranscriptBeforeAgentReturns() async throws {
        let workspaceRoot = try makeTempDirectory()
        let model = QuillCodeWorkspaceModel(runner: AgentRunner(llm: DesktopSlowLLMClient()))
        let coordinator = QuillCodeDesktopComposerCoordinator()
        let tasks = QuillCodeDesktopTaskCoordinator()
        let recorder = DesktopRefreshRecorder()
        var draft = "run a slow task"

        coordinator.send(
            draft: &draft,
            model: model,
            fallbackWorkspaceRoot: workspaceRoot,
            tasks: tasks,
            refresh: {
                recorder.record(model.surface())
            }
        )

        try await waitUntil(timeoutSeconds: 1) {
            recorder.surface?.transcript.timelineItems.first?.message?.text == "run a slow task"
        }
        let surface = try XCTUnwrap(recorder.surface)
        XCTAssertEqual(draft, "")
        XCTAssertTrue(surface.composer.isSending)
        XCTAssertEqual(surface.transcript.messages.map(\.text), ["run a slow task"])
        XCTAssertEqual(surface.transcript.timelineItems.first?.message?.text, "run a slow task")
        XCTAssertEqual(surface.transcript.thinking?.title, "Thinking")
        XCTAssertEqual(surface.transcript.thinking?.subtitle, "Preparing the next step")
        let threadID = try XCTUnwrap(model.selectedThread?.id)
        XCTAssertTrue(tasks.isRunning(.send(threadID)))

        tasks.cancel(.send(threadID))
        try await waitUntil(timeoutSeconds: 1) {
            !model.composer.isSending
        }
    }


    func testDesktopControllerAppliesVisibleBrowserSessionUpdates() async throws {
        let presenter = NoopDesktopBrowserSessionPresenter()
        let controller = try makeController(
            workspaceRoot: try makeTempDirectory(),
            browserSessionPresenter: presenter
        )
        let tabID = controller.surface.browser.activeTabID

        presenter.onSessionUpdate?(BrowserSessionUpdate(
            tabs: [
                BrowserSessionTabUpdate(
                    id: tabID,
                    title: "Signed-in dashboard",
                    url: try XCTUnwrap(URL(string: "https://example.com/dashboard")),
                    isActive: true,
                    liveDOMSnapshot: BrowserLiveDOMSnapshot(
                        finalURL: try XCTUnwrap(URL(string: "https://example.com/dashboard")),
                        title: "Rendered Dashboard",
                        visibleText: "Signed in dashboard ready",
                        outline: ["H1: Rendered Dashboard"],
                        viewportDescription: "1120x760 @2x"
                    )
                )
            ],
            activeTabID: tabID
        ))

        XCTAssertEqual(controller.surface.browser.currentURL, "https://example.com/dashboard")
        XCTAssertEqual(controller.surface.browser.title, "Rendered Dashboard")
        XCTAssertEqual(controller.surface.browser.statusLabel, "Synced from browser session")
        XCTAssertEqual(controller.surface.browser.snapshot?.inspectionDepth, .liveDOMSnapshot)
        XCTAssertEqual(controller.surface.browser.snapshot?.textSnippet, "Signed in dashboard ready")
        XCTAssertEqual(controller.browserAddressDraft, "https://example.com/dashboard")
    }

    func testDesktopControllerSlashSessionOpensVisibleBrowserSession() throws {
        let presenter = NoopDesktopBrowserSessionPresenter()
        let controller = try makeController(
            workspaceRoot: try makeTempDirectory(),
            browserSessionPresenter: presenter
        )

        controller.draft = "/session localhost:5173/dashboard"
        controller.send()

        XCTAssertEqual(controller.draft, "")
        XCTAssertEqual(controller.surface.browser.currentURL, "http://localhost:5173/dashboard")
        XCTAssertEqual(controller.surface.transcript.messages.last?.text, "Opened browser session for localhost at http://localhost:5173/dashboard.")
        XCTAssertEqual(presenter.presentedSnapshots.count, 1)
        XCTAssertEqual(presenter.presentedSnapshots.last?.tabs.first?.url.absoluteString, "http://localhost:5173/dashboard")
    }

    func testDesktopControllerSlashSessionWithoutTargetUsesCurrentBrowserTab() throws {
        let presenter = NoopDesktopBrowserSessionPresenter()
        let controller = try makeController(
            workspaceRoot: try makeTempDirectory(),
            browserSessionPresenter: presenter
        )
        controller.browserAddressDraft = "localhost:5173"
        controller.openBrowserPreview()

        controller.draft = "/browser-session"
        controller.send()

        XCTAssertEqual(controller.surface.transcript.messages.last?.text, "Opened browser session for localhost at http://localhost:5173.")
        XCTAssertEqual(presenter.presentedSnapshots.count, 1)
        XCTAssertEqual(presenter.presentedSnapshots.last?.tabs.first?.url.absoluteString, "http://localhost:5173")
    }

    func testDesktopControllerReloadCommandReloadsVisibleBrowserSession() throws {
        let presenter = NoopDesktopBrowserSessionPresenter()
        let controller = try makeController(
            workspaceRoot: try makeTempDirectory(),
            browserSessionPresenter: presenter
        )
        controller.browserAddressDraft = "localhost:5173"
        controller.openBrowserSession()

        controller.runWorkspaceCommand("browser-reload")

        XCTAssertEqual(controller.surface.browser.statusLabel, "Reloaded")
        XCTAssertEqual(presenter.syncedSnapshots.last?.tabs.first?.url.absoluteString, "http://localhost:5173")
        XCTAssertEqual(presenter.reloadedSessionCount, 1)
    }

    func testDesktopControllerBackForwardCommandsDriveVisibleBrowserSessionHistory() throws {
        let presenter = NoopDesktopBrowserSessionPresenter()
        let controller = try makeController(
            workspaceRoot: try makeTempDirectory(),
            browserSessionPresenter: presenter
        )
        controller.browserAddressDraft = "localhost:5173"
        controller.openBrowserPreview()
        controller.browserAddressDraft = "localhost:5174"
        controller.openBrowserSession()
        let syncCountBeforeBack = presenter.syncedSnapshots.count

        controller.runWorkspaceCommand("browser-back")

        XCTAssertEqual(controller.surface.browser.currentURL, "http://localhost:5173")
        XCTAssertEqual(presenter.backFallbackSnapshots.last?.tabs.first?.url.absoluteString, "http://localhost:5173")
        XCTAssertEqual(presenter.syncedSnapshots.count, syncCountBeforeBack)
        let syncCountBeforeForward = presenter.syncedSnapshots.count

        controller.runWorkspaceCommand("browser-forward")

        XCTAssertEqual(controller.surface.browser.currentURL, "http://localhost:5174")
        XCTAssertEqual(presenter.forwardFallbackSnapshots.last?.tabs.first?.url.absoluteString, "http://localhost:5174")
        XCTAssertEqual(presenter.syncedSnapshots.count, syncCountBeforeForward)
    }

    func testDesktopBrowserCoordinatorEvaluatesJavaScriptInVisibleSession() async throws {
        let presenter = NoopDesktopBrowserSessionPresenter()
        let controller = try makeController(
            workspaceRoot: try makeTempDirectory(),
            browserSessionPresenter: presenter
        )
        controller.browserAddressDraft = "localhost:5173"
        controller.openBrowserSession()

        let result = try await controller.browserCoordinator.evaluateJavaScriptInOpenSession("document.title")

        XCTAssertEqual(presenter.evaluatedJavaScriptSources, ["document.title"])
        XCTAssertEqual(result.title, "Visible Browser")
        XCTAssertEqual(result.url.absoluteString, "http://localhost:5173")
        XCTAssertEqual(result.valueDescription, "Visible Browser")
    }

    func testDesktopBrowserCoordinatorRejectsEmptyVisibleSessionJavaScript() async throws {
        let presenter = NoopDesktopBrowserSessionPresenter()
        let controller = try makeController(
            workspaceRoot: try makeTempDirectory(),
            browserSessionPresenter: presenter
        )
        controller.browserAddressDraft = "localhost:5173"
        controller.openBrowserSession()

        do {
            _ = try await controller.browserCoordinator.evaluateJavaScriptInOpenSession("   ")
            XCTFail("Expected empty JavaScript source to fail.")
        } catch let error as DesktopBrowserSessionScriptError {
            XCTAssertEqual(error, .emptySource)
        }
    }

    func testDesktopBrowserCoordinatorCapturesLiveDOMSnapshotInVisibleSession() async throws {
        let presenter = NoopDesktopBrowserSessionPresenter()
        let controller = try makeController(
            workspaceRoot: try makeTempDirectory(),
            browserSessionPresenter: presenter
        )
        controller.browserAddressDraft = "localhost:5173/dashboard"
        controller.openBrowserSession()

        let snapshot = try await controller.browserCoordinator.captureLiveDOMSnapshotInOpenSession()

        XCTAssertEqual(presenter.capturedLiveDOMSnapshotCount, 1)
        XCTAssertEqual(snapshot.finalURL.absoluteString, "http://localhost:5173/dashboard")
        XCTAssertEqual(snapshot.title, "Visible Dashboard")
        XCTAssertEqual(snapshot.visibleText, "Live dashboard text")
        XCTAssertEqual(snapshot.outline, ["H1: Visible Dashboard", "Button: Save"])
        XCTAssertEqual(snapshot.viewportDescription, "1120x760 @2x")
    }

    func testDesktopBrowserCoordinatorClicksInVisibleSession() async throws {
        let presenter = NoopDesktopBrowserSessionPresenter()
        let controller = try makeController(
            workspaceRoot: try makeTempDirectory(),
            browserSessionPresenter: presenter
        )
        controller.browserAddressDraft = "localhost:5173/dashboard"
        controller.openBrowserSession()

        let result = try await controller.browserCoordinator.clickInOpenSession(selector: "button.save")

        XCTAssertEqual(presenter.clickedSelectors, ["button.save"])
        XCTAssertEqual(result, DesktopBrowserSessionActionResult(ok: true, summary: "Clicked button.save", error: nil))
    }

    func testDesktopBrowserCoordinatorTypesInVisibleSession() async throws {
        let presenter = NoopDesktopBrowserSessionPresenter()
        let controller = try makeController(
            workspaceRoot: try makeTempDirectory(),
            browserSessionPresenter: presenter
        )
        controller.browserAddressDraft = "localhost:5173/dashboard"
        controller.openBrowserSession()

        let result = try await controller.browserCoordinator.typeInOpenSession(
            selector: "input[name='query']",
            text: "minimax",
            submit: true
        )

        XCTAssertEqual(presenter.typedRequests, [
            NoopDesktopBrowserSessionPresenter.TypedRequest(
                selector: "input[name='query']",
                text: "minimax",
                submit: true
            )
        ])
        XCTAssertEqual(result, DesktopBrowserSessionActionResult(ok: true, summary: "Typed into input[name='query']", error: nil))
    }

    func testDesktopAgentBrowserClickUsesVisibleSessionActionTool() async throws {
        let presenter = NoopDesktopBrowserSessionPresenter()
        let controller = try makeController(
            workspaceRoot: try makeTempDirectory(),
            browserSessionPresenter: presenter
        )
        controller.browserAddressDraft = "localhost:5173/dashboard"
        controller.openBrowserSession()
        let override = try XCTUnwrap(controller.model.visibleBrowserToolOverride)

        let result = await override(
            ToolCall(
                name: ToolDefinition.browserClick.name,
                argumentsJSON: ToolArguments.json(["selector": "button.save"])
            ),
            try makeTempDirectory()
        )

        XCTAssertEqual(result?.ok, true)
        XCTAssertEqual(presenter.clickedSelectors, ["button.save"])
        XCTAssertTrue(result?.stdout.contains(#""action" : "click""#) == true)
        XCTAssertTrue(result?.stdout.contains(#""selector" : "button.save""#) == true)
    }

    func testDesktopAgentBrowserTypeUsesVisibleSessionActionTool() async throws {
        let presenter = NoopDesktopBrowserSessionPresenter()
        let controller = try makeController(
            workspaceRoot: try makeTempDirectory(),
            browserSessionPresenter: presenter
        )
        controller.browserAddressDraft = "localhost:5173/dashboard"
        controller.openBrowserSession()
        let override = try XCTUnwrap(controller.model.visibleBrowserToolOverride)

        let result = await override(
            ToolCall(
                name: ToolDefinition.browserType.name,
                argumentsJSON: ToolArguments.json([
                    "selector": "input[name='query']",
                    "text": "minimax",
                    "submit": true
                ])
            ),
            try makeTempDirectory()
        )

        XCTAssertEqual(result?.ok, true)
        XCTAssertEqual(presenter.typedRequests, [
            NoopDesktopBrowserSessionPresenter.TypedRequest(
                selector: "input[name='query']",
                text: "minimax",
                submit: true
            )
        ])
        XCTAssertTrue(result?.stdout.contains(#""action" : "type""#) == true)
        XCTAssertTrue(result?.stdout.contains(#""submitted" : true"#) == true)
    }

    func testDesktopAgentBrowserScriptUsesVisibleSessionActionTool() async throws {
        let presenter = NoopDesktopBrowserSessionPresenter()
        let controller = try makeController(
            workspaceRoot: try makeTempDirectory(),
            browserSessionPresenter: presenter
        )
        controller.browserAddressDraft = "localhost:5173/dashboard"
        controller.openBrowserSession()
        let override = try XCTUnwrap(controller.model.visibleBrowserToolOverride)

        let result = await override(
            ToolCall(
                name: ToolDefinition.browserScript.name,
                argumentsJSON: ToolArguments.json(["source": "document.title"])
            ),
            try makeTempDirectory()
        )

        XCTAssertEqual(result?.ok, true)
        XCTAssertEqual(presenter.evaluatedJavaScriptSources, ["document.title"])
        XCTAssertTrue(result?.stdout.contains(#""title" : "Visible Browser""#) == true)
        XCTAssertTrue(result?.stdout.contains(#""value" : "Visible Browser""#) == true)
    }

    func testDesktopAgentBrowserClickReportsMissingVisibleSession() async throws {
        let presenter = NoopDesktopBrowserSessionPresenter()
        let controller = try makeController(
            workspaceRoot: try makeTempDirectory(),
            browserSessionPresenter: presenter
        )
        let override = try XCTUnwrap(controller.model.visibleBrowserToolOverride)

        let result = await override(
            ToolCall(
                name: ToolDefinition.browserClick.name,
                argumentsJSON: ToolArguments.json(["selector": "button.save"])
            ),
            try makeTempDirectory()
        )

        XCTAssertEqual(result?.ok, false)
        XCTAssertTrue(result?.error?.contains("No visible browser session is open") == true)
    }

    func testDesktopAgentBrowserScriptReportsMissingVisibleSession() async throws {
        let presenter = NoopDesktopBrowserSessionPresenter()
        let controller = try makeController(
            workspaceRoot: try makeTempDirectory(),
            browserSessionPresenter: presenter
        )
        let override = try XCTUnwrap(controller.model.visibleBrowserToolOverride)

        let result = await override(
            ToolCall(
                name: ToolDefinition.browserScript.name,
                argumentsJSON: ToolArguments.json(["source": "document.title"])
            ),
            try makeTempDirectory()
        )

        XCTAssertEqual(result?.ok, false)
        XCTAssertTrue(result?.error?.contains("No visible browser session is open") == true)
    }

    func testDesktopAgentBrowserScriptRejectsEmptySource() async throws {
        let presenter = NoopDesktopBrowserSessionPresenter()
        let controller = try makeController(
            workspaceRoot: try makeTempDirectory(),
            browserSessionPresenter: presenter
        )
        controller.browserAddressDraft = "localhost:5173/dashboard"
        controller.openBrowserSession()
        let override = try XCTUnwrap(controller.model.visibleBrowserToolOverride)

        let result = await override(
            ToolCall(
                name: ToolDefinition.browserScript.name,
                argumentsJSON: ToolArguments.json(["source": "   "])
            ),
            try makeTempDirectory()
        )

        XCTAssertEqual(result?.ok, false)
        XCTAssertTrue(result?.error?.contains("No browser script source was specified") == true)
    }

    func testDesktopAgentBrowserInspectPrefersVisibleSessionLiveDOM() async throws {
        let presenter = NoopDesktopBrowserSessionPresenter()
        let controller = try makeController(
            workspaceRoot: try makeTempDirectory(),
            browserSessionPresenter: presenter
        )
        controller.browserAddressDraft = "localhost:5173/dashboard"
        controller.openBrowserSession()
        let previousTimelineCount = controller.surface.transcript.timelineItems.count

        controller.draft = "inspect browser page"
        controller.send()

        try await waitForDesktopRun(
            controller,
            previousTimelineCount: previousTimelineCount,
            expectedAnswer: "Live dashboard text",
            expectedTimelineDelta: 3
        )
        XCTAssertEqual(presenter.capturedLiveDOMSnapshotCount, 1)
        XCTAssertTrue(controller.surface.transcript.messages.last?.text.contains("Visible Dashboard") == true)
    }

    func testDesktopControllerSendPathCoversRealWorldActionPromptFamily() async throws {
        let workspaceRoot = try makeTempDirectory()
        let downloadSource = workspaceRoot.appendingPathComponent("source.html")
        try "<!doctype html><title>QuillCode desktop smoke</title>\n"
            .write(to: downloadSource, atomically: true, encoding: .utf8)

        let cases = [
            DesktopRealWorldSmokeCase(
                prompt: "whoami?",
                toolName: ToolDefinition.shellRun.name,
                inputContains: ["\"cmd\":\"whoami\""],
                answerContains: "You are `",
                sideEffect: nil
            ),
            DesktopRealWorldSmokeCase(
                prompt: "How much hd?",
                toolName: ToolDefinition.shellRun.name,
                inputContains: ["df -h / /Quill"],
                answerContains: "Disk usage:",
                sideEffect: nil
            ),
            DesktopRealWorldSmokeCase(
                prompt: "Do you have openclaw?",
                toolName: ToolDefinition.shellRun.name,
                inputContains: ["command -v openclaw"],
                answerContains: "openclaw is",
                sideEffect: nil
            ),
            DesktopRealWorldSmokeCase(
                prompt: "Can you write a file that says \"hello world\"",
                toolName: ToolDefinition.fileWrite.name,
                inputContains: ["\"path\":\"hello.txt\"", "hello world"],
                answerContains: "Wrote `hello.txt`.",
                sideEffect: .fileContains(path: "hello.txt", text: "hello world")
            ),
            DesktopRealWorldSmokeCase(
                prompt: "Download \(downloadSource.absoluteString) into `downloads/example.html` in this workspace.",
                toolName: ToolDefinition.shellRun.name,
                inputContains: [
                    "mkdir -p 'downloads'",
                    "--output 'downloads/example.html'",
                    downloadSource.absoluteString
                ],
                answerContains: "Downloaded to `downloads/example.html`.",
                sideEffect: .fileContains(path: "downloads/example.html", text: "QuillCode desktop smoke")
            )
        ]

        for testCase in cases {
            let controller = try makeController(workspaceRoot: workspaceRoot)
            controller.draft = testCase.prompt
            let previousTimelineCount = controller.surface.transcript.timelineItems.count
            controller.send()

            try await waitForDesktopRun(
                controller,
                previousTimelineCount: previousTimelineCount,
                expectedAnswer: testCase.answerContains
            )

            let surface = controller.surface
            XCTAssertFalse(surface.composer.isSending, testCase.prompt)
            XCTAssertNil(surface.lastError, testCase.prompt)

            let timeline = surface.transcript.timelineItems
            let latestKinds = Array(timeline.suffix(3).map(\.kind))
            XCTAssertEqual(
                latestKinds,
                [
                    TranscriptTimelineItemKind.message,
                    TranscriptTimelineItemKind.toolCard,
                    TranscriptTimelineItemKind.message
                ],
                testCase.prompt
            )

            let latestMessages = Array(surface.transcript.messages.suffix(2))
            XCTAssertEqual(latestMessages.first?.text, testCase.prompt)
            let answer = try XCTUnwrap(latestMessages.last?.text, testCase.prompt)
            XCTAssertTrue(answer.contains(testCase.answerContains), "\(testCase.prompt): \(answer)")
            XCTAssertFalse(
                answer.range(
                    of: #"I'?ll (run|check|do|download|create|write)"#,
                    options: String.CompareOptions.regularExpression
                ) != nil,
                testCase.prompt
            )
            XCTAssertFalse(answer.localizedCaseInsensitiveContains("No shell command was specified"), testCase.prompt)

            let card = try XCTUnwrap(surface.transcript.toolCards.last, testCase.prompt)
            XCTAssertEqual(card.title, testCase.toolName, testCase.prompt)
            XCTAssertEqual(card.status, .done, testCase.prompt)
            XCTAssertNotEqual(card.inputJSON, "{}", testCase.prompt)
            let normalizedInputJSON = normalizeToolInputJSON(card.inputJSON)
            for expectedInput in testCase.inputContains {
                let normalizedExpectedInput = expectedInput.replacingOccurrences(of: " ", with: "")
                XCTAssertTrue(
                    normalizedInputJSON.contains(normalizedExpectedInput),
                    "\(testCase.prompt): \(expectedInput)"
                )
            }

            try assertSideEffect(testCase.sideEffect, workspaceRoot: workspaceRoot, label: testCase.prompt)
        }
    }

    func testDesktopControllerRespectsOnlyNegatedActionPromptsWithoutSideEffects() async throws {
        let workspaceRoot = try makeTempDirectory()
        let controller = try makeController(workspaceRoot: workspaceRoot)
        let cases = [
            DesktopNegativeActionSmokeCase(
                prompt: "Do not run whoami.",
                forbiddenOutput: "You are `",
                absentPath: nil
            ),
            DesktopNegativeActionSmokeCase(
                prompt: "Do not write `forbidden.txt` with content `nope`.",
                forbiddenOutput: "Wrote `forbidden.txt`.",
                absentPath: "forbidden.txt"
            ),
            DesktopNegativeActionSmokeCase(
                prompt: "Don't download https://example.com into `downloads/forbidden.html`.",
                forbiddenOutput: "Downloaded to `downloads/forbidden.html`.",
                absentPath: "downloads/forbidden.html"
            )
        ]

        for testCase in cases {
            let previousTimelineCount = controller.surface.transcript.timelineItems.count
            let previousToolCount = controller.surface.transcript.toolCards.count
            controller.draft = testCase.prompt
            controller.send()

            try await waitForDesktopRun(
                controller,
                previousTimelineCount: previousTimelineCount,
                expectedAnswer: "Okay, I won't take that action.",
                expectedTimelineDelta: 2
            )

            let surface = controller.surface
            XCTAssertFalse(surface.composer.isSending, testCase.prompt)
            XCTAssertNil(surface.lastError, testCase.prompt)
            XCTAssertEqual(surface.transcript.toolCards.count, previousToolCount, testCase.prompt)
            XCTAssertFalse(surface.transcript.messages.last?.text.contains(testCase.forbiddenOutput) == true, testCase.prompt)
            XCTAssertFalse(
                surface.transcript.messages.contains { $0.text.localizedCaseInsensitiveContains("No shell command was specified") },
                testCase.prompt
            )
            if let absentPath = testCase.absentPath {
                XCTAssertFalse(
                    FileManager.default.fileExists(atPath: workspaceRoot.appendingPathComponent(absentPath).path),
                    testCase.prompt
                )
            }
        }
    }

    func testDesktopControllerReadsBackCreatedWorkspaceFileInFollowupTurn() async throws {
        let workspaceRoot = try makeTempDirectory()
        let controller = try makeController(workspaceRoot: workspaceRoot)

        controller.draft = #"Can you write a file that says "hello world""#
        let writeTimelineCount = controller.surface.transcript.timelineItems.count
        controller.send()

        try await waitForDesktopRun(
            controller,
            previousTimelineCount: writeTimelineCount,
            expectedAnswer: "Wrote `hello.txt`."
        )

        controller.draft = "Read `hello.txt` and tell me its exact content."
        let readTimelineCount = controller.surface.transcript.timelineItems.count
        controller.send()

        try await waitForDesktopRun(
            controller,
            previousTimelineCount: readTimelineCount,
            expectedAnswer: "hello world"
        )

        let messages = controller.surface.transcript.messages
        XCTAssertEqual(Array(messages.suffix(4).map(\.role)), [.user, .assistant, .user, .assistant])
        XCTAssertTrue(messages.last?.text.contains("Contents of `hello.txt`:") == true)
        XCTAssertTrue(messages.last?.text.contains("hello world") == true)

        let toolCards = controller.surface.transcript.toolCards
        XCTAssertEqual(Array(toolCards.map(\.title).suffix(2)), [
            ToolDefinition.fileWrite.name,
            ToolDefinition.fileRead.name
        ])
        XCTAssertTrue(toolCards.suffix(2).allSatisfy { $0.status == .done })
    }

    func testControllerSuspendAndResumeRefreshTheRenderedSurface() async throws {
        let controller = try makeController(workspaceRoot: try makeTempDirectory())
        controller.terminalDraft = "read x; printf got:$x"
        controller.runTerminalCommand()

        // Drive suspend through the controller until it takes (the async run must reach the live PTY
        // first). The rendered surface — not just the underlying model — must then reflect it, or the
        // native pane shows a dead Suspend button that never becomes Resume. The `read` blocks with no
        // output, so no event-driven refresh fires; only the controller calling refresh() after
        // suspend can update the surface, so this would fail without that call.
        var suspendedInSurface = false
        for _ in 0..<300 {
            controller.suspendTerminal()
            if controller.surface.terminal.isSuspended { suspendedInSurface = true; break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertTrue(suspendedInSurface, "Controller.suspendTerminal must refresh the surface so the pane can render Resume.")
        XCTAssertTrue(controller.surface.terminal.isRunning)
        XCTAssertTrue(controller.surface.terminal.canResume)
        XCTAssertFalse(controller.surface.terminal.canSuspend)

        controller.resumeTerminal()
        XCTAssertFalse(controller.surface.terminal.isSuspended, "Controller.resumeTerminal must refresh the surface back to running.")
        XCTAssertTrue(controller.surface.terminal.canSuspend)

        // Finish the command so the test does not leak a running PTY (Run sends input while running).
        controller.terminalDraft = "hello\n"
        controller.runTerminalCommand()
        for _ in 0..<300 {
            if !controller.surface.terminal.isRunning { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertFalse(controller.surface.terminal.isRunning)
        XCTAssertFalse(controller.surface.terminal.isSuspended)
    }

    private func makeController(
        workspaceRoot: URL,
        browserSessionPresenter: any DesktopBrowserSessionPresenting = NoopDesktopBrowserSessionPresenter(),
        sshRemoteProjectProbe: SSHRemoteProjectProbe = SSHRemoteProjectProbe()
    ) throws -> QuillCodeDesktopController {
        let stateRoot = try makeTempDirectory().appendingPathComponent("state", isDirectory: true)
        let paths = QuillCodePaths(home: stateRoot)
        let runtimeFactory = QuillCodeRuntimeFactory(
            paths: paths,
            environment: ["QUILLCODE_USE_MOCK_LLM": "1"]
        )
        let bootstrap = QuillCodeWorkspaceBootstrap(paths: paths, runtimeFactory: runtimeFactory)
        return QuillCodeDesktopController(
            bootstrap: bootstrap,
            browserPageFetcher: URLSessionBrowserPageFetcher(),
            browserLiveDOMCapturer: nil,
            browserSessionPresenter: browserSessionPresenter,
            automationNotifier: NoopAutomationNotifier(),
            sshRemoteProjectProbe: sshRemoteProjectProbe,
            workspaceRoot: workspaceRoot
        )
    }

    private func waitForDesktopRun(
        _ controller: QuillCodeDesktopController,
        previousTimelineCount: Int,
        expectedAnswer: String,
        expectedTimelineDelta: Int = 3,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        for _ in 0..<300 {
            let timelineCount = controller.surface.transcript.timelineItems.count
            let latestAnswer = controller.surface.transcript.messages.last?.text ?? ""
            if !controller.surface.composer.isSending,
               timelineCount >= previousTimelineCount + expectedTimelineDelta,
               latestAnswer.contains(expectedAnswer) {
                return
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Desktop send did not complete with expected answer: \(expectedAnswer)", file: file, line: line)
    }

    private func waitUntil(
        timeoutSeconds: TimeInterval,
        condition: @MainActor @escaping () -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while !condition() {
            if Date() > deadline {
                XCTFail("Timed out waiting for desktop condition", file: file, line: line)
                return
            }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
    }

    private func assertSideEffect(
        _ sideEffect: DesktopRealWorldSmokeSideEffect?,
        workspaceRoot: URL,
        label: String
    ) throws {
        switch sideEffect {
        case .fileContains(let path, let text):
            let url = workspaceRoot.appendingPathComponent(path)
            let contents = try String(contentsOf: url, encoding: .utf8)
            XCTAssertTrue(contents.contains(text), "\(label): \(url.path)")
        case .none:
            break
        }
    }

    private func normalizeToolInputJSON(_ inputJSON: String?) -> String {
        (inputJSON ?? "")
            .replacingOccurrences(of: "\\/", with: "/")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: " ", with: "")
    }

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuillCodeDesktopTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }

    func testDesktopRefreshPreservesComposerFocusTokenAndHistory() {
        let thread = ChatThread(messages: [
            ChatMessage(role: .user, content: "first"),
            ChatMessage(role: .assistant, content: "ok"),
            ChatMessage(role: .user, content: "second")
        ])
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            threads: [thread],
            selectedThreadID: thread.id
        ))
        model.focusComposer()
        let expectedToken = model.composer.focusToken
        let expectedHistory = model.surface().composer.sentMessageHistory
        XCTAssertGreaterThan(expectedToken, 0)
        XCTAssertFalse(expectedHistory.isEmpty)

        // Drive the REAL desktop refresh path (not model.surface() directly) — the path the live
        // app renders from. Its composer rebuild must preserve the focus token (or Cmd+L is dead
        // on native — the view's .onChange never fires) AND the sent-message history (Up/Down
        // recall) — the bare rebuild used to reset both to their defaults.
        var surface = model.surface()
        var draft = ""
        var terminalDraft = ""
        var browserAddressDraft = ""
        QuillCodeDesktopModelStateCoordinator().refreshState(
            from: model,
            surface: &surface,
            draft: &draft,
            terminalDraft: &terminalDraft,
            browserAddressDraft: &browserAddressDraft
        )

        XCTAssertEqual(surface.composer.focusToken, expectedToken)
        XCTAssertEqual(surface.composer.sentMessageHistory, expectedHistory)
    }

    /// Structural guard against the whole "native refresh drops a composer field" bug class the
    /// focus-composer review surfaced: `refreshState` is the ONLY place that rebuilds a sub-surface
    /// (the composer); everything else is copied verbatim. So with the local draft matching the
    /// model's, the rebuilt composer must EQUAL `model.surface().composer` exactly — any field a
    /// future rebuild forgets to carry (focusToken, sentMessageHistory, …) trips this immediately.
    /// (Compares the composer, not the whole surface, because the sidebar carries relative-time
    /// strings that aren't stable across two `surface()` calls.)
    func testDesktopRefreshComposerEqualsModelSurfaceWhenDraftUnchanged() {
        let model = richlyPopulatedModel()

        var surface = model.surface()
        var draft = model.composer.draft
        var terminalDraft = model.terminal.draft
        var browserAddressDraft = model.browser.addressDraft
        QuillCodeDesktopModelStateCoordinator().refreshState(
            from: model,
            surface: &surface,
            draft: &draft,
            terminalDraft: &terminalDraft,
            browserAddressDraft: &browserAddressDraft
        )

        XCTAssertEqual(surface.composer, model.surface().composer)
    }

    /// While a send is in flight the live local draft is kept (the model isn't the source of truth
    /// mid-send), so the composer rebuilds from it — but the non-draft fields the bare rebuild used
    /// to drop (focusToken, sentMessageHistory) must still survive.
    func testDesktopRefreshKeepsLocalDraftAndNonDraftFieldsWhileSending() {
        let model = richlyPopulatedModel()
        let modelComposer = model.surface().composer

        var surface = model.surface()
        var draft = "a half-typed message"
        var terminalDraft = model.terminal.draft
        var browserAddressDraft = model.browser.addressDraft
        // isComposerTaskRunning: true ⇒ the local draft is preserved rather than synced to the model.
        QuillCodeDesktopModelStateCoordinator().refreshState(
            from: model,
            surface: &surface,
            draft: &draft,
            terminalDraft: &terminalDraft,
            browserAddressDraft: &browserAddressDraft,
            isComposerTaskRunning: true
        )

        XCTAssertEqual(surface.composer.draft, "a half-typed message")
        XCTAssertTrue(surface.composer.isSending)
        XCTAssertEqual(surface.composer.focusToken, modelComposer.focusToken)
        XCTAssertEqual(surface.composer.sentMessageHistory, modelComposer.sentMessageHistory)
        XCTAssertEqual(surface.composer.placeholder, modelComposer.placeholder)
    }

    /// The live plan-progress rail and queued follow-up chips are the unattended-driving check-in
    /// surface — both are model-derived composer fields. `refreshState` rebuilds the composer from
    /// the LOCAL draft, so it must carry them across; the bare rebuild dropped both, making the rail
    /// and follow-ups vanish on every controller-triggered refresh. (`supportsPersonality` was in the
    /// same dropped set; the structural `==` guard above catches it once a fixture exercises it.)
    func testDesktopRefreshPreservesPlanProgressAndFollowUpQueue() throws {
        let update = AgentPlanUpdate(plan: [
            AgentPlanItem(step: "Inspect", status: .completed),
            AgentPlanItem(step: "Change", status: .inProgress),
            AgentPlanItem(step: "Verify", status: .pending)
        ])
        let planResult = ToolResult(ok: true, stdout: try JSONHelpers.encodePretty(update))
        var thread = ChatThread(
            title: "Plan work",
            messages: [.init(role: .user, content: "plan the work")],
            events: [.init(
                kind: .toolCompleted,
                summary: "\(ToolDefinition.planUpdate.name) completed",
                payloadJSON: try JSONHelpers.encodePretty(planResult)
            )]
        )
        thread.followUpQueue = [FollowUpItem(text: "queued follow-up")]
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            threads: [thread],
            selectedThreadID: thread.id
        ))
        let expected = model.surface().composer
        XCTAssertNotNil(expected.planProgress, "fixture must actually populate a plan")
        XCTAssertFalse(expected.followUpQueue.isEmpty, "fixture must actually queue a follow-up")

        var surface = model.surface()
        var draft = model.composer.draft
        var terminalDraft = model.terminal.draft
        var browserAddressDraft = model.browser.addressDraft
        QuillCodeDesktopModelStateCoordinator().refreshState(
            from: model,
            surface: &surface,
            draft: &draft,
            terminalDraft: &terminalDraft,
            browserAddressDraft: &browserAddressDraft
        )

        XCTAssertEqual(surface.composer.planProgress, expected.planProgress, "the plan rail must survive refresh")
        XCTAssertEqual(surface.composer.followUpQueue, expected.followUpQueue, "queued follow-ups must survive refresh")
        XCTAssertEqual(surface.composer, expected, "no model-derived composer field may be dropped by the rebuild")
    }

    private func richlyPopulatedModel() -> QuillCodeWorkspaceModel {
        let thread = ChatThread(messages: [
            ChatMessage(role: .user, content: "first request"),
            ChatMessage(role: .assistant, content: "did it"),
            ChatMessage(role: .user, content: "second request")
        ])
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            threads: [thread],
            selectedThreadID: thread.id
        ))
        model.focusComposer()
        return model
    }
}

private struct DesktopRealWorldSmokeCase {
    var prompt: String
    var toolName: String
    var inputContains: [String]
    var answerContains: String
    var sideEffect: DesktopRealWorldSmokeSideEffect?
}

private struct DesktopNegativeActionSmokeCase {
    var prompt: String
    var forbiddenOutput: String
    var absentPath: String?
}

private enum DesktopRealWorldSmokeSideEffect {
    case fileContains(path: String, text: String)
}

@MainActor
private final class DesktopRefreshRecorder {
    private(set) var surface: WorkspaceSurface?

    func record(_ surface: WorkspaceSurface) {
        self.surface = surface
    }
}

private struct DesktopSlowLLMClient: LLMClient {
    func nextAction(thread _: ChatThread, userMessage _: String, tools _: [ToolDefinition]) async throws -> AgentAction {
        try await Task.sleep(nanoseconds: 5_000_000_000)
        return .say("late response")
    }
}


@MainActor
private final class NoopDesktopBrowserSessionPresenter: DesktopBrowserSessionPresenting {
    struct TypedRequest: Equatable {
        var selector: String
        var text: String
        var submit: Bool
    }

    var onSessionUpdate: (@MainActor (BrowserSessionUpdate) -> Void)?
    private(set) var presentedSnapshots: [BrowserSessionSyncSnapshot] = []
    private(set) var syncedSnapshots: [BrowserSessionSyncSnapshot] = []
    private(set) var backFallbackSnapshots: [BrowserSessionSyncSnapshot] = []
    private(set) var forwardFallbackSnapshots: [BrowserSessionSyncSnapshot] = []
    private(set) var evaluatedJavaScriptSources: [String] = []
    private(set) var capturedLiveDOMSnapshotCount = 0
    private(set) var clickedSelectors: [String] = []
    private(set) var typedRequests: [TypedRequest] = []
    private(set) var reloadedSessionCount = 0
    private var hasOpenSession = false

    func presentSession(_ snapshot: BrowserSessionSyncSnapshot) {
        hasOpenSession = true
        presentedSnapshots.append(snapshot)
    }

    func syncSession(_ snapshot: BrowserSessionSyncSnapshot) {
        hasOpenSession = true
        syncedSnapshots.append(snapshot)
    }

    func goBackSession(fallback snapshot: BrowserSessionSyncSnapshot) {
        backFallbackSnapshots.append(snapshot)
    }

    func goForwardSession(fallback snapshot: BrowserSessionSyncSnapshot) {
        forwardFallbackSnapshots.append(snapshot)
    }

    func evaluateJavaScriptInSelectedTab(_ source: String) async throws -> DesktopBrowserSessionScriptResult {
        guard hasOpenSession else { throw DesktopBrowserSessionScriptError.noOpenSession }
        let trimmedSource = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSource.isEmpty else { throw DesktopBrowserSessionScriptError.emptySource }
        evaluatedJavaScriptSources.append(trimmedSource)
        return DesktopBrowserSessionScriptResult(
            title: "Visible Browser",
            url: try XCTUnwrap(URL(string: "http://localhost:5173")),
            valueDescription: "Visible Browser"
        )
    }

    func captureLiveDOMSnapshotInSelectedTab() async throws -> BrowserLiveDOMSnapshot {
        guard hasOpenSession else { throw DesktopBrowserSessionScriptError.noOpenSession }
        capturedLiveDOMSnapshotCount += 1
        return BrowserLiveDOMSnapshot(
            finalURL: try XCTUnwrap(URL(string: "http://localhost:5173/dashboard")),
            title: "Visible Dashboard",
            visibleText: "Live dashboard text",
            outline: ["H1: Visible Dashboard", "Button: Save"],
            html: "<h1>Visible Dashboard</h1><button>Save</button>",
            viewportDescription: "1120x760 @2x"
        )
    }

    func clickInSelectedTab(selector: String) async throws -> DesktopBrowserSessionActionResult {
        guard hasOpenSession else { throw DesktopBrowserSessionActionError.noOpenSession }
        let trimmedSelector = selector.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSelector.isEmpty else { throw DesktopBrowserSessionActionError.emptySelector }
        clickedSelectors.append(trimmedSelector)
        return DesktopBrowserSessionActionResult(ok: true, summary: "Clicked \(trimmedSelector)", error: nil)
    }

    func typeInSelectedTab(selector: String, text: String, submit: Bool) async throws -> DesktopBrowserSessionActionResult {
        guard hasOpenSession else { throw DesktopBrowserSessionActionError.noOpenSession }
        let trimmedSelector = selector.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSelector.isEmpty else { throw DesktopBrowserSessionActionError.emptySelector }
        guard !text.isEmpty else { throw DesktopBrowserSessionActionError.emptyText }
        typedRequests.append(TypedRequest(selector: trimmedSelector, text: text, submit: submit))
        return DesktopBrowserSessionActionResult(ok: true, summary: "Typed into \(trimmedSelector)", error: nil)
    }

    func reloadSession() {
        reloadedSessionCount += 1
    }
}

private struct NoopAutomationNotifier: QuillCodeAutomationNotifying {
    func deliver(_ report: AutomationRunReport) {}
}
