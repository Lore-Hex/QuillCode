import XCTest
import QuillCodeAgent
import QuillCodeApp
import QuillCodeCore
import QuillCodePersistence
import QuillComputerUseKit
@testable import quill_code_desktop

@MainActor
final class QuillCodeDesktopControllerSmokeTests: XCTestCase {
    func testDesktopWindowSmokeRequestParsesReportAndScreenshotPaths() {
        let request = QuillCodeDesktopWindowSmokeRequest(arguments: [
            "QuillCode",
            "--native-window-smoke",
            "--window-smoke-report",
            "/tmp/quillcode-window-report.json",
            "--window-smoke-screenshot",
            "/tmp/quillcode-window.png"
        ])

        XCTAssertEqual(request?.reportPath, "/tmp/quillcode-window-report.json")
        XCTAssertEqual(request?.screenshotPath, "/tmp/quillcode-window.png")
        XCTAssertNil(QuillCodeDesktopWindowSmokeRequest(arguments: ["QuillCode"]))
    }

    func testDesktopBrowserSmokeReportDocumentsAgentInspection() {
        let report = QuillCodeDesktopBrowserSmokeReport(
            previewPath: "/tmp/browser-smoke.html",
            url: "file:///tmp/browser-smoke.html",
            title: "Browser Smoke",
            status: "Preview ready",
            sourceLabel: "Local HTML",
            inspectionDepth: "Static HTML snapshot",
            outline: ["H1: Browser Smoke"],
            textSnippet: "Native browser smoke preview text.",
            commentCount: 1,
            toolName: "host.browser.inspect",
            finalAnswer: "Inspected `Browser Smoke`. Native browser smoke preview text."
        )

        let dictionary = report.dictionary
        XCTAssertEqual(dictionary["title"] as? String, "Browser Smoke")
        XCTAssertEqual(dictionary["inspectionDepth"] as? String, "Static HTML snapshot")
        XCTAssertEqual(dictionary["commentCount"] as? Int, 1)
        XCTAssertEqual(dictionary["toolName"] as? String, "host.browser.inspect")
        XCTAssertEqual(dictionary["outline"] as? [String], ["H1: Browser Smoke"])
    }

