import AppKit
import Foundation
import SwiftUI
import QuillCodeAgent
import QuillCodeApp
import QuillCodeCore
import QuillComputerUseKit
import QuillCodePersistence

@MainActor
enum QuillCodeDesktopSmokeRunner {
    static func runAndExit(_ request: QuillCodeDesktopSmokeRequest) async {
        do {
            let report = try await run(request)
            let json = try report.prettyJSON()
            if let reportPath = request.reportPath, !reportPath.isEmpty {
                let reportURL = URL(fileURLWithPath: reportPath)
                try FileManager.default.createDirectory(
                    at: reportURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try json.write(to: reportURL, options: .atomic)
            }
            FileHandle.standardOutput.write(json)
            FileHandle.standardOutput.write(Data("\n".utf8))
            exit(0)
        } catch {
            FileHandle.standardError.write(Data("quill-code-desktop smoke failed: \(error)\n".utf8))
            exit(1)
        }
    }

    private static func run(_ request: QuillCodeDesktopSmokeRequest) async throws -> QuillCodeDesktopSmokeReport {
        let root = try QuillCodeDesktopSmokeWorkspaceRoot(request: request)
        let paths = QuillCodePaths(home: root.home)
        let runtimeFactory = QuillCodeRuntimeFactory(
            paths: paths,
            environment: ["QUILLCODE_USE_MOCK_LLM": "1"]
        )
        let bootstrap = QuillCodeWorkspaceBootstrap(paths: paths, runtimeFactory: runtimeFactory)
        let automationNotifier = SmokeAutomationNotifier()
        let controller = QuillCodeDesktopController(
            bootstrap: bootstrap,
            browserPageFetcher: URLSessionBrowserPageFetcher(),
            browserLiveDOMCapturer: nil,
            browserSessionPresenter: SmokeBrowserSessionPresenter(),
            automationNotifier: automationNotifier,
            workspaceRoot: root.workspace
        )

        let chrome = try QuillCodeDesktopChromeSmoke.verify(controller: controller)

        let writePrompt = #"Can you write a file that says "hello world""#
        controller.draft = writePrompt
        let previousTimelineCount = controller.surface.transcript.timelineItems.count
        controller.send()

        try await waitForDesktopRun(
            controller,
            previousTimelineCount: previousTimelineCount,
            expectedAnswer: "Wrote `hello.txt`."
        )

        let createdFile = root.workspace.appendingPathComponent("hello.txt")
        let createdText = try String(contentsOf: createdFile, encoding: .utf8)
        guard createdText.contains("hello world") else {
            throw QuillCodeDesktopSmokeFailure.createdFileMismatch(createdFile.path)
        }

        let writeSurface = controller.surface
        let writeFinalAnswer = writeSurface.transcript.messages.last?.text ?? ""
        let writeToolName = writeSurface.transcript.toolCards.last?.title ?? ""

        let followUpPrompt = "Read `hello.txt` and tell me its exact content."
        controller.draft = followUpPrompt
        let followUpPreviousTimelineCount = controller.surface.transcript.timelineItems.count
        controller.send()

        try await waitForDesktopRun(
            controller,
            previousTimelineCount: followUpPreviousTimelineCount,
            expectedAnswer: "hello world"
        )

        let followUpSurface = controller.surface
        let followUpFinalAnswer = followUpSurface.transcript.messages.last?.text ?? ""
        let followUpToolName = followUpSurface.transcript.toolCards.last?.title ?? ""
        guard followUpFinalAnswer.contains("Contents of `hello.txt`:"),
              followUpFinalAnswer.contains("hello world")
        else {
            throw QuillCodeDesktopSmokeFailure.followUpReadMismatch(followUpFinalAnswer)
        }

        let browserSmoke = try await runBrowserSmoke(controller: controller, root: root)
        let browserWorkflowSmoke = try await runBrowserWorkflowSmoke(controller: controller, root: root)
        let browserSpreadsheetWorkflowSmoke = try await runBrowserSpreadsheetWorkflowSmoke(
            controller: controller,
            root: root
        )
        let browserAuthenticatedWorkflowSmoke = try await runBrowserAuthenticatedWorkflowSmoke(
            controller: controller,
            root: root
        )
        let computerUseActionSmoke = try await runComputerUseActionSmoke(root: root)
        let multiFileArtifactSmoke = try await runMultiFileArtifactSmoke(controller: controller, root: root)
        let oneTurnCoworkerSmoke = try await runOneTurnCoworkerSmoke(controller: controller, root: root)
        let surface = controller.surface
        let nativeHitTargets = try QuillCodeDesktopNativeHitTargetSmoke.validatedReport(for: surface)
        guard surface.transcript.messages.count >= 4,
              surface.transcript.toolCards.count >= 3,
              surface.transcript.timelineItems.count >= 9
        else {
            throw QuillCodeDesktopSmokeFailure.incompleteTranscript
        }
        guard surface.transcript.toolCards.last?.status == .done else {
            throw QuillCodeDesktopSmokeFailure.toolCardDidNotComplete
        }

        let renderURL = root.renderURL(request: request)
        let image = try renderWorkspace(controller: controller, renderURL: renderURL)
        let stats = try QuillCodeDesktopSmokePixelStats(image: image)
        try stats.validate(
            expectedWidth: 1280,
            expectedHeight: 900,
            minDistinctColorBuckets: 28,
            minBrightPixelRatio: 0.0008,
            minBlueAccentPixelRatio: 0.0001
        )

        let resultRenderURL = root.resultRenderURL(request: request)
        let resultImage = try renderResultEvidence(
            surface: surface,
            createdFilePath: createdFile.path,
            renderURL: resultRenderURL
        )
        let resultStats = try QuillCodeDesktopSmokePixelStats(image: resultImage)
        try resultStats.validate(
            expectedWidth: 820,
            expectedHeight: 720,
            minDistinctColorBuckets: 28,
            minBrightPixelRatio: 0.004,
            minBlueAccentPixelRatio: 0.0004
        )

        let chromeRenderURL = root.chromeRenderURL(request: request)
        let chromeImage = try QuillCodeDesktopChromeSmoke.render(chrome, to: chromeRenderURL)
        let chromeStats = try QuillCodeDesktopSmokePixelStats(image: chromeImage)
        try chromeStats.validate(
            expectedWidth: 420,
            expectedHeight: 760,
            minDistinctColorBuckets: 22,
            minBrightPixelRatio: 0.004,
            minBlueAccentPixelRatio: 0.0005
        )

        let htmlURL = root.htmlURL(request: request)
        let html = WorkspaceHTMLRenderer.render(surface)
        guard html.contains("Wrote `hello.txt`."),
              html.contains("Contents of `hello.txt`:"),
              html.contains("hello world"),
              html.contains("Inspected `Browser Smoke`"),
              html.contains("host.browser.inspect"),
              html.contains("host.file.read"),
              html.contains("host.file.write")
        else {
            throw QuillCodeDesktopSmokeFailure.htmlMissingResult
        }
        try html.write(to: htmlURL, atomically: true, encoding: .utf8)

        let scheduledCoworkerSmoke = try runScheduledCoworkerSmoke(
            controller: controller,
            notifier: automationNotifier
        )

        return QuillCodeDesktopSmokeReport(
            ok: true,
            prompt: writePrompt,
            finalAnswer: writeFinalAnswer,
            toolName: writeToolName,
            followUpPrompt: followUpPrompt,
            followUpFinalAnswer: followUpFinalAnswer,
            followUpToolName: followUpToolName,
            toolNames: surface.transcript.toolCards.map(\.title),
            messageCount: surface.transcript.messages.count,
            toolCardCount: surface.transcript.toolCards.count,
            timelineItemCount: surface.transcript.timelineItems.count,
            workspacePath: root.workspace.path,
            createdFilePath: createdFile.path,
            renderPath: renderURL.path,
            resultRenderPath: resultRenderURL.path,
            chromeRenderPath: chromeRenderURL.path,
            htmlPath: htmlURL.path,
            image: stats.report,
            resultImage: resultStats.report,
            chromeImage: chromeStats.report,
            chrome: chrome,
            browserSmoke: browserSmoke,
            browserWorkflowSmoke: browserWorkflowSmoke,
            browserSpreadsheetWorkflowSmoke: browserSpreadsheetWorkflowSmoke,
            browserAuthenticatedWorkflowSmoke: browserAuthenticatedWorkflowSmoke,
            computerUseActionSmoke: computerUseActionSmoke,
            multiFileArtifactSmoke: multiFileArtifactSmoke,
            oneTurnCoworkerSmoke: oneTurnCoworkerSmoke,
            scheduledCoworkerSmoke: scheduledCoworkerSmoke,
            nativeHitTargets: nativeHitTargets
        )
    }

    private static func runComputerUseActionSmoke(
        root: QuillCodeDesktopSmokeWorkspaceRoot
    ) async throws -> QuillCodeDesktopComputerUseActionSmokeReport {
        let backend = StubComputerUseBackend(
            foregroundApplication: ComputerUseApplication(
                name: "QuillCode Smoke Target",
                bundleIdentifier: "co.lorehex.QuillCode.SmokeTarget"
            ),
            accessibilitySnapshot: ComputerUseAccessibilitySnapshot(elements: [
                ComputerUseAccessibilityElement(role: "Window", label: "QuillCode Smoke Target"),
                ComputerUseAccessibilityElement(role: "Button", label: "Save"),
                ComputerUseAccessibilityElement(role: "TextField", label: "Prompt", value: "Ready")
            ])
        )
        let artifactDirectory = root.root.appendingPathComponent("computer-use-smoke", isDirectory: true)
        let executor = ComputerUseToolExecutor(
            backend: backend,
            artifactDirectory: artifactDirectory,
            originThreadID: "desktop-smoke-thread",
            projectID: "desktop-smoke-project",
            workspaceRoot: root.workspace.path
        )

        let screenshotResult = try requiredToolResult(
            await executor.execute(ToolCall(name: ToolDefinition.computerScreenshot.name, argumentsJSON: "{}")),
            toolName: ToolDefinition.computerScreenshot.name
        )
        let screenshotOutput = try decodeSmokeOutput(ComputerScreenshotToolOutput.self, from: screenshotResult)
        guard let screenshotPath = screenshotOutput.path,
              FileManager.default.fileExists(atPath: screenshotPath),
              screenshotOutput.foregroundApplication?.name == "QuillCode Smoke Target",
              screenshotOutput.accessibilitySnapshot?.elements.count == 3
        else {
            throw QuillCodeDesktopSmokeFailure.computerUseActionMismatch(
                "screenshot did not preserve artifact, foreground app, and accessibility evidence"
            )
        }

        let calls = computerUseActionSmokeCalls()
        var outputs: [String] = []
        for call in calls {
            let result = try requiredToolResult(await executor.execute(call), toolName: call.name)
            outputs.append(result.stdout)
        }

        let recordedActions = await backend.recordedActions()
        let expectedActions = [
            "screenshot",
            "leftClick:42,84",
            "type:QuillCode smoke",
            "scroll:0,-120",
            "move:64,96",
            "key:return"
        ]
        guard recordedActions == expectedActions else {
            throw QuillCodeDesktopSmokeFailure.computerUseActionMismatch(
                "unexpected actions: \(recordedActions.joined(separator: ", "))"
            )
        }

        return QuillCodeDesktopComputerUseActionSmokeReport(
            toolSequence: [ToolDefinition.computerScreenshot.name] + calls.map(\.name),
            actionSequence: recordedActions,
            argumentJSON: ["{}"] + calls.map(\.argumentsJSON),
            outputSummaries: ["Captured desktop screenshot."] + outputs,
            screenshotPath: screenshotPath,
            screenshotArtifactExists: true,
            foregroundApplication: screenshotOutput.foregroundApplication?.displayLabel ?? "",
            accessibilitySummary: screenshotOutput.accessibilitySnapshot?.summary ?? ""
        )
    }

    private static func computerUseActionSmokeCalls() -> [ToolCall] {
        [
            ToolCall(name: ToolDefinition.computerClick.name, argumentsJSON: #"{"x":42,"y":84}"#),
            ToolCall(name: ToolDefinition.computerType.name, argumentsJSON: #"{"text":"QuillCode smoke"}"#),
            ToolCall(name: ToolDefinition.computerScroll.name, argumentsJSON: #"{"dx":0,"dy":-120}"#),
            ToolCall(name: ToolDefinition.computerMove.name, argumentsJSON: #"{"x":64,"y":96}"#),
            ToolCall(name: ToolDefinition.computerKey.name, argumentsJSON: #"{"key":"return"}"#)
        ]
    }

    private static func runBrowserSmoke(
        controller: QuillCodeDesktopController,
        root: QuillCodeDesktopSmokeWorkspaceRoot
    ) async throws -> QuillCodeDesktopBrowserSmokeReport {
        let previewFile = root.workspace.appendingPathComponent("browser-smoke.html")
        try """
        <!doctype html>
        <html>
          <head><title>Browser Smoke</title></head>
          <body>
            <main>
              <h1>Browser Smoke</h1>
              <p>Native browser smoke preview text.</p>
              <button>Smoke Action</button>
            </main>
          </body>
        </html>
        """.write(to: previewFile, atomically: true, encoding: .utf8)

        controller.browserAddressDraft = "browser-smoke.html"
        controller.openBrowserPreview()
        controller.addBrowserComment("Check the smoke hero")

        let browser = controller.surface.browser
        guard browser.currentURL?.hasSuffix("/browser-smoke.html") == true,
              browser.title == "Browser Smoke",
              browser.snapshot?.inspectionDepth == .staticHTMLSnapshot,
              browser.snapshot?.outline.contains("H1: Browser Smoke") == true,
              browser.snapshot?.textSnippet?.contains("Native browser smoke preview text.") == true
        else {
            throw QuillCodeDesktopSmokeFailure.browserSmokeFailed(
                "browser preview did not expose the local HTML snapshot"
            )
        }

        controller.draft = "inspect browser page"
        let previousTimelineCount = controller.surface.transcript.timelineItems.count
        controller.send()

        try await waitForDesktopRun(
            controller,
            previousTimelineCount: previousTimelineCount,
            expectedAnswer: "Browser Smoke"
        )

        let surface = controller.surface
        let finalAnswer = surface.transcript.messages.last?.text ?? ""
        let toolCard = surface.transcript.toolCards.last
        guard toolCard?.title == ToolDefinition.browserInspect.name,
              toolCard?.status == .done,
              finalAnswer.contains("Inspected `Browser Smoke`"),
              finalAnswer.contains("H1: Browser Smoke"),
              finalAnswer.contains("Native browser smoke preview text."),
              finalAnswer.contains("Check the smoke hero")
        else {
            throw QuillCodeDesktopSmokeFailure.browserSmokeFailed(finalAnswer)
        }

        let snapshot = surface.browser.snapshot
        return QuillCodeDesktopBrowserSmokeReport(
            previewPath: previewFile.path,
            url: surface.browser.currentURL ?? "",
            title: surface.browser.title,
            status: surface.browser.statusLabel,
            sourceLabel: snapshot?.sourceLabel ?? "",
            inspectionDepth: snapshot?.inspectionDepth.label ?? "",
            outline: snapshot?.outline ?? [],
            textSnippet: snapshot?.textSnippet ?? "",
            commentCount: surface.browser.comments.count,
            toolName: toolCard?.title ?? "",
            finalAnswer: finalAnswer
        )
    }

    private static func runBrowserWorkflowSmoke(
        controller: QuillCodeDesktopController,
        root: QuillCodeDesktopSmokeWorkspaceRoot
    ) async throws -> QuillCodeDesktopBrowserWorkflowSmokeReport {
        let previewFile = root.workspace.appendingPathComponent("browser-crm-smoke.html")
        try """
        <!doctype html>
        <html>
          <head><title>CRM Workflow Smoke</title></head>
          <body>
            <main>
              <h1>CRM Workflow Smoke</h1>
              <label>Status <input name="status" value="Open"></label>
              <button data-action="save">Save</button>
              <p data-testid="status">Status: Open</p>
            </main>
          </body>
        </html>
        """.write(to: previewFile, atomically: true, encoding: .utf8)

        controller.browserAddressDraft = "browser-crm-smoke.html"
        controller.openBrowserPreview()
        controller.openBrowserSession()

        let override = try requiredBrowserToolOverride(controller)
        let workspace = root.workspace
        let typeTool = try requiredToolResult(
            await override(
                ToolCall(
                    name: ToolDefinition.browserType.name,
                    argumentsJSON: ToolArguments.json([
                        "selector": "input[name='status']",
                        "text": "Qualified",
                        "submit": false
                    ])
                ),
                workspace
            ),
            toolName: ToolDefinition.browserType.name
        )
        let clickTool = try requiredToolResult(
            await override(
                ToolCall(
                    name: ToolDefinition.browserClick.name,
                    argumentsJSON: ToolArguments.json(["selector": "button[data-action='save']"])
                ),
                workspace
            ),
            toolName: ToolDefinition.browserClick.name
        )
        let scriptTool = try requiredToolResult(
            await override(
                ToolCall(
                    name: ToolDefinition.browserScript.name,
                    argumentsJSON: ToolArguments.json([
                        "source": "document.querySelector('[data-testid=\"status\"]').textContent"
                    ])
                ),
                workspace
            ),
            toolName: ToolDefinition.browserScript.name
        )
        let inspectTool = try requiredToolResult(
            await override(
                ToolCall(name: ToolDefinition.browserInspect.name, argumentsJSON: "{}"),
                workspace
            ),
            toolName: ToolDefinition.browserInspect.name
        )

        let typeOutput = try decodeSmokeOutput(BrowserActionToolOutput.self, from: typeTool)
        let clickOutput = try decodeSmokeOutput(BrowserActionToolOutput.self, from: clickTool)
        let scriptOutput = try decodeSmokeOutput(BrowserScriptToolOutput.self, from: scriptTool)
        let inspectOutput = try decodeSmokeOutput(BrowserInspectionToolOutput.self, from: inspectTool)

        guard typeOutput.selector == "input[name='status']",
              typeOutput.action == "type",
              clickOutput.selector == "button[data-action='save']",
              clickOutput.action == "click",
              scriptOutput.value.contains("Qualified"),
              scriptOutput.value.contains("saved=true"),
              inspectOutput.inspectionDepth == .liveDOMSnapshot,
              inspectOutput.outline.contains("H1: CRM Workflow Smoke"),
              inspectOutput.textSnippet?.contains("Qualified") == true,
              inspectOutput.textSnippet?.contains("Saved") == true
        else {
            throw QuillCodeDesktopSmokeFailure.browserSmokeFailed(
                "browser workflow smoke did not preserve typed/clicked live DOM state"
            )
        }

        return QuillCodeDesktopBrowserWorkflowSmokeReport(
            previewPath: previewFile.path,
            url: inspectOutput.url,
            typedSelector: typeOutput.selector,
            typedText: "Qualified",
            clickedSelector: clickOutput.selector,
            typeToolName: ToolDefinition.browserType.name,
            clickToolName: ToolDefinition.browserClick.name,
            scriptToolName: ToolDefinition.browserScript.name,
            inspectToolName: ToolDefinition.browserInspect.name,
            scriptValue: scriptOutput.value,
            inspectionDepth: inspectOutput.inspectionDepth.label,
            sourceLabel: inspectOutput.sourceLabel,
            outline: inspectOutput.outline,
            textSnippet: inspectOutput.textSnippet ?? ""
        )
    }

    private static func runBrowserSpreadsheetWorkflowSmoke(
        controller: QuillCodeDesktopController,
        root: QuillCodeDesktopSmokeWorkspaceRoot
    ) async throws -> QuillCodeDesktopBrowserWorkflowSmokeReport {
        let previewFile = root.workspace.appendingPathComponent("browser-sheet-smoke.html")
        try """
        <!doctype html>
        <html>
          <head><title>Shared Sheet Workflow Smoke</title></head>
          <body>
            <main>
              <h1>Shared Sheet Workflow Smoke</h1>
              <table aria-label="Launch tracker">
                <tr>
                  <th>Item</th>
                  <th>Date</th>
                  <th>Status</th>
                </tr>
                <tr>
                  <td>Launch checklist</td>
                  <td><input data-cell="launch-date" value="TBD"></td>
                  <td><button data-action="mark-done">Mark done</button></td>
                </tr>
              </table>
              <p data-testid="row-state">Launch checklist: TBD; done=false</p>
            </main>
          </body>
        </html>
        """.write(to: previewFile, atomically: true, encoding: .utf8)

        controller.browserAddressDraft = "browser-sheet-smoke.html"
        controller.openBrowserPreview()
        controller.openBrowserSession()

        let override = try requiredBrowserToolOverride(controller)
        let workspace = root.workspace
        let typeTool = try requiredToolResult(
            await override(
                ToolCall(
                    name: ToolDefinition.browserType.name,
                    argumentsJSON: ToolArguments.json([
                        "selector": "[data-cell='launch-date']",
                        "text": "2026-09-15",
                        "submit": false
                    ])
                ),
                workspace
            ),
            toolName: ToolDefinition.browserType.name
        )
        let clickTool = try requiredToolResult(
            await override(
                ToolCall(
                    name: ToolDefinition.browserClick.name,
                    argumentsJSON: ToolArguments.json(["selector": "button[data-action='mark-done']"])
                ),
                workspace
            ),
            toolName: ToolDefinition.browserClick.name
        )
        let scriptTool = try requiredToolResult(
            await override(
                ToolCall(
                    name: ToolDefinition.browserScript.name,
                    argumentsJSON: ToolArguments.json([
                        "source": "document.querySelector('[data-testid=\"row-state\"]').textContent"
                    ])
                ),
                workspace
            ),
            toolName: ToolDefinition.browserScript.name
        )
        let inspectTool = try requiredToolResult(
            await override(
                ToolCall(name: ToolDefinition.browserInspect.name, argumentsJSON: "{}"),
                workspace
            ),
            toolName: ToolDefinition.browserInspect.name
        )

        let typeOutput = try decodeSmokeOutput(BrowserActionToolOutput.self, from: typeTool)
        let clickOutput = try decodeSmokeOutput(BrowserActionToolOutput.self, from: clickTool)
        let scriptOutput = try decodeSmokeOutput(BrowserScriptToolOutput.self, from: scriptTool)
        let inspectOutput = try decodeSmokeOutput(BrowserInspectionToolOutput.self, from: inspectTool)

        guard typeOutput.selector == "[data-cell='launch-date']",
              typeOutput.action == "type",
              clickOutput.selector == "button[data-action='mark-done']",
              clickOutput.action == "click",
              scriptOutput.value.contains("2026-09-15"),
              scriptOutput.value.contains("done=true"),
              inspectOutput.inspectionDepth == .liveDOMSnapshot,
              inspectOutput.outline.contains("H1: Shared Sheet Workflow Smoke"),
              inspectOutput.textSnippet?.contains("2026-09-15") == true,
              inspectOutput.textSnippet?.contains("Done") == true
        else {
            throw QuillCodeDesktopSmokeFailure.browserSmokeFailed(
                "browser spreadsheet workflow smoke did not preserve edited row state"
            )
        }

        return QuillCodeDesktopBrowserWorkflowSmokeReport(
            previewPath: previewFile.path,
            url: inspectOutput.url,
            typedSelector: typeOutput.selector,
            typedText: "2026-09-15",
            clickedSelector: clickOutput.selector,
            typeToolName: ToolDefinition.browserType.name,
            clickToolName: ToolDefinition.browserClick.name,
            scriptToolName: ToolDefinition.browserScript.name,
            inspectToolName: ToolDefinition.browserInspect.name,
            scriptValue: scriptOutput.value,
            inspectionDepth: inspectOutput.inspectionDepth.label,
            sourceLabel: inspectOutput.sourceLabel,
            outline: inspectOutput.outline,
            textSnippet: inspectOutput.textSnippet ?? ""
        )
    }

    private static func runBrowserAuthenticatedWorkflowSmoke(
        controller: QuillCodeDesktopController,
        root: QuillCodeDesktopSmokeWorkspaceRoot
    ) async throws -> QuillCodeDesktopBrowserWorkflowSmokeReport {
        let previewFile = root.workspace.appendingPathComponent("browser-auth-smoke.html")
        try """
        <!doctype html>
        <html>
          <head><title>Signed-In Workspace Smoke</title></head>
          <body>
            <main>
              <h1>Signed-In Workspace Smoke</h1>
              <label>Workspace key <input name="workspace-key" value=""></label>
              <button data-action="sign-in">Sign in</button>
              <p data-testid="account-state">Signed out; workspace=none; signed-in=false</p>
            </main>
          </body>
        </html>
        """.write(to: previewFile, atomically: true, encoding: .utf8)

        controller.browserAddressDraft = "browser-auth-smoke.html"
        controller.openBrowserPreview()
        controller.openBrowserSession()

        let override = try requiredBrowserToolOverride(controller)
        let workspace = root.workspace
        let typeTool = try requiredToolResult(
            await override(
                ToolCall(
                    name: ToolDefinition.browserType.name,
                    argumentsJSON: ToolArguments.json([
                        "selector": "input[name='workspace-key']",
                        "text": "lorehex-demo",
                        "submit": false
                    ])
                ),
                workspace
            ),
            toolName: ToolDefinition.browserType.name
        )
        let clickTool = try requiredToolResult(
            await override(
                ToolCall(
                    name: ToolDefinition.browserClick.name,
                    argumentsJSON: ToolArguments.json(["selector": "button[data-action='sign-in']"])
                ),
                workspace
            ),
            toolName: ToolDefinition.browserClick.name
        )
        let scriptTool = try requiredToolResult(
            await override(
                ToolCall(
                    name: ToolDefinition.browserScript.name,
                    argumentsJSON: ToolArguments.json([
                        "source": "document.querySelector('[data-testid=\"account-state\"]').textContent"
                    ])
                ),
                workspace
            ),
            toolName: ToolDefinition.browserScript.name
        )
        let inspectTool = try requiredToolResult(
            await override(
                ToolCall(name: ToolDefinition.browserInspect.name, argumentsJSON: "{}"),
                workspace
            ),
            toolName: ToolDefinition.browserInspect.name
        )

        let typeOutput = try decodeSmokeOutput(BrowserActionToolOutput.self, from: typeTool)
        let clickOutput = try decodeSmokeOutput(BrowserActionToolOutput.self, from: clickTool)
        let scriptOutput = try decodeSmokeOutput(BrowserScriptToolOutput.self, from: scriptTool)
        let inspectOutput = try decodeSmokeOutput(BrowserInspectionToolOutput.self, from: inspectTool)

        guard typeOutput.selector == "input[name='workspace-key']",
              typeOutput.action == "type",
              clickOutput.selector == "button[data-action='sign-in']",
              clickOutput.action == "click",
              scriptOutput.value.contains("signed-in=true"),
              scriptOutput.value.contains("lorehex-demo"),
              inspectOutput.inspectionDepth == .liveDOMSnapshot,
              inspectOutput.outline.contains("H1: Signed-In Workspace Smoke"),
              inspectOutput.textSnippet?.contains("Signed in") == true,
              inspectOutput.textSnippet?.contains("lorehex-demo") == true
        else {
            throw QuillCodeDesktopSmokeFailure.browserSmokeFailed(
                "browser authenticated workflow smoke did not preserve signed-in session state"
            )
        }

        return QuillCodeDesktopBrowserWorkflowSmokeReport(
            previewPath: previewFile.path,
            url: inspectOutput.url,
            typedSelector: typeOutput.selector,
            typedText: "lorehex-demo",
            clickedSelector: clickOutput.selector,
            typeToolName: ToolDefinition.browserType.name,
            clickToolName: ToolDefinition.browserClick.name,
            scriptToolName: ToolDefinition.browserScript.name,
            inspectToolName: ToolDefinition.browserInspect.name,
            scriptValue: scriptOutput.value,
            inspectionDepth: inspectOutput.inspectionDepth.label,
            sourceLabel: inspectOutput.sourceLabel,
            outline: inspectOutput.outline,
            textSnippet: inspectOutput.textSnippet ?? ""
        )
    }

    private static func runScheduledCoworkerSmoke(
        controller: QuillCodeDesktopController,
        notifier: SmokeAutomationNotifier
    ) throws -> QuillCodeDesktopScheduledCoworkerSmokeReport {
        guard let project = controller.model.selectedProject else {
            throw QuillCodeDesktopSmokeFailure.browserSmokeFailed("scheduled coworker smoke missing selected project")
        }

        let taskText = "check competitor pricing pages and notify me with a diff"
        let scheduleDescription = "Every Monday at 8:00 AM"
        let runAt = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970))
        let recurrence = QuillAutomationRecurrence(
            interval: 1,
            unit: .weeks,
            weekdays: [2],
            hour: 8,
            minute: 0
        )
        let automation = QuillAutomation(
            title: "Scheduled task: check competitor pricing pages and notify me with a diff",
            detail: taskText,
            kind: .workspaceSchedule,
            scheduleKind: .cron,
            scheduleDescription: scheduleDescription,
            projectID: project.id,
            createdAt: runAt.addingTimeInterval(-3_600),
            updatedAt: runAt.addingTimeInterval(-3_600),
            nextRunAt: runAt.addingTimeInterval(-10),
            recurrence: recurrence
        )

        let startingNotificationCount = notifier.automationReports.count
        controller.model.setAutomations([automation])
        controller.automationCoordinator.runDueAutomations(
            model: controller.model,
            notifier: notifier,
            refresh: { controller.refresh() }
        )

        let deliveredReports = Array(notifier.automationReports.dropFirst(startingNotificationCount))
        guard deliveredReports.count == 1, let report = deliveredReports.first else {
            throw QuillCodeDesktopSmokeFailure.browserSmokeFailed(
                "scheduled coworker smoke did not deliver exactly one automation notification"
            )
        }
        guard report.automationID == automation.id,
              report.title == "QuillCode scheduled task ready",
              report.body.contains(taskText)
        else {
            throw QuillCodeDesktopSmokeFailure.browserSmokeFailed(
                "scheduled coworker smoke delivered the wrong notification report"
            )
        }

        guard let thread = controller.model.root.threads.first(where: { $0.id == report.followUpThreadID }),
              thread.projectID == project.id,
              thread.title == "Scheduled check: \(project.name)",
              thread.messages.first?.content.contains("Run the scheduled coworker task for \(project.name).") == true,
              thread.messages.first?.content.contains("Task: \(taskText)") == true
        else {
            throw QuillCodeDesktopSmokeFailure.browserSmokeFailed(
                "scheduled coworker smoke did not create the expected follow-up thread"
            )
        }

        guard let savedAutomation = controller.model.automations.items.first(where: { $0.id == automation.id }),
              savedAutomation.lastRunAt != nil,
              savedAutomation.nextRunAt != nil,
              savedAutomation.nextRunAt != automation.nextRunAt,
              controller.surface.automations.isVisible
        else {
            throw QuillCodeDesktopSmokeFailure.browserSmokeFailed(
                "scheduled coworker smoke did not persist run state and reveal automation history"
            )
        }

        return QuillCodeDesktopScheduledCoworkerSmokeReport(
            automationTitle: savedAutomation.title,
            taskText: taskText,
            scheduleDescription: savedAutomation.scheduleDescription,
            reportTitle: report.title,
            reportBody: report.body,
            notificationCount: deliveredReports.count,
            followUpThreadTitle: thread.title,
            followUpPrompt: thread.messages.first?.content ?? "",
            automationsVisible: controller.surface.automations.isVisible,
            lastRunRecorded: savedAutomation.lastRunAt != nil,
            nextRunRecorded: savedAutomation.nextRunAt != nil
        )
    }

    private static func runMultiFileArtifactSmoke(
        controller: QuillCodeDesktopController,
        root: QuillCodeDesktopSmokeWorkspaceRoot
    ) async throws -> QuillCodeDesktopMultiFileArtifactSmokeReport {
        let notesDirectory = root.workspace.appendingPathComponent("notes", isDirectory: true)
        try FileManager.default.createDirectory(at: notesDirectory, withIntermediateDirectories: true)

        let researchFile = notesDirectory.appendingPathComponent("research.md")
        let risksFile = notesDirectory.appendingPathComponent("risks.md")
        try """
        # Research

        Customers asked for QuillCloud relay reliability before shipment.
        The launch owner is Maya.
        """.write(to: researchFile, atomically: true, encoding: .utf8)
        try """
        # Risks

        The top risk is pairing fallback after a bad Wi-Fi password.
        The mitigation is a deterministic AP fallback smoke before shipping.
        """.write(to: risksFile, atomically: true, encoding: .utf8)

        let prompt = "Create the team action brief from `notes/research.md` and `notes/risks.md`."
        let previousTimelineCount = controller.surface.transcript.timelineItems.count
        let previousToolCardCount = controller.surface.transcript.toolCards.count
        controller.draft = prompt
        controller.send()

        let expectedAnswer = "Created `team-action-brief.md` from `notes/research.md` and `notes/risks.md`."
        try await waitForDesktopRun(
            controller,
            previousTimelineCount: previousTimelineCount,
            expectedAnswer: expectedAnswer
        )

        let deliverable = root.workspace.appendingPathComponent("team-action-brief.md")
        let deliverableText = try String(contentsOf: deliverable, encoding: .utf8)
        let containsResearch = deliverableText.contains("QuillCloud relay reliability")
            && deliverableText.contains("Maya")
        let containsRisk = deliverableText.contains("pairing fallback")
            && deliverableText.contains("bad Wi-Fi password")
        let containsNextAction = deliverableText.contains("Run the pairing fallback smoke")
        guard containsResearch, containsRisk, containsNextAction else {
            throw QuillCodeDesktopSmokeFailure.multiFileArtifactMismatch(deliverable.path)
        }

        let toolSequence = Array(controller.surface.transcript.toolCards.dropFirst(previousToolCardCount))
            .map(\.title)
        guard toolSequence == [
            ToolDefinition.fileRead.name,
            ToolDefinition.fileRead.name,
            ToolDefinition.fileWrite.name
        ] else {
            throw QuillCodeDesktopSmokeFailure.multiFileArtifactMismatch(
                "unexpected tool sequence: \(toolSequence.joined(separator: ", "))"
            )
        }

        return QuillCodeDesktopMultiFileArtifactSmokeReport(
            prompt: prompt,
            sourcePaths: [researchFile.path, risksFile.path],
            deliverablePath: deliverable.path,
            toolSequence: toolSequence,
            finalAnswer: controller.surface.transcript.messages.last?.text ?? "",
            deliverableContainsResearch: containsResearch,
            deliverableContainsRisk: containsRisk,
            deliverableContainsNextAction: containsNextAction
        )
    }

    private static func runOneTurnCoworkerSmoke(
        controller: QuillCodeDesktopController,
        root: QuillCodeDesktopSmokeWorkspaceRoot
    ) async throws -> QuillCodeDesktopOneTurnCoworkerSmokeReport {
        let cases = [
            OneTurnCoworkerSmokeCase(
                taskID: 15,
                prompt: "Create a file named `launch-announcement.md` that says `Billing portal launch email ready.`",
                expectedToolName: ToolDefinition.fileWrite.name,
                expectedAnswer: "Wrote `launch-announcement.md`.",
                artifactRelativePath: "launch-announcement.md",
                artifactExpectation: .textContains("Billing portal launch email ready.")
            ),
            OneTurnCoworkerSmokeCase(
                taskID: 16,
                prompt: "Run `printf 'source,signups\\nads,42\\norganic,31\\n' > signup-slice.csv && printf 'wrote signup-slice.csv\\n'`",
                expectedToolName: ToolDefinition.shellRun.name,
                expectedAnswer: "wrote signup-slice.csv",
                artifactRelativePath: "signup-slice.csv",
                artifactExpectation: .textContains("organic,31")
            ),
            OneTurnCoworkerSmokeCase(
                taskID: 20,
                prompt: "Run `\(chartGenerationCommand)`",
                expectedToolName: ToolDefinition.shellRun.name,
                expectedAnswer: "wrote regional-revenue-chart.png",
                artifactRelativePath: "regional-revenue-chart.png",
                artifactExpectation: .png(
                    width: 320,
                    height: 200,
                    minimumByteCount: 700,
                    assertion: "PNG 320x200 stacked revenue chart"
                )
            ),
            OneTurnCoworkerSmokeCase(
                taskID: 21,
                prompt: "Run `\(cohortRetentionCommand)`",
                expectedToolName: ToolDefinition.shellRun.name,
                expectedAnswer: "wrote cohort-retention.csv",
                artifactRelativePath: "cohort-retention.csv",
                artifactExpectation: .textContains("2026-01,3,67%,2026-02")
            ),
            OneTurnCoworkerSmokeCase(
                taskID: 28,
                prompt: "Create a file named `dependency-map.mmd` that says `flowchart LR\\n  Product --> Engineering\\n  Engineering --> Launch\\n  Launch --> Support\\n`",
                expectedToolName: ToolDefinition.fileWrite.name,
                expectedAnswer: "Wrote `dependency-map.mmd`.",
                artifactRelativePath: "dependency-map.mmd",
                artifactExpectation: .textContains("Engineering --> Launch")
            ),
            OneTurnCoworkerSmokeCase(
                taskID: 68,
                prompt: "Run `printf 'project,files,todos\\nLaunch,3,2\\n' > weekly-review.csv && printf 'wrote weekly-review.csv\\n'`",
                expectedToolName: ToolDefinition.shellRun.name,
                expectedAnswer: "wrote weekly-review.csv",
                artifactRelativePath: "weekly-review.csv",
                artifactExpectation: .textContains("Launch,3,2")
            )
        ]

        var reports: [QuillCodeDesktopOneTurnCoworkerSmokeCaseReport] = []
        for smokeCase in cases {
            let previousTimelineCount = controller.surface.transcript.timelineItems.count
            let previousToolCardCount = controller.surface.transcript.toolCards.count
            controller.draft = smokeCase.prompt
            controller.send()

            try await waitForDesktopRun(
                controller,
                previousTimelineCount: previousTimelineCount,
                expectedAnswer: smokeCase.expectedAnswer
            )

            let newToolCards = Array(controller.surface.transcript.toolCards.dropFirst(previousToolCardCount))
            guard newToolCards.count == 1,
                  newToolCards.first?.title == smokeCase.expectedToolName,
                  newToolCards.first?.status == .done
            else {
                throw QuillCodeDesktopSmokeFailure.oneTurnCoworkerMismatch(
                    "task \(smokeCase.taskID) unexpected tool cards: \(newToolCards.map(\.title).joined(separator: ", "))"
                )
            }

            let artifact = root.workspace.appendingPathComponent(smokeCase.artifactRelativePath)
            try verifyOneTurnCoworkerArtifact(smokeCase.artifactExpectation, artifact: artifact, taskID: smokeCase.taskID)

            reports.append(QuillCodeDesktopOneTurnCoworkerSmokeCaseReport(
                taskID: smokeCase.taskID,
                prompt: smokeCase.prompt,
                toolName: smokeCase.expectedToolName,
                artifactPath: artifact.path,
                artifactContains: smokeCase.artifactExpectation.assertion,
                finalAnswer: controller.surface.transcript.messages.last?.text ?? ""
            ))
        }

        return QuillCodeDesktopOneTurnCoworkerSmokeReport(cases: reports)
    }

    private static var chartGenerationCommand: String {
        let pngBase64 = "iVBORw0KGgoAAAANSUhEUgAAAUAAAADICAIAAAAWZq/8AAADLUlEQVR42u3awQ1AQBRF0enEmgbUoQ0bpahAN3oRJWBDA3Z8I3OSW8CL/BML0rYfkn5a8ggkgCUBLAlgCWBJAEsCWBLAEsCSAJYEsASwJIAlASwJYAlgSQBLAlgSwBLAkgCWBLAEsCSAb6rq9spDlwCWBLAEMMASwJIAlgAGWAIYYAlgSQBLAAMsASwJYAlggCWAAZYAlgSwBDDAEsAASwBLAlgCGGAJYEkASwADLAEMsASwJIAlgAGWAAZYAliltQxdQAADLIABlgAGWAADDLAABhhgAQywAAYYYAEMMMACGGAJYIAFMMAAC2CAARbAAEsAAyyAAQZYAAMMMBgAAyyAAQZYAAMMMMAAAyyAAQZYAAMMMMAAAwwwwAADLIABBlgAAwwwwAADLIABBlgAAwwwwAADDDDA78FY5z4ggAH2ZgMYYIABBhhggAEGGGCAAQYYYIABBhhggAEGGGCAAQYYYIABBhhggAEGGGCAAfaLYpYwAAYYYIABBhhggAEGGGCAAQYYYIABBhhggGMA+zwDMMAAAwwwwAADDDDAYIABMMAA2wkwwADbCTDAYAAMMMBgAAwwwHYCDDAYdgIMMBgAAwwwwAADDLCdAAMMhp0AOzg7AQbYwdkJMMBg2AkwwHY+tLOZxoAABthOgAEGw06AAQYDYIABthNggAG2E2CAwSgTBsAAAwwwwAADDDDAAAMMMMAAAwwwwAADDDDAAAMMMBhgAAwwwHYCDDAYdgIMMBgAAwwwwAADDLCdAAMMhp0AOzg7AQbYwdkJMMBg2AkwwHYCDLCDsxNggB2cnQADbKedAANsJ8AAOzg7AQbYwdkJMMB22gmwg7MTYIAdnJ0AAwyGnQADbCfAADs4OwEG2MHZCTDAdtoJMMB2Agywg7MTYIDBsBNggO20E2AHZyfAADs4OwEGGAw7AQbYToABdnB2Agywg7MTYIDttBNgB2cnwAA7ODsBBhgMOwEG2E6AAXZwdgKcM2Cp5ACWAP4CsCSAJQEsASwJYEkASwBLAlgSwJIAlgCWBLAkgCUBLAEsCWBJAEsASwJYEsCSAJYAlgSwJIAlgCUBLCm0ExkC2txUfBiYAAAAAElFTkSuQmCC"
        let csv = "quarter,north,south,west\\nQ1,42,28,18\\nQ2,50,33,24\\nQ3,58,36,31\\nQ4,66,42,37\\n"
        return """
        python3 -c "print((__import__('pathlib').Path('regional-revenue.csv').write_text('\(csv)'),__import__('pathlib').Path('regional-revenue-chart.png').write_bytes(__import__('base64').b64decode('\(pngBase64)')),'wrote regional-revenue-chart.png')[-1])"
        """
    }

    private static var cohortRetentionCommand: String {
        let subscriptionsCSV = "customer,signup_month,paid_month,canceled_month\\nA,2026-01,2026-01,\\nB,2026-01,2026-01,2026-02\\nC,2026-01,2026-02,\\nD,2026-02,2026-02,2026-03\\nE,2026-02,2026-02,\\n"
        let retentionCSV = "cohort,signup_count,retained_after_first_month,fastest_decay_month\\n2026-01,3,67%,2026-02\\n2026-02,2,50%,2026-03\\n"
        return """
        python3 -c "print((__import__('pathlib').Path('subscriptions.csv').write_text('\(subscriptionsCSV)'),__import__('pathlib').Path('cohort-retention.csv').write_text('\(retentionCSV)'),'wrote cohort-retention.csv')[-1])"
        """
    }

    private static func verifyOneTurnCoworkerArtifact(
        _ expectation: OneTurnCoworkerArtifactExpectation,
        artifact: URL,
        taskID: Int
    ) throws {
        switch expectation {
        case .textContains(let expected):
            let artifactText = try String(contentsOf: artifact, encoding: .utf8)
            guard artifactText.contains(expected) else {
                throw QuillCodeDesktopSmokeFailure.oneTurnCoworkerMismatch(
                    "task \(taskID) artifact missing expected content: \(artifact.path)"
                )
            }
        case .png(let width, let height, let minimumByteCount, _):
            let data = try Data(contentsOf: artifact)
            let pngSignature = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
            guard data.starts(with: pngSignature),
                  data.count >= minimumByteCount,
                  let dimensions = pngDimensions(in: data),
                  dimensions == (width, height)
            else {
                throw QuillCodeDesktopSmokeFailure.oneTurnCoworkerMismatch(
                    "task \(taskID) PNG artifact was invalid: \(artifact.path)"
                )
            }
        }
    }

    private static func pngDimensions(in data: Data) -> (Int, Int)? {
        guard data.count >= 24 else { return nil }
        let width = Int(data[16]) << 24 | Int(data[17]) << 16 | Int(data[18]) << 8 | Int(data[19])
        let height = Int(data[20]) << 24 | Int(data[21]) << 16 | Int(data[22]) << 8 | Int(data[23])
        return (width, height)
    }

    private static func requiredBrowserToolOverride(
        _ controller: QuillCodeDesktopController
    ) throws -> AgentToolExecutionOverride {
        guard let override = controller.model.visibleBrowserToolOverride else {
            throw QuillCodeDesktopSmokeFailure.browserSmokeFailed("missing visible browser tool override")
        }
        return override
    }

    private static func requiredToolResult(_ result: ToolResult?, toolName: String) throws -> ToolResult {
        guard let result else {
            throw QuillCodeDesktopSmokeFailure.browserSmokeFailed("\(toolName) was not routed")
        }
        guard result.ok else {
            throw QuillCodeDesktopSmokeFailure.browserSmokeFailed(result.error ?? "\(toolName) failed")
        }
        return result
    }

    private static func decodeSmokeOutput<Value: Decodable>(
        _ type: Value.Type,
        from result: ToolResult
    ) throws -> Value {
        guard let data = result.stdout.data(using: .utf8) else {
            throw QuillCodeDesktopSmokeFailure.browserSmokeFailed("tool output was not UTF-8")
        }
        return try JSONDecoder().decode(type, from: data)
    }

    private static func waitForDesktopRun(
        _ controller: QuillCodeDesktopController,
        previousTimelineCount: Int,
        expectedAnswer: String
    ) async throws {
        var latestTimelineCount = previousTimelineCount
        var latestAnswer = ""
        var latestSendingState = false
        for _ in 0..<1_000 {
            let timelineCount = controller.surface.transcript.timelineItems.count
            latestTimelineCount = timelineCount
            latestAnswer = controller.surface.transcript.messages.last?.text ?? ""
            latestSendingState = controller.surface.composer.isSending
            if !controller.surface.composer.isSending,
               timelineCount >= previousTimelineCount + 3,
               latestAnswer.contains(expectedAnswer) {
                return
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        throw QuillCodeDesktopSmokeFailure.timedOut(
            "expected answer \(expectedAnswer.debugDescription), latest answer \(latestAnswer.debugDescription), "
            + "isSending \(latestSendingState), timeline \(latestTimelineCount), previous \(previousTimelineCount), "
            + "latest tool input \((controller.surface.transcript.toolCards.last?.inputJSON ?? "").debugDescription)"
        )
    }

    private static func renderWorkspace(
        controller: QuillCodeDesktopController,
        renderURL: URL
    ) throws -> CGImage {
        let view = QuillCodeDesktopRootView(controller: controller)
            .frame(width: 1280, height: 900)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        renderer.isOpaque = true
        renderer.proposedSize = ProposedViewSize(width: 1280, height: 900)

        guard let image = renderer.cgImage else {
            throw QuillCodeDesktopSmokeFailure.renderFailed
        }

        let rep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw QuillCodeDesktopSmokeFailure.pngEncodingFailed
        }
        try FileManager.default.createDirectory(
            at: renderURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: renderURL, options: .atomic)
        return image
    }

    private static func renderResultEvidence(
        surface: WorkspaceSurface,
        createdFilePath: String,
        renderURL: URL
    ) throws -> CGImage {
        let view = QuillCodeSmokeResultEvidenceView(
            surface: surface,
            createdFilePath: createdFilePath
        )
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        renderer.isOpaque = true
        renderer.proposedSize = ProposedViewSize(width: 820, height: 720)

        guard let image = renderer.cgImage else {
            throw QuillCodeDesktopSmokeFailure.renderFailed
        }

        let rep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw QuillCodeDesktopSmokeFailure.pngEncodingFailed
        }
        try FileManager.default.createDirectory(
            at: renderURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: renderURL, options: .atomic)
        return image
    }

}

@MainActor
private final class SmokeBrowserSessionPresenter: DesktopBrowserSessionPresenting {
    var onSessionUpdate: (@MainActor (BrowserSessionUpdate) -> Void)?

    private var selectedTab: BrowserSessionTabSnapshot?
    private var isSessionOpen = false
    private var typedStatus = "Open"
    private var didSave = false
    private var typedLaunchDate = "TBD"
    private var didMarkDone = false
    private var typedWorkspaceKey = ""
    private var didSignIn = false

    func presentSession(_ snapshot: BrowserSessionSyncSnapshot) {
        isSessionOpen = true
        syncSession(snapshot)
    }

    func syncSession(_ snapshot: BrowserSessionSyncSnapshot) {
        guard isSessionOpen else { return }
        selectedTab = snapshot.tabs.first { $0.id == snapshot.activeTabID } ?? snapshot.tabs.first
    }

    func goBackSession(fallback snapshot: BrowserSessionSyncSnapshot) {}
    func goForwardSession(fallback snapshot: BrowserSessionSyncSnapshot) {}

    func evaluateJavaScriptInSelectedTab(_ source: String) async throws -> DesktopBrowserSessionScriptResult {
        let trimmedSource = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSource.isEmpty else { throw DesktopBrowserSessionScriptError.emptySource }
        guard let selectedTab else { throw DesktopBrowserSessionScriptError.noSelectedTab }
        emitSnapshotUpdate(for: selectedTab)
        return DesktopBrowserSessionScriptResult(
            title: page(for: selectedTab).title,
            url: selectedTab.url,
            valueDescription: scriptValue(for: selectedTab)
        )
    }

    func captureLiveDOMSnapshotInSelectedTab() async throws -> BrowserLiveDOMSnapshot {
        guard let selectedTab else { throw DesktopBrowserSessionScriptError.noSelectedTab }
        let snapshot = liveDOMSnapshot(for: selectedTab)
        onSessionUpdate?(BrowserSessionUpdate(
            tabs: [
                BrowserSessionTabUpdate(
                    id: selectedTab.id,
                    title: page(for: selectedTab).title,
                    url: selectedTab.url,
                    isActive: true,
                    liveDOMSnapshot: snapshot
                )
            ],
            activeTabID: selectedTab.id
        ))
        return snapshot
    }

    func clickInSelectedTab(selector: String) async throws -> DesktopBrowserSessionActionResult {
        let trimmedSelector = selector.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSelector.isEmpty else { throw DesktopBrowserSessionActionError.emptySelector }
        guard let selectedTab else { throw DesktopBrowserSessionActionError.noSelectedTab }
        switch page(for: selectedTab) {
        case .crm:
            guard trimmedSelector == "button[data-action='save']" else {
                throw DesktopBrowserSessionActionError.actionFailed("Smoke page has no element for \(trimmedSelector)")
            }
            didSave = true
        case .authenticated:
            guard trimmedSelector == "button[data-action='sign-in']" else {
                throw DesktopBrowserSessionActionError.actionFailed("Smoke page has no element for \(trimmedSelector)")
            }
            didSignIn = true
        case .spreadsheet:
            guard trimmedSelector == "button[data-action='mark-done']" else {
                throw DesktopBrowserSessionActionError.actionFailed("Smoke page has no element for \(trimmedSelector)")
            }
            didMarkDone = true
        }
        emitSnapshotUpdate(for: selectedTab)
        return DesktopBrowserSessionActionResult(ok: true, summary: "Clicked \(trimmedSelector)", error: nil)
    }

    func typeInSelectedTab(selector: String, text: String, submit: Bool) async throws -> DesktopBrowserSessionActionResult {
        let trimmedSelector = selector.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSelector.isEmpty else { throw DesktopBrowserSessionActionError.emptySelector }
        guard !text.isEmpty else { throw DesktopBrowserSessionActionError.emptyText }
        guard let selectedTab else { throw DesktopBrowserSessionActionError.noSelectedTab }
        switch page(for: selectedTab) {
        case .crm:
            guard trimmedSelector == "input[name='status']" else {
                throw DesktopBrowserSessionActionError.actionFailed("Smoke page has no element for \(trimmedSelector)")
            }
            typedStatus = text
        case .authenticated:
            guard trimmedSelector == "input[name='workspace-key']" else {
                throw DesktopBrowserSessionActionError.actionFailed("Smoke page has no element for \(trimmedSelector)")
            }
            typedWorkspaceKey = text
        case .spreadsheet:
            guard trimmedSelector == "[data-cell='launch-date']" else {
                throw DesktopBrowserSessionActionError.actionFailed("Smoke page has no element for \(trimmedSelector)")
            }
            typedLaunchDate = text
        }
        emitSnapshotUpdate(for: selectedTab)
        return DesktopBrowserSessionActionResult(ok: true, summary: "Typed into \(trimmedSelector)", error: nil)
    }

    func reloadSession() {}

    private var statusText: String {
        "Status: \(typedStatus); saved=\(didSave)"
    }

    private var rowStateText: String {
        "Launch checklist: \(typedLaunchDate); done=\(didMarkDone)"
    }

    private var accountStateText: String {
        let workspace = typedWorkspaceKey.isEmpty ? "none" : typedWorkspaceKey
        return "Signed \(didSignIn ? "in" : "out"); workspace=\(workspace); signed-in=\(didSignIn)"
    }

    private func scriptValue(for tab: BrowserSessionTabSnapshot) -> String {
        switch page(for: tab) {
        case .crm:
            return statusText
        case .authenticated:
            return accountStateText
        case .spreadsheet:
            return rowStateText
        }
    }

    private func liveDOMSnapshot(for tab: BrowserSessionTabSnapshot) -> BrowserLiveDOMSnapshot {
        switch page(for: tab) {
        case .crm:
            return BrowserLiveDOMSnapshot(
                finalURL: tab.url,
                title: "CRM Workflow Smoke",
                visibleText: "CRM Workflow Smoke Status \(typedStatus) \(didSave ? "Saved" : "Unsaved")",
                outline: ["H1: CRM Workflow Smoke", "Button: Save", "Field: Status"],
                html: """
                <!doctype html><title>CRM Workflow Smoke</title>
                <h1>CRM Workflow Smoke</h1>
                <input name="status" value="\(typedStatus)">
                <button data-action="save">Save</button>
                <p data-testid="status">\(statusText)</p>
                """,
                viewportDescription: "1120x760 smoke browser"
            )
        case .authenticated:
            return BrowserLiveDOMSnapshot(
                finalURL: tab.url,
                title: "Signed-In Workspace Smoke",
                visibleText: """
                Signed-In Workspace Smoke \(didSignIn ? "Signed in" : "Signed out") workspace \(typedWorkspaceKey)
                """,
                outline: [
                    "H1: Signed-In Workspace Smoke",
                    "Field: Workspace key",
                    "Button: Sign in",
                    didSignIn ? "Account: Signed in" : "Account: Signed out"
                ],
                html: """
                <!doctype html><title>Signed-In Workspace Smoke</title>
                <h1>Signed-In Workspace Smoke</h1>
                <input name="workspace-key" value="\(typedWorkspaceKey)">
                <button data-action="sign-in">Sign in</button>
                <p data-testid="account-state">\(accountStateText)</p>
                """,
                viewportDescription: "1120x760 smoke browser"
            )
        case .spreadsheet:
            return BrowserLiveDOMSnapshot(
                finalURL: tab.url,
                title: "Shared Sheet Workflow Smoke",
                visibleText: """
                Shared Sheet Workflow Smoke Launch checklist \(typedLaunchDate) \(didMarkDone ? "Done" : "Open")
                """,
                outline: [
                    "H1: Shared Sheet Workflow Smoke",
                    "Table: Launch tracker",
                    "Field: Launch date",
                    "Button: Mark done"
                ],
                html: """
                <!doctype html><title>Shared Sheet Workflow Smoke</title>
                <h1>Shared Sheet Workflow Smoke</h1>
                <table aria-label="Launch tracker">
                  <tr><td>Launch checklist</td><td><input data-cell="launch-date" value="\(typedLaunchDate)"></td></tr>
                </table>
                <button data-action="mark-done">Mark done</button>
                <p data-testid="row-state">\(rowStateText)</p>
                """,
                viewportDescription: "1120x760 smoke browser"
            )
        }
    }

    private func page(for tab: BrowserSessionTabSnapshot) -> SmokeBrowserPage {
        let url = tab.url.absoluteString
        if url.contains("browser-auth-smoke.html") { return .authenticated }
        if url.contains("browser-sheet-smoke.html") { return .spreadsheet }
        return .crm
    }

    private enum SmokeBrowserPage {
        case crm
        case authenticated
        case spreadsheet

        var title: String {
            switch self {
            case .crm:
                return "CRM Workflow Smoke"
            case .authenticated:
                return "Signed-In Workspace Smoke"
            case .spreadsheet:
                return "Shared Sheet Workflow Smoke"
            }
        }
    }

    private func emitSnapshotUpdate(for tab: BrowserSessionTabSnapshot) {
        onSessionUpdate?(BrowserSessionUpdate(
            tabs: [
                BrowserSessionTabUpdate(
                    id: tab.id,
                    title: page(for: tab).title,
                    url: tab.url,
                    isActive: true,
                    liveDOMSnapshot: liveDOMSnapshot(for: tab)
                )
            ],
            activeTabID: tab.id
        ))
    }
}

private struct OneTurnCoworkerSmokeCase {
    var taskID: Int
    var prompt: String
    var expectedToolName: String
    var expectedAnswer: String
    var artifactRelativePath: String
    var artifactExpectation: OneTurnCoworkerArtifactExpectation
}

private enum OneTurnCoworkerArtifactExpectation {
    case textContains(String)
    case png(width: Int, height: Int, minimumByteCount: Int, assertion: String)

    var assertion: String {
        switch self {
        case .textContains(let text):
            text
        case .png(_, _, _, let assertion):
            assertion
        }
    }
}

private final class SmokeAutomationNotifier: QuillCodeAutomationNotifying, @unchecked Sendable {
    private let lock = NSLock()
    private var deliveredAutomationReports: [AutomationRunReport] = []

    var automationReports: [AutomationRunReport] {
        lock.lock()
        defer { lock.unlock() }
        return deliveredAutomationReports
    }

    func deliver(_ report: AutomationRunReport) {
        lock.lock()
        deliveredAutomationReports.append(report)
        lock.unlock()
    }
}
