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

        let prompt = #"Can you write a file that says "hello world""#
        controller.draft = prompt
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

        let surface = controller.surface
        let nativeHitTargets = QuillCodeNativeHitTargetAudit.report(for: surface)
        guard nativeHitTargets.isValid else {
            throw QuillCodeDesktopSmokeFailure.nativeHitTargetAuditFailed(
                nativeHitTargets.validationIssues
                    + nativeHitTargets.missingDesignKinds.map { "missing design kind: \($0)" }
                    + nativeHitTargets.missingSurfaceFamilies.map { "missing surface family: \($0)" }
                    + nativeHitTargets.missingRequiredCommandIDs.map { "missing command: \($0)" }
            )
        }
        guard surface.transcript.messages.count >= 2,
              surface.transcript.toolCards.count >= 1,
              surface.transcript.timelineItems.count >= 3
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
              html.contains("host.file.write")
        else {
            throw QuillCodeDesktopSmokeFailure.htmlMissingResult
        }
        try html.write(to: htmlURL, atomically: true, encoding: .utf8)

        return QuillCodeDesktopSmokeReport(
            ok: true,
            prompt: prompt,
            finalAnswer: surface.transcript.messages.last?.text ?? "",
            toolName: surface.transcript.toolCards.last?.title ?? "",
            messageCount: surface.transcript.messages.count,
            toolCardCount: surface.transcript.toolCards.count,
            timelineItemCount: surface.transcript.timelineItems.count,
            workspacePath: root.workspace.path,
            createdFilePath: createdFile.path,
            renderPath: renderURL.path,
            chromeRenderPath: chromeRenderURL.path,
            htmlPath: htmlURL.path,
            image: stats.report,
            chromeImage: chromeStats.report,
            chrome: chrome,
            nativeHitTargets: nativeHitTargets
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

}

@MainActor
private final class SmokeBrowserSessionPresenter: DesktopBrowserSessionPresenting {
    var onSessionUpdate: (@MainActor (BrowserSessionUpdate) -> Void)?

    func presentSession(_ snapshot: BrowserSessionSyncSnapshot) {}
    func syncSession(_ snapshot: BrowserSessionSyncSnapshot) {}
}

private struct SmokeAutomationNotifier: QuillCodeAutomationNotifying {
    func deliver(_ report: AutomationRunReport) {}
}
