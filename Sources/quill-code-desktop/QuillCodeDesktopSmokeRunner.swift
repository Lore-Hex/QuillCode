import AppKit
import Darwin
import Foundation
import SwiftUI
import QuillCodeApp
import QuillCodeCore
import QuillCodePersistence

struct QuillCodeDesktopSmokeRequest: Sendable {
    var reportPath: String?
    var renderPath: String?
    var htmlPath: String?
    var workspacePath: String?

    init?(arguments: [String]) {
        guard arguments.contains("--native-render-smoke") else {
            return nil
        }

        self.reportPath = Self.value(after: "--smoke-report", in: arguments)
        self.renderPath = Self.value(after: "--smoke-render", in: arguments)
        self.htmlPath = Self.value(after: "--smoke-html", in: arguments)
        self.workspacePath = Self.value(after: "--smoke-workspace", in: arguments)
    }

    private static func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag) else { return nil }
        let valueIndex = arguments.index(after: index)
        guard valueIndex < arguments.endIndex else { return nil }
        return arguments[valueIndex]
    }
}

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
        let root = try SmokeWorkspaceRoot(request: request)
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
        guard surface.transcript.messages.count >= 2,
              surface.transcript.toolCards.count >= 1,
              surface.transcript.timelineItems.count >= 3
        else {
            throw QuillCodeDesktopSmokeFailure.incompleteTranscript
        }
        guard surface.transcript.toolCards.last?.status == .done else {
            throw QuillCodeDesktopSmokeFailure.toolCardDidNotComplete
        }

        let renderURL = try root.renderURL(request: request)
        let image = try renderWorkspace(controller: controller, renderURL: renderURL)
        let stats = try QuillCodeDesktopSmokePixelStats(image: image)
        try stats.validate()

        let htmlURL = try root.htmlURL(request: request)
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
            htmlPath: htmlURL.path,
            image: stats.report
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

private struct SmokeWorkspaceRoot {
    var root: URL
    var home: URL
    var workspace: URL

    init(request: QuillCodeDesktopSmokeRequest) throws {
        if let workspacePath = request.workspacePath, !workspacePath.isEmpty {
            root = URL(fileURLWithPath: workspacePath, isDirectory: true)
        } else {
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent("quillcode-desktop-smoke-\(UUID().uuidString)", isDirectory: true)
        }
        home = root.appendingPathComponent("home", isDirectory: true)
        workspace = root.appendingPathComponent("workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
    }

    func renderURL(request: QuillCodeDesktopSmokeRequest) throws -> URL {
        if let renderPath = request.renderPath, !renderPath.isEmpty {
            return URL(fileURLWithPath: renderPath)
        }
        return root.appendingPathComponent("quillcode-desktop-smoke.png")
    }

    func htmlURL(request: QuillCodeDesktopSmokeRequest) throws -> URL {
        if let htmlPath = request.htmlPath, !htmlPath.isEmpty {
            return URL(fileURLWithPath: htmlPath)
        }
        return root.appendingPathComponent("quillcode-desktop-smoke.html")
    }
}

private struct QuillCodeDesktopSmokeReport {
    var ok: Bool
    var prompt: String
    var finalAnswer: String
    var toolName: String
    var messageCount: Int
    var toolCardCount: Int
    var timelineItemCount: Int
    var workspacePath: String
    var createdFilePath: String
    var renderPath: String
    var htmlPath: String
    var image: QuillCodeDesktopSmokePixelReport

    func prettyJSON() throws -> Data {
        try JSONSerialization.data(
            withJSONObject: [
                "ok": ok,
                "prompt": prompt,
                "finalAnswer": finalAnswer,
                "toolName": toolName,
                "messageCount": messageCount,
                "toolCardCount": toolCardCount,
                "timelineItemCount": timelineItemCount,
                "workspacePath": workspacePath,
                "createdFilePath": createdFilePath,
                "renderPath": renderPath,
                "htmlPath": htmlPath,
                "image": image.dictionary
            ],
            options: [.prettyPrinted, .sortedKeys]
        )
    }
}

private struct QuillCodeDesktopSmokePixelReport {
    var width: Int
    var height: Int
    var opaquePixelRatio: Double
    var brightPixelRatio: Double
    var blueAccentPixelRatio: Double
    var distinctColorBuckets: Int

    var dictionary: [String: Any] {
        [
            "width": width,
            "height": height,
            "opaquePixelRatio": opaquePixelRatio,
            "brightPixelRatio": brightPixelRatio,
            "blueAccentPixelRatio": blueAccentPixelRatio,
            "distinctColorBuckets": distinctColorBuckets
        ]
    }
}

private struct QuillCodeDesktopSmokePixelStats {
    var report: QuillCodeDesktopSmokePixelReport

    init(image: CGImage) throws {
        let width = image.width
        let height = image.height
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
            throw QuillCodeDesktopSmokeFailure.bitmapContextFailed
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

        report = QuillCodeDesktopSmokePixelReport(
            width: width,
            height: height,
            opaquePixelRatio: Double(opaquePixels) / Double(totalPixels),
            brightPixelRatio: Double(brightPixels) / Double(totalPixels),
            blueAccentPixelRatio: Double(blueAccentPixels) / Double(totalPixels),
            distinctColorBuckets: colorBuckets.count
        )
    }

    func validate() throws {
        guard report.width == 1280, report.height == 900 else {
            throw QuillCodeDesktopSmokeFailure.invalidImageSize(report.width, report.height)
        }
        guard report.opaquePixelRatio > 0.98 else {
            throw QuillCodeDesktopSmokeFailure.imageTooTransparent(report.opaquePixelRatio)
        }
        guard report.distinctColorBuckets > 28 else {
            throw QuillCodeDesktopSmokeFailure.imageTooFlat(report.distinctColorBuckets)
        }
        guard report.brightPixelRatio > 0.0008 else {
            throw QuillCodeDesktopSmokeFailure.imageMissingBrightPixels(report.brightPixelRatio)
        }
        guard report.blueAccentPixelRatio > 0.0001 else {
            throw QuillCodeDesktopSmokeFailure.imageMissingAccentPixels(report.blueAccentPixelRatio)
        }
    }
}

private enum QuillCodeDesktopSmokeFailure: Error {
    case bitmapContextFailed
    case createdFileMismatch(String)
    case imageMissingAccentPixels(Double)
    case imageMissingBrightPixels(Double)
    case imageTooFlat(Int)
    case imageTooTransparent(Double)
    case htmlMissingResult
    case incompleteTranscript
    case invalidImageSize(Int, Int)
    case pngEncodingFailed
    case renderFailed
    case timedOut
    case toolCardDidNotComplete
}

@MainActor
private final class SmokeBrowserSessionPresenter: DesktopBrowserSessionPresenting {
    func presentSession(_ snapshot: BrowserSessionSyncSnapshot) {}
    func syncSession(_ snapshot: BrowserSessionSyncSnapshot) {}
}

private struct SmokeAutomationNotifier: QuillCodeAutomationNotifying {
    func deliver(_ report: AutomationRunReport) {}
}
