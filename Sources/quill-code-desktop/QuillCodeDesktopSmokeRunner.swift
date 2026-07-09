import AppKit
import Foundation
import SwiftUI
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

    func presentSession(_ snapshot: BrowserSessionSyncSnapshot) {}
    func syncSession(_ snapshot: BrowserSessionSyncSnapshot) {}
    func goBackSession(fallback snapshot: BrowserSessionSyncSnapshot) {}
    func goForwardSession(fallback snapshot: BrowserSessionSyncSnapshot) {}
    func reloadSession() {}
}

private struct SmokeAutomationNotifier: QuillCodeAutomationNotifying {
    func deliver(_ report: AutomationRunReport) {}
}
