import AppKit
import SwiftUI
import XCTest
import QuillCodeCore
import QuillCodePersistence
@testable import QuillCodeApp
@testable import quill_code_desktop

@MainActor
final class QuillCodeDesktopRenderedSmokeTests: XCTestCase {
    func testRenderedWorkspaceShowsRealWorldActionResult() async throws {
        let workspaceRoot = try makeTempDirectory()
        let controller = try makeController(workspaceRoot: workspaceRoot)

        controller.draft = #"Can you write a file that says "hello world""#
        let previousTimelineCount = controller.surface.transcript.timelineItems.count
        controller.send()

        try await waitForDesktopRun(
            controller,
            previousTimelineCount: previousTimelineCount,
            expectedAnswer: "Wrote `hello.txt`."
        )

        let writtenFile = workspaceRoot.appendingPathComponent("hello.txt")
        let writtenText = try String(contentsOf: writtenFile, encoding: .utf8)
        XCTAssertTrue(writtenText.contains("hello world"))

        controller.draft = "Read `hello.txt` and tell me its exact content."
        let followUpTimelineCount = controller.surface.transcript.timelineItems.count
        controller.send()

        try await waitForDesktopRun(
            controller,
            previousTimelineCount: followUpTimelineCount,
            expectedAnswer: "hello world"
        )

        let surface = controller.surface
        XCTAssertEqual(surface.transcript.toolCards.last?.status, .done)
        XCTAssertEqual(surface.transcript.toolCards.last?.title, ToolDefinition.fileRead.name)
        XCTAssertGreaterThanOrEqual(surface.transcript.timelineItems.count, previousTimelineCount + 6)
        XCTAssertTrue(surface.transcript.messages.last?.text.contains("Contents of `hello.txt`:") == true)
        XCTAssertTrue(surface.transcript.messages.last?.text.contains("hello world") == true)

        let workspaceImage = try renderWorkspace(surface)
        let workspaceStats = try RenderedWorkspacePixelStats(image: workspaceImage)

        XCTAssertEqual(workspaceStats.width, 1280)
        XCTAssertEqual(workspaceStats.height, 900)
        XCTAssertGreaterThan(workspaceStats.opaquePixelRatio, 0.98)
        XCTAssertGreaterThan(
            workspaceStats.distinctColorBuckets,
            28,
            "Rendered workspace should contain real chrome and accent colors."
        )
        XCTAssertGreaterThan(
            workspaceStats.brightPixelRatio,
            0.0008,
            "Rendered workspace should contain visible text/control pixels instead of a flat blank surface."
        )
        XCTAssertGreaterThan(
            workspaceStats.blueAccentPixelRatio,
            0.0001,
            "Rendered workspace should include QuillCode accent controls instead of a flat blank surface."
        )

        let transcriptImage = try renderTranscriptExcerpt(surface)
        let transcriptStats = try RenderedWorkspacePixelStats(image: transcriptImage)
        XCTAssertEqual(transcriptStats.width, 860)
        XCTAssertEqual(transcriptStats.height, 520)
        XCTAssertGreaterThan(transcriptStats.distinctColorBuckets, 34)
        XCTAssertGreaterThan(
            transcriptStats.brightPixelRatio,
            0.003,
            "Rendered transcript excerpt should visibly show the prompt, tool card, and final answer."
        )
        XCTAssertGreaterThan(
            transcriptStats.blueAccentPixelRatio,
            0.002,
            "Rendered transcript excerpt should preserve tool-card and user-bubble accents."
        )
    }

    private func renderWorkspace(_ surface: WorkspaceSurface) throws -> CGImage {
        let view = QuillCodeWorkspaceView(
            surface: surface,
            draft: .constant(""),
            terminalDraft: .constant(""),
            browserAddressDraft: .constant(""),
            isCommandPalettePresented: .constant(false),
            isSettingsPresented: .constant(false),
            isKeyboardShortcutsPresented: .constant(false),
            onSend: {},
            onRunTerminalCommand: {},
            onOpenBrowserPreview: {},
            onAddBrowserComment: { _ in },
            onAddProjectRequested: {},
            onSelectThread: { _ in },
            onThreadAction: { _ in },
            onRenameThread: { _, _ in },
            onSelectProject: { _ in },
            onProjectAction: { _ in },
            onRenameProject: { _, _ in },
            onSetMode: { _ in },
            onSetModel: { _ in },
            onToggleModelFavorite: { _ in },
            onSaveSettings: { _ in },
            onStartTrustedRouterSignIn: {},
            onReviewAction: { _ in },
            onToolCardAction: { _ in },
            onAddReviewComment: { _, _, _, _, _ in },
            onCreateWorktree: { _ in },
            onOpenWorktree: { _ in },
            onRemoveWorktree: { _ in },
            onCopyTranscriptItem: { _, _ in },
            onCommand: { _ in }
        )
        .frame(width: 1280, height: 900)

        return try render(
            view,
            width: 1280,
            height: 900,
            debugPathEnvironmentKey: "QUILLCODE_RENDER_SMOKE_IMAGE_PATH"
        )
    }

    private func renderTranscriptExcerpt(_ surface: WorkspaceSurface) throws -> CGImage {
        let view = RenderedTranscriptExcerpt(
            items: Array(surface.transcript.timelineItems.suffix(3))
        )
        .frame(width: 860, height: 520, alignment: .topLeading)

        return try render(
            view,
            width: 860,
            height: 520,
            debugPathEnvironmentKey: "QUILLCODE_RENDER_SMOKE_TRANSCRIPT_IMAGE_PATH"
        )
    }

