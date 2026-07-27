import AppKit
import Foundation
import SwiftUI
import QuillCodeAgent
import QuillCodeApp
import QuillCodeCore
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
        let controller = QuillCodeDesktopController(
            bootstrap: bootstrap,
            browserPageFetcher: URLSessionBrowserPageFetcher(),
            browserLiveDOMCapturer: nil,
            browserSessionPresenter: SmokeBrowserSessionPresenter(),
            automationNotifier: SmokeAutomationNotifier(),
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
            nativeHitTargets: nativeHitTargets
        )
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
        for _ in 0..<300 {
            let timelineCount = controller.surface.transcript.timelineItems.count
            let latestAnswer = controller.surface.transcript.messages.last?.text ?? ""
            if !controller.surface.composer.isSending,
               timelineCount >= previousTimelineCount + 3,
               latestAnswer.contains(expectedAnswer) {
                return
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        throw QuillCodeDesktopSmokeFailure.timedOut
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

    private func scriptValue(for tab: BrowserSessionTabSnapshot) -> String {
        switch page(for: tab) {
        case .crm:
            return statusText
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
        tab.url.absoluteString.contains("browser-sheet-smoke.html") ? .spreadsheet : .crm
    }

    private enum SmokeBrowserPage {
        case crm
        case spreadsheet

        var title: String {
            switch self {
            case .crm:
                return "CRM Workflow Smoke"
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

private struct SmokeAutomationNotifier: QuillCodeAutomationNotifying {
    func deliver(_ report: AutomationRunReport) {}
}