    func testDesktopWindowSmokeReportIncludesNativeHitTargets() throws {
        let model = QuillCodeWorkspaceModel()
        let surface = model.surface()
        let nativeHitTargets = try QuillCodeDesktopNativeHitTargetSmoke.validatedReport(for: surface)
        let surfaceReport = try QuillCodeDesktopWindowSmokeSurfaceReport(surface: surface)
        let accessibilityActivation = QuillCodeDesktopAccessibilityActivationReport(
            liveAccessibilityActivation: "ax-press-sampled",
            requiredContractIDs: ["command.settings"],
            activatedContractIDs: ["command.settings"],
            skippedContractIDs: [],
            checks: [
                QuillCodeDesktopAccessibilityActivationCheck(
                    contractID: "command.settings",
                    selectorKind: "command-id",
                    selector: "settings",
                    resolvedIdentifier: "quillcode-sidebar-command-settings",
                    role: "AXButton",
                    label: "Settings",
                    activation: "AXPress",
                    expectedOutcome: "settings sheet becomes presented",
                    beforeValue: "false",
                    afterValue: "true",
                    axError: "success",
                    validationIssue: nil
                )
            ],
            validationIssues: []
        )
        let accessibilityFrameSamples = QuillCodeDesktopAccessibilityFrameSampleReport(
            liveAccessibilitySampling: "frame-sampled",
            minimumHitTarget: 40,
            minimumTargetClearance: 8,
            requiredContractIDs: ["composer.send"],
            sampledContractIDs: ["composer.send"],
            unresolvedRequiredContractIDs: [],
            skippedContractIDs: [],
            samples: [
                QuillCodeDesktopAccessibilityFrameSample(
                    contractID: "composer.send",
                    selectorKind: "test-id",
                    selector: "quillcode-send-button",
                    collisionScope: "composer:composer",
                    kind: "icon",
                    action: "press",
                    resolvedIdentifier: "quillcode-send-button",
                    role: "AXButton",
                    label: "Send message",
                    frame: CGRect(x: 100, y: 100, width: 44, height: 44),
                    requiredMinWidth: 44,
                    requiredMinHeight: 44,
                    requiredPeerClearance: 8,
                    allowsNestedInteractiveChildren: false,
                    requiresUnblockedInterior: true,
                    requiresTactileFeedback: true,
                    allowsTextSelection: false,
                    samplePoints: [[
                        "name": "center",
                        "x": 122,
                        "y": 122,
                        "hitTestAvailable": true,
                        "hitTestError": "",
                        "hitTestIdentifier": "quillcode-send-button",
                        "hitTestRole": "AXButton",
                        "hitTestLabel": "Send message",
                        "hitTestAncestorIdentifiers": [],
                        "hitTestMatchesTarget": true
                    ]]
                )
            ],
            validationIssues: []
        )
        let report = QuillCodeDesktopWindowSmokeReport(
            ok: true,
            appName: "QuillCode",
            bundleIdentifier: "co.lorehex.QuillCode",
            windowTitle: "QuillCode",
            windowFrame: CGRect(x: 0, y: 0, width: 1280, height: 928),
            contentSize: CGSize(width: 1280, height: 900),
            screenshotPath: "/tmp/quillcode-window.png",
            image: QuillCodeDesktopSmokePixelReport(
                width: 2560,
                height: 1800,
                opaquePixelRatio: 1,
                brightPixelRatio: 0.01,
                blueAccentPixelRatio: 0.01,
                distinctColorBuckets: 48
            ),
            nativeHitTargets: nativeHitTargets,
            accessibilityFrameSamples: accessibilityFrameSamples,
            accessibilityActivation: accessibilityActivation,
            surface: surfaceReport
        )

        let json = String(data: try report.prettyJSON(), encoding: .utf8) ?? ""
        XCTAssertTrue(json.contains(#""nativeHitTargets""#))
        XCTAssertTrue(json.contains(#""clickProbes""#))
        XCTAssertTrue(json.contains(#""quillcode-send-button""#))
        XCTAssertTrue(json.contains(#""collisionScope" : "composer:composer""#))
        XCTAssertTrue(json.contains(#""accessibilityFrameSamples""#))
        XCTAssertTrue(json.contains(#""liveAccessibilitySampling" : "frame-sampled""#))
        XCTAssertTrue(json.contains(#""accessibilityActivation""#))
        XCTAssertTrue(json.contains(#""liveAccessibilityActivation" : "ax-press-sampled""#))
        XCTAssertTrue(json.contains(#""expectedOutcome" : "settings sheet becomes presented""#))
        XCTAssertTrue(json.contains(#""activation" : "AXPress""#))
        XCTAssertTrue(json.contains(#""hitTestAvailable" : true"#))
        XCTAssertTrue(json.contains(#""hitTestMatchesTarget" : true"#))
        XCTAssertTrue(json.contains(#""requiresTactileFeedback" : true"#))
        XCTAssertTrue(json.contains(#""allowsTextSelection" : false"#))
        XCTAssertTrue(json.contains(#""surface""#))
        XCTAssertTrue(json.contains(#""composerCanSend" : false"#))
    }

    func testComputerUseCoordinatorRefreshesForegroundApplication() async throws {
        let application = ComputerUseApplication(
            name: "Terminal",
            bundleIdentifier: "com.apple.Terminal"
        )
        let backend = StubComputerUseBackend(foregroundApplication: application)
        let model = QuillCodeWorkspaceModel()
        let coordinator = QuillCodeDesktopComputerUseCoordinator(backend: backend)

        coordinator.install(on: model)

        try await waitUntil(timeoutSeconds: 1) {
            model.surface().settings.computerUseForegroundApplication == application
        }
    }

    func testWindowAccessibilityFrameSamplerRequiresPrimarySidebarActions() {
        XCTAssertEqual(
            QuillCodeDesktopAccessibilityFrameSampler.requiredPrimarySidebarContractIDs,
            [
                "command.add-project",
                "command.new-chat",
                "command.search",
                "command.toggle-automations",
                "command.toggle-extensions",
                "command.settings",
                "project.clear"
            ]
        )
        XCTAssertTrue(QuillCodeDesktopAccessibilityFrameSampler.requiredLiveContractIDs.isSuperset(
            of: QuillCodeDesktopAccessibilityFrameSampler.requiredPrimarySidebarContractIDs
        ))
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
        XCTAssertTrue(tasks.isRunning(.send))

        tasks.cancel(.send)
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
        browserSessionPresenter: any DesktopBrowserSessionPresenting = NoopDesktopBrowserSessionPresenter()
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
    var onSessionUpdate: (@MainActor (BrowserSessionUpdate) -> Void)?
    private(set) var presentedSnapshots: [BrowserSessionSyncSnapshot] = []
    private(set) var syncedSnapshots: [BrowserSessionSyncSnapshot] = []
    private(set) var backFallbackSnapshots: [BrowserSessionSyncSnapshot] = []
    private(set) var forwardFallbackSnapshots: [BrowserSessionSyncSnapshot] = []
    private(set) var evaluatedJavaScriptSources: [String] = []
    private(set) var reloadedSessionCount = 0

    func presentSession(_ snapshot: BrowserSessionSyncSnapshot) {
        presentedSnapshots.append(snapshot)
    }

    func syncSession(_ snapshot: BrowserSessionSyncSnapshot) {
        syncedSnapshots.append(snapshot)
    }

    func goBackSession(fallback snapshot: BrowserSessionSyncSnapshot) {
        backFallbackSnapshots.append(snapshot)
    }

    func goForwardSession(fallback snapshot: BrowserSessionSyncSnapshot) {
        forwardFallbackSnapshots.append(snapshot)
    }

    func evaluateJavaScriptInSelectedTab(_ source: String) async throws -> DesktopBrowserSessionScriptResult {
        let trimmedSource = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSource.isEmpty else { throw DesktopBrowserSessionScriptError.emptySource }
        evaluatedJavaScriptSources.append(trimmedSource)
        return DesktopBrowserSessionScriptResult(
            title: "Visible Browser",
            url: try XCTUnwrap(URL(string: "http://localhost:5173")),
            valueDescription: "Visible Browser"
        )
    }

    func reloadSession() {
        reloadedSessionCount += 1
    }
}

private struct NoopAutomationNotifier: QuillCodeAutomationNotifying {
    func deliver(_ report: AutomationRunReport) {}
}