    private func render<Content: View>(
        _ view: Content,
        width: CGFloat,
        height: CGFloat,
        debugPathEnvironmentKey: String
    ) throws -> CGImage {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        renderer.isOpaque = true
        renderer.proposedSize = ProposedViewSize(width: width, height: height)

        guard let image = renderer.cgImage else {
            XCTFail("SwiftUI workspace did not render a CGImage.")
            throw RenderedWorkspaceSmokeFailure.renderFailed
        }
        try writeDebugRenderIfRequested(image, environmentKey: debugPathEnvironmentKey)
        return image
    }

    private func writeDebugRenderIfRequested(_ image: CGImage, environmentKey: String) throws {
        guard let path = ProcessInfo.processInfo.environment[environmentKey],
              !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        let rep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw RenderedWorkspaceSmokeFailure.pngEncodingFailed
        }
        try data.write(to: URL(fileURLWithPath: path), options: .atomic)
    }

    private func makeController(workspaceRoot: URL) throws -> QuillCodeDesktopController {
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
            browserSessionPresenter: RenderSmokeNoopBrowserSessionPresenter(),
            automationNotifier: RenderSmokeNoopAutomationNotifier(),
            workspaceRoot: workspaceRoot
        )
    }

    private func waitForDesktopRun(
        _ controller: QuillCodeDesktopController,
        previousTimelineCount: Int,
        expectedAnswer: String,
        file: StaticString = #filePath,
        line: UInt = #line
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
        XCTFail("Desktop send did not complete with expected answer: \(expectedAnswer)", file: file, line: line)
    }

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuillCodeDesktopRenderTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }
}

private struct RenderedTranscriptExcerpt: View {
    var items: [TranscriptTimelineItemSurface]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(items) { item in
                if let message = item.message {
                    QuillCodeMessageBubble(
                        message: message,
                        timelineItemID: item.id,
                        isCopied: false,
                        onCopy: {},
                        onUseAsDraft: {},
                        canRetry: false,
                        onRetry: {}
                    )
                } else if let card = item.toolCard {
                    QuillCodeToolCardView(card: card)
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(QuillCodePalette.background)
        .foregroundStyle(QuillCodePalette.text)
    }
}

private enum RenderedWorkspaceSmokeFailure: Error {
    case bitmapContextFailed
    case renderFailed
    case pngEncodingFailed
}

private struct RenderedWorkspacePixelStats {
    var width: Int
    var height: Int
    var opaquePixelRatio: Double
    var brightPixelRatio: Double
    var blueAccentPixelRatio: Double
    var distinctColorBuckets: Int

    init(image: CGImage) throws {
        width = image.width
        height = image.height

        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw RenderedWorkspaceSmokeFailure.bitmapContextFailed
        }

        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        var opaquePixels = 0
        var brightPixels = 0
        var blueAccentPixels = 0
        var colorBuckets = Set<Int>()
        let totalPixels = width * height

        for index in stride(from: 0, to: pixels.count, by: 4) {
            let red = Int(pixels[index])
            let green = Int(pixels[index + 1])
            let blue = Int(pixels[index + 2])
            let alpha = Int(pixels[index + 3])

            if alpha > 240 {
                opaquePixels += 1
            }
            if red + green + blue > 560 {
                brightPixels += 1
            }
            if blue > 130, green > 95, red < 120 {
                blueAccentPixels += 1
            }

            let bucket = (red / 16) << 8 | (green / 16) << 4 | (blue / 16)
            colorBuckets.insert(bucket)
        }

        opaquePixelRatio = Double(opaquePixels) / Double(totalPixels)
        brightPixelRatio = Double(brightPixels) / Double(totalPixels)
        blueAccentPixelRatio = Double(blueAccentPixels) / Double(totalPixels)
        distinctColorBuckets = colorBuckets.count
    }
}

@MainActor
private final class RenderSmokeNoopBrowserSessionPresenter: DesktopBrowserSessionPresenting {
    var onSessionUpdate: (@MainActor (BrowserSessionUpdate) -> Void)?

    func presentSession(_ snapshot: BrowserSessionSyncSnapshot) {}
    func syncSession(_ snapshot: BrowserSessionSyncSnapshot) {}
    func goBackSession(fallback snapshot: BrowserSessionSyncSnapshot) {}
    func goForwardSession(fallback snapshot: BrowserSessionSyncSnapshot) {}
    func evaluateJavaScriptInSelectedTab(_ source: String) async throws -> DesktopBrowserSessionScriptResult {
        throw DesktopBrowserSessionScriptError.noOpenSession
    }
    func captureLiveDOMSnapshotInSelectedTab() async throws -> BrowserLiveDOMSnapshot {
        throw DesktopBrowserSessionScriptError.noOpenSession
    }
    func clickInSelectedTab(selector: String) async throws -> DesktopBrowserSessionActionResult {
        throw DesktopBrowserSessionActionError.noOpenSession
    }
    func typeInSelectedTab(selector: String, text: String, submit: Bool) async throws -> DesktopBrowserSessionActionResult {
        throw DesktopBrowserSessionActionError.noOpenSession
    }
    func reloadSession() {}
}

private struct RenderSmokeNoopAutomationNotifier: QuillCodeAutomationNotifying {
    func deliver(_ report: AutomationRunReport) {}
}
