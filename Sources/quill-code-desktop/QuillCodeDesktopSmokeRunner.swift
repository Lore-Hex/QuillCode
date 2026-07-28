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
                taskID: 17,
                prompt: "Run `mkdir -p 'Client Files' Archive/2024-Q4 && printf 'Acme contract\\n' > 'Client Files/Acme-old.txt' && printf 'Current plan\\n' > 'Client Files/Current-plan.txt' && mv 'Client Files/Acme-old.txt' Archive/2024-Q4/Acme-old.txt && printf 'Archived Client Files/Acme-old.txt -> Archive/2024-Q4/Acme-old.txt\\nKept Client Files/Current-plan.txt\\n' > archive-readme.md && printf 'wrote archive-readme.md\\n'`",
                expectedToolName: ToolDefinition.shellRun.name,
                expectedAnswer: "wrote archive-readme.md",
                artifactRelativePath: "archive-readme.md",
                artifactExpectation: .textContains("Archive/2024-Q4/Acme-old.txt"),
                secondaryArtifacts: [
                    OneTurnCoworkerArtifactCheck(
                        relativePath: "Archive/2024-Q4/Acme-old.txt",
                        expectation: .textContains("Acme contract")
                    )
                ]
            ),
            OneTurnCoworkerSmokeCase(
                taskID: 18,
                prompt: "Run `printf 'plan,premium,deductible,out_of_pocket_max,specialist_copay,rx_tier\\nBronze,98,2500,7000,65,Tier 3\\nSilver,150,1000,4000,35,Tier 2\\nGold,225,500,2500,20,Tier 1\\n' > benefits-plan-matrix.csv && printf 'wrote benefits-plan-matrix.csv\\n'`",
                expectedToolName: ToolDefinition.shellRun.name,
                expectedAnswer: "wrote benefits-plan-matrix.csv",
                artifactRelativePath: "benefits-plan-matrix.csv",
                artifactExpectation: .textContains("Silver,150,1000,4000,35,Tier 2")
            ),
            OneTurnCoworkerSmokeCase(
                taskID: 19,
                prompt: "Run `printf 'tab,month,channel,spend,quarter\\nassumptions,FY26,target_budget,120000,all\\nmonthly,2026-01,Search,9000,Q1\\nmonthly,2026-01,Events,6000,Q1\\nmonthly,2026-02,Search,9500,Q1\\nquarter_rollup,Q1,all,24500,Q1\\n' > marketing-budget-model.csv && printf 'wrote marketing-budget-model.csv\\n'`",
                expectedToolName: ToolDefinition.shellRun.name,
                expectedAnswer: "wrote marketing-budget-model.csv",
                artifactRelativePath: "marketing-budget-model.csv",
                artifactExpectation: .textContains("quarter_rollup,Q1,all,24500,Q1")
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
                taskID: 22,
                prompt: "Run `printf 'aging_bucket,tone,invoice\\n31-60,friendly reminder,INV-104\\n61-90,payment follow-up,INV-205\\n90-plus,urgent payment plan,INV-309\\n' > collections-chase-emails.md && printf 'wrote collections-chase-emails.md\\n'`",
                expectedToolName: ToolDefinition.shellRun.name,
                expectedAnswer: "wrote collections-chase-emails.md",
                artifactRelativePath: "collections-chase-emails.md",
                artifactExpectation: .textContains("90-plus,urgent payment plan,INV-309")
            ),
            OneTurnCoworkerSmokeCase(
                taskID: 23,
                prompt: "Run `\(donorColumnSplitCommand)`",
                expectedToolName: ToolDefinition.shellRun.name,
                expectedAnswer: "wrote donors-split.csv",
                artifactRelativePath: "donors-split.csv",
                artifactExpectation: .textContains("No city state zip,,,,true")
            ),
            OneTurnCoworkerSmokeCase(
                taskID: 24,
                prompt: "Run `\(supportRepliesCommand)`",
                expectedToolName: ToolDefinition.shellRun.name,
                expectedAnswer: "wrote support-replies/ticket-001.md and support-replies/ticket-002.md",
                artifactRelativePath: "support-replies/ticket-001.md",
                artifactExpectation: .textContains("billing-access-restored-today"),
                secondaryArtifacts: [
                    OneTurnCoworkerArtifactCheck(
                        relativePath: "support-replies/ticket-002.md",
                        expectation: .textContains("corrected-csv-attached")
                    )
                ]
            ),
            OneTurnCoworkerSmokeCase(
                taskID: 25,
                prompt: "Run `\(newsletterValidationCommand)`",
                expectedToolName: ToolDefinition.shellRun.name,
                expectedAnswer: "wrote newsletter-clean.csv and newsletter-bad-rows.csv",
                artifactRelativePath: "newsletter-clean.csv",
                artifactExpectation: .textContains("+14155550100"),
                secondaryArtifacts: [
                    OneTurnCoworkerArtifactCheck(
                        relativePath: "newsletter-bad-rows.csv",
                        expectation: .textContains("invalid-email,not-a-phone")
                    )
                ]
            ),
            OneTurnCoworkerSmokeCase(
                taskID: 26,
                prompt: "Run `\(dateNormalizationCommand)`",
                expectedToolName: ToolDefinition.shellRun.name,
                expectedAnswer: "wrote members-normalized.csv",
                artifactRelativePath: "members-normalized.csv",
                artifactExpectation: .textContains("Cam,2026-07-14,text date")
            ),
            OneTurnCoworkerSmokeCase(
                taskID: 27,
                prompt: "Create a file named `delay-notice.md` that says `Subject: Delivery delay notice\\n\\nHi customer, your order is delayed until Friday because the carrier missed pickup. We are sorry for the delay and will send tracking as soon as it moves.\\n`",
                expectedToolName: ToolDefinition.fileWrite.name,
                expectedAnswer: "Wrote `delay-notice.md`.",
                artifactRelativePath: "delay-notice.md",
                artifactExpectation: .textContains("your order is delayed until Friday")
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
                taskID: 29,
                prompt: "Run `\(documentSplittingCommand)`",
                expectedToolName: ToolDefinition.shellRun.name,
                expectedAnswer: "wrote exhibits/Exhibit-A-Purchase-Agreement.pdf and exhibits/Exhibit-B-Disclosure-Schedule.pdf",
                artifactRelativePath: "exhibits/Exhibit-A-Purchase-Agreement.pdf",
                artifactExpectation: .textContains("Exhibit A - Purchase Agreement"),
                secondaryArtifacts: [
                    OneTurnCoworkerArtifactCheck(
                        relativePath: "exhibits/Exhibit-B-Disclosure-Schedule.pdf",
                        expectation: .textContains("Exhibit B - Disclosure Schedule")
                    ),
                    OneTurnCoworkerArtifactCheck(
                        relativePath: "exhibits/exhibit-index.csv",
                        expectation: .textContains("B,Disclosure Schedule,Exhibit-B-Disclosure-Schedule.pdf")
                    )
                ]
            ),
            OneTurnCoworkerSmokeCase(
                taskID: 30,
                prompt: "Run `\(expenseCategorizationCommand)`",
                expectedToolName: ToolDefinition.shellRun.name,
                expectedAnswer: "wrote amex_q3-categorized.csv and amex_q3-review.csv",
                artifactRelativePath: "amex_q3-categorized.csv",
                artifactExpectation: .textContains("2026-07-18,Adobe,79.99,Software,6100"),
                secondaryArtifacts: [
                    OneTurnCoworkerArtifactCheck(
                        relativePath: "amex_q3-review.csv",
                        expectation: .textContains("2026-07-22,Unknown Vendor,312.00,needs_review")
                    )
                ]
            ),
            OneTurnCoworkerSmokeCase(
                taskID: 31,
                prompt: "Run `\(financeVarianceCommand)`",
                expectedToolName: ToolDefinition.shellRun.name,
                expectedAnswer: "wrote june-variance-pack.csv",
                artifactRelativePath: "june-variance-pack.csv",
                artifactExpectation: .textContains("Support,42000,36500,15.1%,over,billing backlog temporary contractors")
            ),
            OneTurnCoworkerSmokeCase(
                taskID: 32,
                prompt: "Run `\(folderOrganizationCommand)`",
                expectedToolName: ToolDefinition.shellRun.name,
                expectedAnswer: "wrote downloads-organization-report.md",
                artifactRelativePath: "downloads-organization-report.md",
                artifactExpectation: .textContains("Junk pile: Downloads/Junk/installer.tmp"),
                secondaryArtifacts: [
                    OneTurnCoworkerArtifactCheck(
                        relativePath: "Downloads/Receipts/receipt-1042.pdf",
                        expectation: .textContains("Receipt 1042")
                    ),
                    OneTurnCoworkerArtifactCheck(
                        relativePath: "Downloads/Screenshots/screenshot-launch.png",
                        expectation: .textContains("Screenshot launch")
                    )
                ]
            ),
            OneTurnCoworkerSmokeCase(
                taskID: 33,
                prompt: "Run `\(followUpSequenceCommand)`",
                expectedToolName: ToolDefinition.shellRun.name,
                expectedAnswer: "wrote prospect-followups/ada-day-1.md, prospect-followups/ada-day-3.md, and prospect-followups/ada-day-7.md",
                artifactRelativePath: "prospect-followups/ada-day-1.md",
                artifactExpectation: .textContains("Great talking about the warehouse pilot"),
                secondaryArtifacts: [
                    OneTurnCoworkerArtifactCheck(
                        relativePath: "prospect-followups/ada-day-3.md",
                        expectation: .textContains("bring the warehouse checklist")
                    ),
                    OneTurnCoworkerArtifactCheck(
                        relativePath: "prospect-followups/ben-day-1.md",
                        expectation: .textContains("pricing analytics dashboard")
                    )
                ]
            ),
            OneTurnCoworkerSmokeCase(
                taskID: 34,
                prompt: "Run `\(forecastReviewCommand)`",
                expectedToolName: ToolDefinition.shellRun.name,
                expectedAnswer: "wrote forecast-review.md",
                artifactRelativePath: "forecast-review.md",
                artifactExpectation: .textContains("Flag: Q3 Upside assumes 42 pct close rate"),
                secondaryArtifacts: [
                    OneTurnCoworkerArtifactCheck(
                        relativePath: "pipeline-forecast.xlsx",
                        expectation: .textContains("Q3 Upside,1200000,42 pct")
                    )
                ]
            ),
            OneTurnCoworkerSmokeCase(
                taskID: 35,
                prompt: "Run `\(funnelAnalysisCommand)`",
                expectedToolName: ToolDefinition.shellRun.name,
                expectedAnswer: "wrote q2-funnel-summary.md",
                artifactRelativePath: "q2-funnel-summary.md",
                artifactExpectation: .textContains("Biggest drop-off: Demo to Proposal"),
                secondaryArtifacts: [
                    OneTurnCoworkerArtifactCheck(
                        relativePath: "q2-funnel-conversions.csv",
                        expectation: .textContains("Demo to Proposal,40 pct,14")
                    )
                ]
            ),
            OneTurnCoworkerSmokeCase(
                taskID: 36,
                prompt: "Run `\(vendorDeduplicationCommand)`",
                expectedToolName: ToolDefinition.shellRun.name,
                expectedAnswer: "wrote vendor-name-mapping.csv and ap-vendors-standardized.csv",
                artifactRelativePath: "vendor-name-mapping.csv",
                artifactExpectation: .textContains("ACME, Inc.,Acme"),
                secondaryArtifacts: [
                    OneTurnCoworkerArtifactCheck(
                        relativePath: "ap-vendors-standardized.csv",
                        expectation: .textContains("Acme,3,merged")
                    )
                ]
            ),
            OneTurnCoworkerSmokeCase(
                taskID: 37,
                prompt: "Run `\(jobDescriptionCommand)`",
                expectedToolName: ToolDefinition.shellRun.name,
                expectedAnswer: "wrote senior-csm-job-description.md",
                artifactRelativePath: "senior-csm-job-description.md",
                artifactExpectation: .textContains("Senior Customer Success Manager"),
                secondaryArtifacts: [
                    OneTurnCoworkerArtifactCheck(
                        relativePath: "senior-csm-screening-questions.md",
                        expectation: .textContains("at-risk account")
                    )
                ]
            ),
            OneTurnCoworkerSmokeCase(
                taskID: 38,
                prompt: "Run `\(interviewScorecardCommand)`",
                expectedToolName: ToolDefinition.shellRun.name,
                expectedAnswer: "wrote sales-ops-analyst-scorecard.md",
                artifactRelativePath: "sales-ops-analyst-scorecard.md",
                artifactExpectation: .textContains("Anchored 1-4 ratings"),
                secondaryArtifacts: [
                    OneTurnCoworkerArtifactCheck(
                        relativePath: "sales-ops-analyst-interview-questions.md",
                        expectation: .textContains("pipeline hygiene")
                    )
                ]
            ),
            OneTurnCoworkerSmokeCase(
                taskID: 39,
                prompt: "Run `\(newsletterImagePrepCommand)`",
                expectedToolName: ToolDefinition.shellRun.name,
                expectedAnswer: "wrote july-image-prep-report.md",
                artifactRelativePath: "july-image-prep-report.md",
                artifactExpectation: .textContains("ready/hero-launch.png <= 1600px and under 500KB"),
                secondaryArtifacts: [
                    OneTurnCoworkerArtifactCheck(
                        relativePath: "Newsletter/July/ready/hero-launch.png",
                        expectation: .png(
                            width: 320,
                            height: 200,
                            minimumByteCount: 700,
                            assertion: "PNG ready/hero-launch.png under 500KB and <=1600px wide"
                        )
                    ),
                    OneTurnCoworkerArtifactCheck(
                        relativePath: "Newsletter/July/originals/IMG_0001.png",
                        expectation: .png(
                            width: 320,
                            height: 200,
                            minimumByteCount: 700,
                            assertion: "PNG originals/IMG_0001.png preserved"
                        )
                    )
                ]
            ),
            OneTurnCoworkerSmokeCase(
                taskID: 40,
                prompt: "Run `printf '<h1>Finance KPI Dashboard</h1><p>Revenue USD 1.24M</p><p>Churn 3.1 percent</p><p>Headcount 58</p><svg><polyline points=0,40 60,20 120,8></polyline></svg>\\n' > finance-kpi-dashboard.html && printf 'wrote finance-kpi-dashboard.html\\n'`",
                expectedToolName: ToolDefinition.shellRun.name,
                expectedAnswer: "wrote finance-kpi-dashboard.html",
                artifactRelativePath: "finance-kpi-dashboard.html",
                artifactExpectation: .textContains("Finance KPI Dashboard")
            ),
            OneTurnCoworkerSmokeCase(
                taskID: 41,
                prompt: "Run `\(launchChecklistCommand)`",
                expectedToolName: ToolDefinition.shellRun.name,
                expectedAnswer: "wrote march-pricing-go-live-checklist.md",
                artifactRelativePath: "march-pricing-go-live-checklist.md",
                artifactExpectation: .textContains("Legal | Priya | 2026-03-04"),
                secondaryArtifacts: [
                    OneTurnCoworkerArtifactCheck(
                        relativePath: "march-pricing-launch-brief.md",
                        expectation: .textContains("March pricing launch")
                    )
                ]
            ),
            OneTurnCoworkerSmokeCase(
                taskID: 42,
                prompt: "Run \(safetyGuideLocalizationCommand)",
                expectedToolName: ToolDefinition.shellRun.name,
                expectedAnswer: "wrote safety-guide-es.pdf and safety-guide-pt.pdf",
                artifactRelativePath: "safety-guide-es.pdf",
                artifactExpectation: .textContains("Safety_Guide_WARNING_BOX_ES_1_2"),
                secondaryArtifacts: [
                    OneTurnCoworkerArtifactCheck(
                        relativePath: "safety-guide-pt.pdf",
                        expectation: .textContains("Safety_Guide_WARNING_BOX_PT_1_2")
                    )
                ]
            ),
            OneTurnCoworkerSmokeCase(
                taskID: 43,
                prompt: "Run `printf 'week,theme,type,title,owner\\n2026-Q3-W01,Migration,blog,Migration planning checklist,Ada\\n2026-Q3-W01,Migration,webinar,Modernize legacy data,Ben\\n2026-Q3-W01,Migration,social,Four migration mistakes,Cam\\n2026-Q3-W02,Security,blog,Security review guide,Ada\\n2026-Q3-W02,Security,social,Audit-ready teams,Cam\\n' > q3-content-calendar.csv && printf 'wrote q3-content-calendar.csv\\n'`",
                expectedToolName: ToolDefinition.shellRun.name,
                expectedAnswer: "wrote q3-content-calendar.csv",
                artifactRelativePath: "q3-content-calendar.csv",
                artifactExpectation: .textContains("2026-Q3-W01,Migration,webinar,Modernize legacy data,Ben")
            ),
            OneTurnCoworkerSmokeCase(
                taskID: 44,
                prompt: "Run `\(zoomTranscriptNotesCommand)`",
                expectedToolName: ToolDefinition.shellRun.name,
                expectedAnswer: "wrote zoom-meeting-notes.md",
                artifactRelativePath: "zoom-meeting-notes.md",
                artifactExpectation: .textContains("Decision: Ship onboarding checklist by 2026-07-21"),
                secondaryArtifacts: [
                    OneTurnCoworkerArtifactCheck(
                        relativePath: "zoom-0714.txt",
                        expectation: .textContains("Raw Zoom transcript 2026-07-14")
                    )
                ]
            ),
            OneTurnCoworkerSmokeCase(
                taskID: 45,
                prompt: "Run `\(meetingRecapCommand)`",
                expectedToolName: ToolDefinition.shellRun.name,
                expectedAnswer: "wrote board-prep-recap-email.md",
                artifactRelativePath: "board-prep-recap-email.md",
                artifactExpectation: .textContains("Priya | Final board deck | 2026-08-02"),
                secondaryArtifacts: [
                    OneTurnCoworkerArtifactCheck(
                        relativePath: "board-prep-call.txt",
                        expectation: .textContains("Raw board prep call transcript")
                    )
                ]
            ),
            OneTurnCoworkerSmokeCase(
                taskID: 46,
                prompt: "Run \(maintenanceNoticeCommand)",
                expectedToolName: ToolDefinition.shellRun.name,
                expectedAnswer: "wrote maintenance-notice-variants.md",
                artifactRelativePath: "maintenance-notice-variants.md",
                artifactExpectation: .textContains("Enterprise admins: Scheduled maintenance starts 2026-08-14 22:00 UTC"),
                secondaryArtifacts: [
                    OneTurnCoworkerArtifactCheck(
                        relativePath: "maintenance-window-notice.md",
                        expectation: .textContains("Original maintenance window notice")
                    )
                ]
            ),
            OneTurnCoworkerSmokeCase(
                taskID: 47,
                prompt: "Run \(obligationTrackingCommand)",
                expectedToolName: ToolDefinition.shellRun.name,
                expectedAnswer: "wrote acme-sow-obligations.csv",
                artifactRelativePath: "acme-sow-obligations.csv",
                artifactExpectation: .textContains("2026-09-15,2026-09-01,Acme kickoff workshop,Ada"),
                secondaryArtifacts: [
                    OneTurnCoworkerArtifactCheck(
                        relativePath: "Acme-SOW.pdf",
                        expectation: .textContains("Acme SOW source")
                    )
                ]
            ),
            OneTurnCoworkerSmokeCase(
                taskID: 48,
                prompt: "Run `printf 'view,rep,region,quarter,revenue\\nby_rep,Ada,All,All,184000\\nby_rep,Ben,All,All,132000\\nby_region,All,West,All,201000\\nby_region,All,East,All,115000\\nby_quarter,All,All,Q1,146000\\nby_quarter,All,All,Q2,170000\\ntop_deal,Ada,West,Q2,92000\\n' > sales-pivot-summary.csv && printf 'wrote sales-pivot-summary.csv\\n'`",
                expectedToolName: ToolDefinition.shellRun.name,
                expectedAnswer: "wrote sales-pivot-summary.csv",
                artifactRelativePath: "sales-pivot-summary.csv",
                artifactExpectation: .textContains("top_deal,Ada,West,Q2,92000")
            ),
            OneTurnCoworkerSmokeCase(
                taskID: 49,
                prompt: "Run \(raciChartCommand)",
                expectedToolName: ToolDefinition.shellRun.name,
                expectedAnswer: "wrote erp-migration-raci.csv",
                artifactRelativePath: "erp-migration-raci.csv",
                artifactExpectation: .textContains("Data migration,Ada,Ben,Cam,Dee"),
                secondaryArtifacts: [
                    OneTurnCoworkerArtifactCheck(
                        relativePath: "stakeholders.csv",
                        expectation: .textContains("Ada,Migration Lead")
                    ),
                    OneTurnCoworkerArtifactCheck(
                        relativePath: "phase-plan.md",
                        expectation: .textContains("Data migration")
                    )
                ]
            ),
            OneTurnCoworkerSmokeCase(
                taskID: 50,
                prompt: "Run \(invoiceReconciliationCommand)",
                expectedToolName: ToolDefinition.shellRun.name,
                expectedAnswer: "wrote invoice-reconciliation.csv",
                artifactRelativePath: "invoice-reconciliation.csv",
                artifactExpectation: .textContains("INV-1002,1200,0,unpaid"),
                secondaryArtifacts: [
                    OneTurnCoworkerArtifactCheck(
                        relativePath: "open_invoices.csv",
                        expectation: .textContains("INV-1003,Cedar,900")
                    ),
                    OneTurnCoworkerArtifactCheck(
                        relativePath: "november-bank.csv",
                        expectation: .textContains("INV-1003,900")
                    )
                ]
            ),
            OneTurnCoworkerSmokeCase(
                taskID: 51,
                prompt: "Run \(redlineAnalysisCommand)",
                expectedToolName: ToolDefinition.shellRun.name,
                expectedAnswer: "wrote amendment-redline-impact.csv",
                artifactRelativePath: "amendment-redline-impact.csv",
                artifactExpectation: .textContains("Limitation of liability,cap increased from 12 months fees to 24 months fees,raises maximum exposure"),
                secondaryArtifacts: [
                    OneTurnCoworkerArtifactCheck(
                        relativePath: "executed-msa.pdf",
                        expectation: .textContains("Executed MSA baseline")
                    ),
                    OneTurnCoworkerArtifactCheck(
                        relativePath: "vendor-amendment-2.pdf",
                        expectation: .textContains("Vendor Amendment Two")
                    )
                ]
            ),
            OneTurnCoworkerSmokeCase(
                taskID: 52,
                prompt: "Run `printf '# August 2026 Release Notes\\n\\n## Billing\\n- Customers can now export invoices from the billing portal.\\n\\n## Collaboration\\n- Team comments now refresh without reloading the page.\\n\\n## Admin\\n- Workspace owners can see seat-change history.\\n' > release-notes-2026-08.md && printf 'wrote release-notes-2026-08.md\\n'`",
                expectedToolName: ToolDefinition.shellRun.name,
                expectedAnswer: "wrote release-notes-2026-08.md",
                artifactRelativePath: "release-notes-2026-08.md",
                artifactExpectation: .textContains("## Collaboration")
            ),
            OneTurnCoworkerSmokeCase(
                taskID: 53,
                prompt: "Run \(rfpComplianceMatrixCommand)",
                expectedToolName: ToolDefinition.shellRun.name,
                expectedAnswer: "wrote rfp-compliance-matrix.csv",
                artifactRelativePath: "rfp-compliance-matrix.csv",
                artifactExpectation: .textContains("3.2,shall encrypt data at rest,,Security"),
                secondaryArtifacts: [
                    OneTurnCoworkerArtifactCheck(
                        relativePath: "RFP-2026-DOT.pdf",
                        expectation: .textContains("RFP 2026 DOT source")
                    )
                ]
            ),
            OneTurnCoworkerSmokeCase(
                taskID: 54,
                prompt: "Run \(riskRegisterCommand)",
                expectedToolName: ToolDefinition.shellRun.name,
                expectedAnswer: "wrote project-risk-register.csv",
                artifactRelativePath: "project-risk-register.csv",
                artifactExpectation: .textContains("Data migration delay,4,5,stage dry runs weekly,Ben"),
                secondaryArtifacts: [
                    OneTurnCoworkerArtifactCheck(
                        relativePath: "project-charter.pdf",
                        expectation: .textContains("Project charter source")
                    )
                ]
            ),
            OneTurnCoworkerSmokeCase(
                taskID: 55,
                prompt: "Run \(roadmapDraftingCommand)",
                expectedToolName: ToolDefinition.shellRun.name,
                expectedAnswer: "wrote roadmap.md",
                artifactRelativePath: "roadmap.md",
                artifactExpectation: .textContains("Theme: Retention-led Q3"),
                secondaryArtifacts: [
                    OneTurnCoworkerArtifactCheck(
                        relativePath: "Q3-OKRs.docx",
                        expectation: .textContains("Q3 OKR source")
                    )
                ]
            ),
            OneTurnCoworkerSmokeCase(
                taskID: 56,
                prompt: "Run \(salesProposalCommand)",
                expectedToolName: ToolDefinition.shellRun.name,
                expectedAnswer: "wrote northwind-logistics-proposal.md",
                artifactRelativePath: "northwind-logistics-proposal.md",
                artifactExpectation: .textContains("Northwind Logistics proposal"),
                secondaryArtifacts: [
                    OneTurnCoworkerArtifactCheck(
                        relativePath: "discovery-call-notes.md",
                        expectation: .textContains("Northwind Logistics discovery")
                    ),
                    OneTurnCoworkerArtifactCheck(
                        relativePath: "pricing-sheet.xlsx",
                        expectation: .textContains("approved pricing tiers")
                    )
                ]
            ),
            OneTurnCoworkerSmokeCase(
                taskID: 57,
                prompt: "Run \(salesOnePagerCommand)",
                expectedToolName: ToolDefinition.shellRun.name,
                expectedAnswer: "wrote customer-leave-behind.md",
                artifactRelativePath: "customer-leave-behind.md",
                artifactExpectation: .textContains("Three proof points"),
                secondaryArtifacts: [
                    OneTurnCoworkerArtifactCheck(
                        relativePath: "product-deck-20-slides.pptx",
                        expectation: .textContains("20 slide product deck source")
                    ),
                    OneTurnCoworkerArtifactCheck(
                        relativePath: "approved-pricing.csv",
                        expectation: .textContains("approved pricing")
                    )
                ]
            ),
            OneTurnCoworkerSmokeCase(
                taskID: 58,
                prompt: "Run \(scannedPensionExtractionCommand)",
                expectedToolName: ToolDefinition.shellRun.name,
                expectedAnswer: "wrote pension-vesting-retirement-table.csv",
                artifactRelativePath: "pension-vesting-retirement-table.csv",
                artifactExpectation: .textContains("early_retirement_reduction,age60,70pct"),
                secondaryArtifacts: [
                    OneTurnCoworkerArtifactCheck(
                        relativePath: "pension-plan-1994-scanned.pdf",
                        expectation: .textContains("image-only pension booklet source")
                    )
                ]
            ),
            OneTurnCoworkerSmokeCase(
                taskID: 59,
                prompt: "Run \(supportTriageCommand)",
                expectedToolName: ToolDefinition.shellRun.name,
                expectedAnswer: "wrote zendesk-theme-triage.csv",
                artifactRelativePath: "zendesk-theme-triage.csv",
                artifactExpectation: .textContains("billing_access,3,2h15m,ZD-101 ZD-104 ZD-108"),
                secondaryArtifacts: [
                    OneTurnCoworkerArtifactCheck(
                        relativePath: "zendesk-export.csv",
                        expectation: .textContains("ZD-101,billing_access")
                    )
                ]
            ),
            OneTurnCoworkerSmokeCase(
                taskID: 60,
                prompt: "Run \(billingSupportMacrosCommand)",
                expectedToolName: ToolDefinition.shellRun.name,
                expectedAnswer: "wrote billing-support-macros.md",
                artifactRelativePath: "billing-support-macros.md",
                artifactExpectation: .textContains("Macro 6 refund timing apology variant"),
                secondaryArtifacts: [
                    OneTurnCoworkerArtifactCheck(
                        relativePath: "existing-macros.md",
                        expectation: .textContains("Tone sample")
                    )
                ]
            ),
            OneTurnCoworkerSmokeCase(
                taskID: 61,
                prompt: "Run \(npsSurveyAnalysisCommand)",
                expectedToolName: ToolDefinition.shellRun.name,
                expectedAnswer: "wrote nps-plan-tier-summary.csv",
                artifactRelativePath: "nps-plan-tier-summary.csv",
                artifactExpectation: .textContains("Enterprise,67,3,2,1"),
                secondaryArtifacts: [
                    OneTurnCoworkerArtifactCheck(
                        relativePath: "customer-survey-q2.csv",
                        expectation: .textContains("survey export q2")
                    ),
                    OneTurnCoworkerArtifactCheck(
                        relativePath: "nps-detractor-complaints.md",
                        expectation: .textContains("complaint_1,Reporting is slow")
                    )
                ]
            ),
            OneTurnCoworkerSmokeCase(
                taskID: 62,
                prompt: "Run \(workBreakdownCommand)",
                expectedToolName: ToolDefinition.shellRun.name,
                expectedAnswer: "wrote wbs.xlsx",
                artifactRelativePath: "wbs.xlsx",
                artifactExpectation: .textContains("Implementation,Onboarding checklist,Ada,5d"),
                secondaryArtifacts: [
                    OneTurnCoworkerArtifactCheck(
                        relativePath: "team-roster.csv",
                        expectation: .textContains("Ada,Product")
                    )
                ]
            ),
            OneTurnCoworkerSmokeCase(
                taskID: 63,
                prompt: "Run \(timelineBuildingCommand)",
                expectedToolName: ToolDefinition.shellRun.name,
                expectedAnswer: "wrote timeline.xlsx",
                artifactRelativePath: "timeline.xlsx",
                artifactExpectation: .textContains("Launch readiness,2026-10-20,2026-11-03,14d"),
                secondaryArtifacts: [
                    OneTurnCoworkerArtifactCheck(
                        relativePath: "milestones.csv",
                        expectation: .textContains("Launch,2026-11-03")
                    )
                ]
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
            for secondaryArtifact in smokeCase.secondaryArtifacts {
                let secondaryURL = root.workspace.appendingPathComponent(secondaryArtifact.relativePath)
                try verifyOneTurnCoworkerArtifact(
                    secondaryArtifact.expectation,
                    artifact: secondaryURL,
                    taskID: smokeCase.taskID
                )
            }

            reports.append(QuillCodeDesktopOneTurnCoworkerSmokeCaseReport(
                taskID: smokeCase.taskID,
                prompt: smokeCase.prompt,
                toolName: smokeCase.expectedToolName,
                artifactPath: artifact.path,
                artifactContains: smokeCase.artifactExpectation.assertion,
                secondaryArtifacts: smokeCase.secondaryArtifacts.map { secondaryArtifact in
                    [
                        "artifactPath": root.workspace
                            .appendingPathComponent(secondaryArtifact.relativePath)
                            .path,
                        "artifactContains": secondaryArtifact.expectation.assertion
                    ]
                },
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

    private static var newsletterValidationCommand: String {
        let sourceCSV = "email,phone\\nvalid@example.com,(415) 555-0100\\ninvalid-email,not-a-phone\\nmissingphone@example.com,\\n"
        let cleanCSV = "email,phone_e164\\nvalid@example.com,+14155550100\\n"
        let badRowsCSV = "email,phone,reason\\ninvalid-email,not-a-phone,invalid email and phone\\nmissingphone@example.com,,missing phone\\n"
        return """
        python3 -c "print((__import__('pathlib').Path('newsletter_list.csv').write_text('\(sourceCSV)'),__import__('pathlib').Path('newsletter-clean.csv').write_text('\(cleanCSV)'),__import__('pathlib').Path('newsletter-bad-rows.csv').write_text('\(badRowsCSV)'),'wrote newsletter-clean.csv and newsletter-bad-rows.csv')[-1])"
        """
    }

    private static var donorColumnSplitCommand: String {
        let donorsCSV = "name_address\\nAda Lovelace|12 Market St, Boston, MA 02110\\nGrace Hopper|1 Navy Way, Arlington, VA 22202\\nMalformed Donor|No city state zip\\n"
        let splitCSV = "first,last,street,city,state,zip,needs_review\\nAda,Lovelace,12 Market St,Boston,MA,02110,false\\nGrace,Hopper,1 Navy Way,Arlington,VA,22202,false\\nMalformed,Donor,No city state zip,,,,true\\n"
        return """
        python3 -c "print((__import__('pathlib').Path('donors.csv').write_text('\(donorsCSV)'),__import__('pathlib').Path('donors-split.csv').write_text('\(splitCSV)'),'wrote donors-split.csv')[-1])"
        """
    }

    private static var supportRepliesCommand: String {
        return """
        mkdir -p support-replies && printf ticket-001-billing-access-restored-today > support-replies/ticket-001.md && printf ticket-002-corrected-csv-attached > support-replies/ticket-002.md && printf 'wrote support-replies/ticket-001.md and support-replies/ticket-002.md\\n'
        """
    }

    private static var dateNormalizationCommand: String {
        return """
        printf 'member,date_joined,source_format\\nAda,2026-07-04,US\\nBen,2026-04-07,EU\\nCam,2026-07-14,text date\\n' > members-normalized.csv && printf 'wrote members-normalized.csv\\n'
        """
    }

    private static var documentSplittingCommand: String {
        return """
        mkdir -p exhibits && printf 'Exhibit A - Purchase Agreement\\n' > exhibits/Exhibit-A-Purchase-Agreement.pdf && printf 'Exhibit B - Disclosure Schedule\\n' > exhibits/Exhibit-B-Disclosure-Schedule.pdf && printf 'exhibit,title,file\\nA,Purchase Agreement,Exhibit-A-Purchase-Agreement.pdf\\nB,Disclosure Schedule,Exhibit-B-Disclosure-Schedule.pdf\\n' > exhibits/exhibit-index.csv && printf 'wrote exhibits/Exhibit-A-Purchase-Agreement.pdf and exhibits/Exhibit-B-Disclosure-Schedule.pdf\\n'
        """
    }

    private static var expenseCategorizationCommand: String {
        return """
        printf 'date,vendor,amount,category,gl_code\\n2026-07-18,Adobe,79.99,Software,6100\\n2026-08-03,Delta,428.10,Travel,6500\\n2026-09-12,Staples,54.20,Office Supplies,6200\\n' > amex_q3-categorized.csv && printf 'date,vendor,amount,status\\n2026-07-22,Unknown Vendor,312.00,needs_review\\n' > amex_q3-review.csv && printf 'wrote amex_q3-categorized.csv and amex_q3-review.csv\\n'
        """
    }

    private static var financeVarianceCommand: String {
        let varianceCSV = "cost_center,actual,budget,variance_pct,status,explanation\\nEngineering,118000,112000,5.4%,within,contractor timing within tolerance\\nSupport,42000,36500,15.1%,over,billing backlog temporary contractors\\nMarketing,27800,32000,-13.1%,under,event spend moved to July\\n"
        return """
        python3 -c "print((__import__('pathlib').Path('june-variance-pack.csv').write_text('\(varianceCSV)'),'wrote june-variance-pack.csv')[-1])"
        """
    }

    private static var folderOrganizationCommand: String {
        return """
        mkdir -p Downloads && printf 'Receipt 1042\\n' > Downloads/receipt-1042.pdf && printf 'Screenshot launch\\n' > Downloads/screenshot-launch.png && printf 'Old temp installer\\n' > Downloads/installer.tmp && mkdir -p Downloads/Installers Downloads/Receipts Downloads/'Client Files' Downloads/Screenshots Downloads/Junk && mv Downloads/receipt-1042.pdf Downloads/Receipts/receipt-1042.pdf && mv Downloads/screenshot-launch.png Downloads/Screenshots/screenshot-launch.png && mv Downloads/installer.tmp Downloads/Junk/installer.tmp && printf 'Moved receipt-1042.pdf to Downloads/Receipts\\nMoved screenshot-launch.png to Downloads/Screenshots\\nJunk pile: Downloads/Junk/installer.tmp\\nNo files deleted.\\n' > downloads-organization-report.md && printf 'wrote downloads-organization-report.md\\n'
        """
    }

    private static var followUpSequenceCommand: String {
        return """
        mkdir -p prospect-followups && printf 'Great talking about the warehouse pilot\\n' > prospect-followups/ada-day-1.md && printf 'bring the warehouse checklist\\n' > prospect-followups/ada-day-3.md && printf 'day seven pilot close\\n' > prospect-followups/ada-day-7.md && printf 'pricing analytics dashboard\\n' > prospect-followups/ben-day-1.md && printf 'wrote prospect-followups/ada-day-1.md, prospect-followups/ada-day-3.md, and prospect-followups/ada-day-7.md\\n'
        """
    }

    private static var forecastReviewCommand: String {
        return """
        printf 'scenario,forecast,assumed_close\\nQ3 Base,820000,30 pct\\nQ3 Upside,1200000,42 pct\\n' > pipeline-forecast.xlsx && printf 'quarter,close_rate\\nQ1,29 pct\\nQ2,31 pct\\nQ3,28 pct\\nQ4,33 pct\\nQ5,30 pct\\nQ6,31 pct\\n' > historical-close-rates.csv && printf 'Forecast review\\nFlag: Q3 Upside assumes 42 pct close rate vs six-quarter average 30 pct.\\nBoard note: use Q3 Base unless late-stage conversion improves.\\n' > forecast-review.md && printf 'wrote forecast-review.md\\n'
        """
    }

    private static var funnelAnalysisCommand: String {
        return """
        printf 'stage,count,median_days\\nLead,100,3\\nQualified,70,6\\nDemo,50,9\\nProposal,20,14\\nClosed Won,8,21\\n' > hubspot-deals-export.xlsx && printf 'step,conversion,median_days\\nLead to Qualified,70 pct,6\\nQualified to Demo,71 pct,9\\nDemo to Proposal,40 pct,14\\nProposal to Closed Won,40 pct,21\\n' > q2-funnel-conversions.csv && printf 'Q2 funnel summary\\nBiggest drop-off: Demo to Proposal at 40 pct conversion.\\nMedian days per stage: Lead 3, Qualified 6, Demo 9, Proposal 14, Closed Won 21.\\n' > q2-funnel-summary.md && printf 'wrote q2-funnel-summary.md\\n'
        """
    }

    private static var vendorDeduplicationCommand: String {
        return """
        printf 'vendor_name,invoice_count\\nAcme Inc,1\\nACME, Inc.,1\\nAcme Incorporated,1\\nNorthwind LLC,2\\n' > ap_vendors.csv && printf 'raw_vendor,standard_vendor\\nAcme Inc,Acme\\nACME, Inc.,Acme\\nAcme Incorporated,Acme\\nNorthwind LLC,Northwind\\n' > vendor-name-mapping.csv && printf 'standard_vendor,source_rows,status\\nAcme,3,merged\\nNorthwind,1,unchanged\\n' > ap-vendors-standardized.csv && printf 'wrote vendor-name-mapping.csv and ap-vendors-standardized.csv\\n'
        """
    }

    private static var jobDescriptionCommand: String {
        return """
        printf CSM > hiring-notes.md && printf 'Senior Customer Success Manager' > senior-csm-job-description.md && printf 'at-risk account' > senior-csm-screening-questions.md && printf 'wrote senior-csm-job-description.md\\n'
        """
    }

    private static var interviewScorecardCommand: String {
        return """
        printf 'Sales Ops Analyst JD\\nPanel: RevOps, Sales, Finance\\n' > sales-ops-analyst-loop.md && printf 'Sales Ops Analyst Scorecard\\nAnchored 1-4 ratings\\nCompetency: pipeline hygiene\\nCompetency: forecasting accuracy\\n' > sales-ops-analyst-scorecard.md && printf 'pipeline hygiene question\\nforecasting question\\n' > sales-ops-analyst-interview-questions.md && printf 'wrote sales-ops-analyst-scorecard.md\\n'
        """
    }

    private static var newsletterImagePrepCommand: String {
        return """
        mkdir -p Newsletter/July/originals Newsletter/July/ready && printf 'source,caption\\nIMG_0001.png,hero launch\\n' > Newsletter/July/captions.csv && cp regional-revenue-chart.png Newsletter/July/originals/IMG_0001.png && cp regional-revenue-chart.png Newsletter/July/ready/hero-launch.png && printf 'ready/hero-launch.png <= 1600px and under 500KB\\noriginals kept in Newsletter/July/originals\\nnames came from captions.csv\\n' > july-image-prep-report.md && printf 'wrote july-image-prep-report.md\\n'
        """
    }

    private static var launchChecklistCommand: String {
        return """
        printf 'March pricing launch\\nLaunch date: 2026-03-18\\n' > march-pricing-launch-brief.md && printf '# March Pricing Go-Live Checklist\\n\\n| Area | Owner | Due date | Item |\\n| Legal | Priya | 2026-03-04 | Approve updated terms |\\n| Support | Marco | 2026-03-08 | Publish escalation macros |\\n| Docs | Lena | 2026-03-10 | Update pricing FAQ |\\n| Comms | Theo | 2026-03-12 | Send customer notice |\\n' > march-pricing-go-live-checklist.md && printf 'wrote march-pricing-go-live-checklist.md\\n'
        """
    }

    private static var safetyGuideLocalizationCommand: String {
        return """
        echo Safety_Guide_WARNING_BOX_ES_1_2>safety-guide-es.pdf&&echo Safety_Guide_WARNING_BOX_PT_1_2>safety-guide-pt.pdf&&echo wrote safety-guide-es.pdf and safety-guide-pt.pdf
        """
    }

    private static var zoomTranscriptNotesCommand: String {
        return """
        printf 'Raw Zoom transcript 2026-07-14\\nAda: decision ship onboarding checklist by July 21\\nBen owns support macros due July 18\\nCam owns customer FAQ due July 19\\nLena owns training deck due July 22\\n' > zoom-0714.txt && printf '# Meeting Notes\\n\\n## Five-bullet summary\\n- Onboarding checklist is the launch blocker.\\n- Support macros need owner review.\\n- Customer FAQ needs final examples.\\n- Training deck follows the FAQ.\\n- Risks and due dates are tracked below.\\n\\n## Decisions\\n- Decision: Ship onboarding checklist by 2026-07-21\\n\\n## Owners and due dates\\n- Ben | Support macros | 2026-07-18\\n- Cam | Customer FAQ | 2026-07-19\\n- Lena | Training deck | 2026-07-22\\n' > zoom-meeting-notes.md && printf 'wrote zoom-meeting-notes.md\\n'
        """
    }

    private static var meetingRecapCommand: String {
        return """
        printf 'Raw board prep call transcript\\nPriya will send final board deck by August 2\\nMarco will refresh ARR bridge by August 1\\nAda will confirm customer quote approvals by July 31\\n' > board-prep-call.txt && printf 'Subject: Board prep recap and commitments\\n\\nHi team,\\n\\nHere are the commitments from the board prep call.\\n\\n| Owner | Commitment | Due date |\\n| Priya | Final board deck | 2026-08-02 |\\n| Marco | Refresh ARR bridge | 2026-08-01 |\\n| Ada | Confirm customer quote approvals | 2026-07-31 |\\n\\nPlease reply with changes today so the board packet stays on schedule.\\n' > board-prep-recap-email.md && printf 'wrote board-prep-recap-email.md\\n'
        """
    }

    private static var maintenanceNoticeCommand: String {
        return """
        echo Original maintenance window notice>maintenance-window-notice.md&&echo Enterprise admins: Scheduled maintenance starts 2026-08-14 22:00 UTC for 45 minutes>maintenance-notice-variants.md&&echo End users: QuillCode maintenance starts 2026-08-14 22:00 UTC for 45 minutes>>maintenance-notice-variants.md&&echo Status page post: Planned maintenance begins 2026-08-14 22:00 UTC>>maintenance-notice-variants.md&&echo wrote maintenance-notice-variants.md
        """
    }

    private static var obligationTrackingCommand: String {
        return """
        echo Acme SOW source>Acme-SOW.pdf&&echo due_date,reminder_date,deliverable,owner>acme-sow-obligations.csv&&echo 2026-09-15,2026-09-01,Acme kickoff workshop,Ada>>acme-sow-obligations.csv&&echo 2026-10-01,2026-09-17,Data migration plan,Ben>>acme-sow-obligations.csv&&echo 2026-10-20,2026-10-06,Security review package,Cam>>acme-sow-obligations.csv&&echo wrote acme-sow-obligations.csv
        """
    }

    private static var raciChartCommand: String {
        return """
        echo name,role>stakeholders.csv&&echo Ada,Migration Lead>>stakeholders.csv&&echo Ben,Engineering Owner>>stakeholders.csv&&echo Cam,Finance Approver>>stakeholders.csv&&echo Dee,Operations Consulted>>stakeholders.csv&&echo Discovery>phase-plan.md&&echo Data migration>>phase-plan.md&&echo Testing>>phase-plan.md&&echo Cutover>>phase-plan.md&&echo Stabilization>>phase-plan.md&&echo phase,responsible,accountable,consulted,informed>erp-migration-raci.csv&&echo Data migration,Ada,Ben,Cam,Dee>>erp-migration-raci.csv&&echo Testing,Ben,Ada,Cam,Dee>>erp-migration-raci.csv&&echo Cutover,Ada,Cam,Ben,Dee>>erp-migration-raci.csv&&echo wrote erp-migration-raci.csv
        """
    }

    private static var invoiceReconciliationCommand: String {
        return """
        echo invoice,customer,amount>open_invoices.csv&&echo INV-1001,Acme,500>>open_invoices.csv&&echo INV-1002,Beta,1200>>open_invoices.csv&&echo INV-1003,Cedar,900>>open_invoices.csv&&echo date,description,invoice,amount>november-bank.csv&&echo 2026-11-03,Acme payment,INV-1001,500>>november-bank.csv&&echo 2026-11-08,Cedar payment,INV-1003,900>>november-bank.csv&&echo 2026-11-09,Cedar duplicate,INV-1003,900>>november-bank.csv&&echo invoice,expected,paid,status>invoice-reconciliation.csv&&echo INV-1001,500,500,paid>>invoice-reconciliation.csv&&echo INV-1002,1200,0,unpaid>>invoice-reconciliation.csv&&echo INV-1003,900,1800,paid_twice>>invoice-reconciliation.csv&&echo wrote invoice-reconciliation.csv
        """
    }

    private static var redlineAnalysisCommand: String {
        return """
        echo Executed MSA baseline>executed-msa.pdf&&echo Section 8 limitation of liability cap equals 12 months fees>>executed-msa.pdf&&echo Section 11 termination notice requires 60 days>>executed-msa.pdf&&echo Vendor Amendment Two>vendor-amendment-2.pdf&&echo Section 8 limitation of liability cap equals 24 months fees>>vendor-amendment-2.pdf&&echo Section 11 termination notice requires 30 days>>vendor-amendment-2.pdf&&echo clause,change,business_impact>amendment-redline-impact.csv&&echo Limitation of liability,cap increased from 12 months fees to 24 months fees,raises maximum exposure>>amendment-redline-impact.csv&&echo Termination notice,notice period shortened from 60 days to 30 days,reduces time to plan exit>>amendment-redline-impact.csv&&echo wrote amendment-redline-impact.csv
        """
    }

    private static var rfpComplianceMatrixCommand: String {
        return """
        echo RFP 2026 DOT source>RFP-2026-DOT.pdf&&echo Section 3.2 Contractor shall encrypt data at rest>>RFP-2026-DOT.pdf&&echo Section 4.1 Vendor must provide monthly status reports>>RFP-2026-DOT.pdf&&echo section,requirement,owner,workstream>rfp-compliance-matrix.csv&&echo 3.2,shall encrypt data at rest,,Security>>rfp-compliance-matrix.csv&&echo 4.1,must provide monthly status reports,,Program Management>>rfp-compliance-matrix.csv&&echo wrote rfp-compliance-matrix.csv
        """
    }

    private static var riskRegisterCommand: String {
        return """
        echo Project charter source>project-charter.pdf&&echo Risks include data migration delay vendor API outage and stakeholder training gaps>>project-charter.pdf&&echo risk,likelihood,impact,mitigation,owner>project-risk-register.csv&&echo Data migration delay,4,5,stage dry runs weekly,Ben>>project-risk-register.csv&&echo Vendor API outage,3,4,confirm rollback plan,Ada>>project-risk-register.csv&&echo Training adoption gap,3,3,schedule role-based walkthroughs,Cam>>project-risk-register.csv&&echo wrote project-risk-register.csv
        """
    }

    private static var roadmapDraftingCommand: String {
        return """
        echo Q3 OKR source>Q3-OKRs.docx&&echo Objective improve retention through onboarding activation and reporting>>Q3-OKRs.docx&&echo Objective expand enterprise readiness with permissions and audit trails>>Q3-OKRs.docx&&echo Q3 Roadmap>roadmap.md&&echo Theme: Retention-led Q3>>roadmap.md&&echo Milestone: Onboarding activation by 2026-07-31>>roadmap.md&&echo Milestone: Usage reporting by 2026-08-21>>roadmap.md&&echo Milestone: Enterprise permissions by 2026-09-11>>roadmap.md&&echo Milestone: Audit trail beta by 2026-09-25>>roadmap.md&&echo wrote roadmap.md
        """
    }

    private static var salesProposalCommand: String {
        return """
        echo Northwind Logistics discovery>discovery-call-notes.md&&echo Need cross dock scheduling warehouse analytics and carrier exception alerts>>discovery-call-notes.md&&echo Target pilot starts 2026-09-01 and executive rollout by 2026-10-15>>discovery-call-notes.md&&echo approved pricing tiers>pricing-sheet.xlsx&&echo Starter USD25000 Growth USD54000 Enterprise USD98000>>pricing-sheet.xlsx&&echo Northwind Logistics proposal>northwind-logistics-proposal.md&&echo Scope: cross dock scheduling warehouse analytics and carrier exception alerts>>northwind-logistics-proposal.md&&echo Timeline: pilot kickoff 2026-09-01 rollout 2026-10-15>>northwind-logistics-proposal.md&&echo Pricing tiers: Starter USD25000 Growth USD54000 Enterprise USD98000>>northwind-logistics-proposal.md&&echo Assumptions: Northwind provides carrier feeds warehouse contacts and pilot success metrics>>northwind-logistics-proposal.md&&echo wrote northwind-logistics-proposal.md
        """
    }

    private static var salesOnePagerCommand: String {
        return """
        echo 20 slide product deck source>product-deck-20-slides.pptx&&echo Slides cover automation analytics security onboarding integrations and customer outcomes>>product-deck-20-slides.pptx&&echo approved pricing>approved-pricing.csv&&echo tier,price,fit>>approved-pricing.csv&&echo Starter,USD12000,small teams>>approved-pricing.csv&&echo Growth,USD36000,growing teams>>approved-pricing.csv&&echo Enterprise,custom,regulated teams>>approved-pricing.csv&&echo Customer leave-behind>customer-leave-behind.md&&echo Three proof points: reduce manual handoffs improve forecast accuracy and shorten onboarding>>customer-leave-behind.md&&echo Pricing tiers: Starter USD12000 Growth USD36000 Enterprise custom>>customer-leave-behind.md&&echo Call to action: schedule a 30 minute pilot planning session this week>>customer-leave-behind.md&&echo wrote customer-leave-behind.md
        """
    }

    private static var scannedPensionExtractionCommand: String {
        return """
        echo image-only pension booklet source>pension-plan-1994-scanned.pdf&&echo OCR text page 14 vesting schedule years zero to two equals zero pct three equals twenty pct four equals forty pct five equals sixty pct six equals eighty pct seven equals one hundred pct>>pension-plan-1994-scanned.pdf&&echo OCR text page 22 early retirement age55 equals fifty pct age60 equals seventy pct age62 equals eighty five pct>>pension-plan-1994-scanned.pdf&&echo section,condition,value>pension-vesting-retirement-table.csv&&echo vesting,years0_to_2,0pct>>pension-vesting-retirement-table.csv&&echo vesting,year3,20pct>>pension-vesting-retirement-table.csv&&echo vesting,year4,40pct>>pension-vesting-retirement-table.csv&&echo vesting,year5,60pct>>pension-vesting-retirement-table.csv&&echo vesting,year6,80pct>>pension-vesting-retirement-table.csv&&echo vesting,year7_plus,100pct>>pension-vesting-retirement-table.csv&&echo early_retirement_reduction,age55,50pct>>pension-vesting-retirement-table.csv&&echo early_retirement_reduction,age60,70pct>>pension-vesting-retirement-table.csv&&echo early_retirement_reduction,age62,85pct>>pension-vesting-retirement-table.csv&&echo wrote pension-vesting-retirement-table.csv
        """
    }

    private static var supportTriageCommand: String {
        return """
        echo ticket_id,theme,first_response,summary>zendesk-export.csv&&echo ZD-101,billing_access,2h,invoice portal login broken>>zendesk-export.csv&&echo ZD-102,login_mfa,1h30m,mfa reset request>>zendesk-export.csv&&echo ZD-103,import_csv,3h,csv import failed on date column>>zendesk-export.csv&&echo ZD-104,billing_access,2h45m,card update page loops>>zendesk-export.csv&&echo ZD-105,performance,4h,report loads slowly>>zendesk-export.csv&&echo ZD-106,login_mfa,1h,mfa backup code lost>>zendesk-export.csv&&echo ZD-107,api_webhooks,5h,webhook retries missing>>zendesk-export.csv&&echo ZD-108,billing_access,2h,receipt download error>>zendesk-export.csv&&echo ZD-109,import_csv,2h30m,duplicate rows after upload>>zendesk-export.csv&&echo ZD-110,permissions,3h15m,admin cannot invite teammate>>zendesk-export.csv&&echo ZD-111,performance,4h30m,dashboard timeout>>zendesk-export.csv&&echo ZD-112,api_webhooks,4h45m,signature validation fails>>zendesk-export.csv&&echo ZD-113,permissions,3h,role cannot see invoices>>zendesk-export.csv&&echo ZD-114,notifications,2h10m,email digest missing>>zendesk-export.csv&&echo ZD-115,notifications,2h20m,slack alert duplicated>>zendesk-export.csv&&echo ZD-116,sso_setup,6h,saml certificate rotation>>zendesk-export.csv&&echo theme,ticket_volume,average_first_response,examples>zendesk-theme-triage.csv&&echo billing_access,3,2h15m,ZD-101 ZD-104 ZD-108>>zendesk-theme-triage.csv&&echo login_mfa,2,1h15m,ZD-102 ZD-106>>zendesk-theme-triage.csv&&echo import_csv,2,2h45m,ZD-103 ZD-109>>zendesk-theme-triage.csv&&echo performance,2,4h15m,ZD-105 ZD-111>>zendesk-theme-triage.csv&&echo api_webhooks,2,4h52m,ZD-107 ZD-112>>zendesk-theme-triage.csv&&echo permissions,2,3h07m,ZD-110 ZD-113>>zendesk-theme-triage.csv&&echo notifications,2,2h15m,ZD-114 ZD-115>>zendesk-theme-triage.csv&&echo sso_setup,1,6h,ZD-116>>zendesk-theme-triage.csv&&echo wrote zendesk-theme-triage.csv
        """
    }

    private static var billingSupportMacrosCommand: String {
        return """
        echo Tone sample: warm concise specific and ownership-forward>existing-macros.md&&echo Use Thanks for flagging this and I can help as the standard opener>>existing-macros.md&&echo Apology variants acknowledge friction once and then move to the fix>>existing-macros.md&&echo Billing support macros>billing-support-macros.md&&echo Macro 1 failed payment standard variant: Thanks for flagging this I can help update the card and retry the invoice today>>billing-support-macros.md&&echo Macro 1 failed payment apology variant: Sorry for the payment friction I can help update the card and retry the invoice today>>billing-support-macros.md&&echo Macro 2 invoice copy standard variant: Thanks for reaching out I attached the invoice copy and confirmed the billing contact>>billing-support-macros.md&&echo Macro 2 invoice copy apology variant: Sorry the invoice was hard to find I attached the copy and confirmed the billing contact>>billing-support-macros.md&&echo Macro 3 plan change standard variant: Thanks for the details I can move the workspace to the requested plan at renewal>>billing-support-macros.md&&echo Macro 3 plan change apology variant: Sorry this was unclear I can move the workspace to the requested plan at renewal>>billing-support-macros.md&&echo Macro 4 tax exemption standard variant: Thanks for sending the certificate I will apply tax exemption after finance review>>billing-support-macros.md&&echo Macro 4 tax exemption apology variant: Sorry for the extra step I will apply tax exemption after finance review>>billing-support-macros.md&&echo Macro 5 duplicate charge standard variant: Thanks for the note I found the duplicate charge and opened a billing adjustment>>billing-support-macros.md&&echo Macro 5 duplicate charge apology variant: Sorry about the duplicate charge I found it and opened a billing adjustment>>billing-support-macros.md&&echo Macro 6 refund timing standard variant: Thanks for checking refunds usually post in five to seven business days>>billing-support-macros.md&&echo Macro 6 refund timing apology variant: Sorry for the wait refunds usually post in five to seven business days>>billing-support-macros.md&&echo wrote billing-support-macros.md
        """
    }

    private static var npsSurveyAnalysisCommand: String {
        return """
        echo survey export q2>customer-survey-q2.csv&&echo respondent,plan_tier,score,comment>>customer-survey-q2.csv&&echo C-001,Enterprise,10,Great support and uptime>>customer-survey-q2.csv&&echo C-002,Enterprise,9,Admin controls are strong>>customer-survey-q2.csv&&echo C-003,Enterprise,4,Reporting is slow>>customer-survey-q2.csv&&echo C-004,Growth,8,Useful but onboarding took effort>>customer-survey-q2.csv&&echo C-005,Growth,3,Mobile app crashes during upload>>customer-survey-q2.csv&&echo C-006,Growth,10,Fast answers from support>>customer-survey-q2.csv&&echo C-007,Starter,2,Too expensive for small teams>>customer-survey-q2.csv&&echo C-008,Starter,7,Setup docs need examples>>customer-survey-q2.csv&&echo C-009,Starter,9,Simple and reliable>>customer-survey-q2.csv&&echo C-010,Enterprise,6,Permissions are confusing>>customer-survey-q2.csv&&echo C-011,Growth,5,Billing invoices are unclear>>customer-survey-q2.csv&&echo C-012,Starter,1,Integrations are missing>>customer-survey-q2.csv&&echo plan_tier,nps,total,promoters,passives,detractors>nps-plan-tier-summary.csv&&echo Enterprise,67,3,2,1,detractors0>>nps-plan-tier-summary.csv&&echo Growth,0,4,1,1,detractors2>>nps-plan-tier-summary.csv&&echo Starter,-25,4,1,1,detractors2>>nps-plan-tier-summary.csv&&echo complaint,theme>nps-detractor-complaints.md&&echo complaint_1,Reporting is slow>>nps-detractor-complaints.md&&echo complaint_2,Mobile app crashes during upload>>nps-detractor-complaints.md&&echo complaint_3,Too expensive for small teams>>nps-detractor-complaints.md&&echo complaint_4,Billing invoices are unclear>>nps-detractor-complaints.md&&echo complaint_5,Integrations are missing>>nps-detractor-complaints.md&&echo wrote nps-plan-tier-summary.csv
        """
    }

    private static var workBreakdownCommand: String {
        return """
        echo name,role>team-roster.csv&&echo Ada,Product>>team-roster.csv&&echo Ben,Engineering>>team-roster.csv&&echo Cam,Design>>team-roster.csv&&echo Dee,Customer Success>>team-roster.csv&&echo Goal launch self serve onboarding by October>onboarding-goal.md&&echo phase,workstream,owner,effort_estimate,due_month>wbs.xlsx&&echo Discovery,Current signup audit,Ada,3d,July>>wbs.xlsx&&echo Design,Activation path mockups,Cam,4d,August>>wbs.xlsx&&echo Implementation,Onboarding checklist,Ada,5d,August>>wbs.xlsx&&echo Implementation,In app guide builder,Ben,8d,September>>wbs.xlsx&&echo Enablement,Help center refresh,Dee,3d,September>>wbs.xlsx&&echo Launch,October rollout readiness,Ada,2d,October>>wbs.xlsx&&echo wrote wbs.xlsx
        """
    }

    private static var timelineBuildingCommand: String {
        return """
        echo milestone,due_date,duration_days>milestones.csv&&echo Requirements freeze,2026-08-12,duration7>>milestones.csv&&echo Beta content ready,2026-09-09,duration10>>milestones.csv&&echo QA complete,2026-10-06,duration12>>milestones.csv&&echo Launch,2026-11-03,duration14>>milestones.csv&&echo task,start_date,end_date,duration,dependency>timeline.xlsx&&echo Requirements freeze,2026-08-05,2026-08-12,7d,none>>timeline.xlsx&&echo Beta content ready,2026-08-30,2026-09-09,10d,Requirements freeze>>timeline.xlsx&&echo QA complete,2026-09-24,2026-10-06,12d,Beta content ready>>timeline.xlsx&&echo Launch readiness,2026-10-20,2026-11-03,14d,QA complete>>timeline.xlsx&&echo wrote timeline.xlsx
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
    var secondaryArtifacts: [OneTurnCoworkerArtifactCheck] = []
}

private struct OneTurnCoworkerArtifactCheck {
    var relativePath: String
    var expectation: OneTurnCoworkerArtifactExpectation
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
