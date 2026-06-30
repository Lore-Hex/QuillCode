import XCTest
import QuillCodeAgent
import QuillCodeApp
import QuillCodeCore
import QuillCodePersistence
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

    func testDesktopWindowSmokeReportIncludesNativeHitTargets() throws {
        let model = QuillCodeWorkspaceModel()
        let surface = model.surface()
        let nativeHitTargets = try QuillCodeDesktopNativeHitTargetSmoke.validatedReport(for: surface)
        let surfaceReport = try QuillCodeDesktopWindowSmokeSurfaceReport(surface: surface)
        let accessibilityFrameSamples = QuillCodeDesktopAccessibilityFrameSampleReport(
            liveAccessibilitySampling: "frame-sampled",
            minimumHitTarget: 44,
            minimumTargetClearance: 6,
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
                    requiredPeerClearance: 6,
                    allowsNestedInteractiveChildren: false,
                    requiresUnblockedInterior: true,
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
            surface: surfaceReport
        )

        let json = String(data: try report.prettyJSON(), encoding: .utf8) ?? ""
        XCTAssertTrue(json.contains(#""nativeHitTargets""#))
        XCTAssertTrue(json.contains(#""clickProbes""#))
        XCTAssertTrue(json.contains(#""quillcode-send-button""#))
        XCTAssertTrue(json.contains(#""collisionScope" : "composer:composer""#))
        XCTAssertTrue(json.contains(#""accessibilityFrameSamples""#))
        XCTAssertTrue(json.contains(#""liveAccessibilitySampling" : "frame-sampled""#))
        XCTAssertTrue(json.contains(#""hitTestAvailable" : true"#))
        XCTAssertTrue(json.contains(#""hitTestMatchesTarget" : true"#))
        XCTAssertTrue(json.contains(#""surface""#))
        XCTAssertTrue(json.contains(#""composerCanSend" : false"#))
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
                    isActive: true
                )
            ],
            activeTabID: tabID
        ))

        XCTAssertEqual(controller.surface.browser.currentURL, "https://example.com/dashboard")
        XCTAssertEqual(controller.surface.browser.title, "Signed-in dashboard")
        XCTAssertEqual(controller.surface.browser.statusLabel, "Synced from browser session")
        XCTAssertEqual(controller.browserAddressDraft, "https://example.com/dashboard")
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

    func presentSession(_ snapshot: BrowserSessionSyncSnapshot) {}
    func syncSession(_ snapshot: BrowserSessionSyncSnapshot) {}
}

private struct NoopAutomationNotifier: QuillCodeAutomationNotifying {
    func deliver(_ report: AutomationRunReport) {}
}
