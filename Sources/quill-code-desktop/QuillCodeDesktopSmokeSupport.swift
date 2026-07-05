import AppKit
import Foundation
import QuillCodeApp

struct QuillCodeDesktopSmokeRequest: Sendable {
    var reportPath: String?
    var renderPath: String?
    var resultRenderPath: String?
    var chromeRenderPath: String?
    var htmlPath: String?
    var workspacePath: String?

    init?(arguments: [String]) {
        guard arguments.contains("--native-render-smoke") else {
            return nil
        }

        self.reportPath = Self.value(after: "--smoke-report", in: arguments)
        self.renderPath = Self.value(after: "--smoke-render", in: arguments)
        self.resultRenderPath = Self.value(after: "--smoke-result-render", in: arguments)
        self.chromeRenderPath = Self.value(after: "--smoke-chrome-render", in: arguments)
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

struct QuillCodeDesktopWindowSmokeRequest: Sendable {
    var reportPath: String?
    var screenshotPath: String?

    init?(arguments: [String]) {
        guard arguments.contains("--native-window-smoke") else {
            return nil
        }

        self.reportPath = Self.value(after: "--window-smoke-report", in: arguments)
        self.screenshotPath = Self.value(after: "--window-smoke-screenshot", in: arguments)
    }

    private static func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag) else { return nil }
        let valueIndex = arguments.index(after: index)
        guard valueIndex < arguments.endIndex else { return nil }
        return arguments[valueIndex]
    }
}

struct QuillCodeDesktopSmokeWorkspaceRoot {
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

    func renderURL(request: QuillCodeDesktopSmokeRequest) -> URL {
        if let renderPath = request.renderPath, !renderPath.isEmpty {
            return URL(fileURLWithPath: renderPath)
        }
        return root.appendingPathComponent("quillcode-desktop-smoke.png")
    }

    func chromeRenderURL(request: QuillCodeDesktopSmokeRequest) -> URL {
        if let chromeRenderPath = request.chromeRenderPath, !chromeRenderPath.isEmpty {
            return URL(fileURLWithPath: chromeRenderPath)
        }
        return root.appendingPathComponent("quillcode-desktop-chrome-smoke.png")
    }

    func resultRenderURL(request: QuillCodeDesktopSmokeRequest) -> URL {
        if let resultRenderPath = request.resultRenderPath, !resultRenderPath.isEmpty {
            return URL(fileURLWithPath: resultRenderPath)
        }
        return root.appendingPathComponent("quillcode-desktop-result-smoke.png")
    }

    func htmlURL(request: QuillCodeDesktopSmokeRequest) -> URL {
        if let htmlPath = request.htmlPath, !htmlPath.isEmpty {
            return URL(fileURLWithPath: htmlPath)
        }
        return root.appendingPathComponent("quillcode-desktop-smoke.html")
    }
}

struct QuillCodeDesktopSmokeReport {
    var ok: Bool
    var prompt: String
    var finalAnswer: String
    var toolName: String
    var followUpPrompt: String
    var followUpFinalAnswer: String
    var followUpToolName: String
    var toolNames: [String]
    var messageCount: Int
    var toolCardCount: Int
    var timelineItemCount: Int
    var workspacePath: String
    var createdFilePath: String
    var renderPath: String
    var resultRenderPath: String
    var chromeRenderPath: String
    var htmlPath: String
    var image: QuillCodeDesktopSmokePixelReport
    var resultImage: QuillCodeDesktopSmokePixelReport
    var chromeImage: QuillCodeDesktopSmokePixelReport
    var chrome: QuillCodeDesktopChromeSmokeReport
    var browserSmoke: QuillCodeDesktopBrowserSmokeReport
    var nativeHitTargets: QuillCodeNativeHitTargetAuditReport

    func prettyJSON() throws -> Data {
        try JSONSerialization.data(
            withJSONObject: [
                "ok": ok,
                "prompt": prompt,
                "finalAnswer": finalAnswer,
                "toolName": toolName,
                "followUpPrompt": followUpPrompt,
                "followUpFinalAnswer": followUpFinalAnswer,
                "followUpToolName": followUpToolName,
                "toolNames": toolNames,
                "messageCount": messageCount,
                "toolCardCount": toolCardCount,
                "timelineItemCount": timelineItemCount,
                "workspacePath": workspacePath,
                "createdFilePath": createdFilePath,
                "renderPath": renderPath,
                "resultRenderPath": resultRenderPath,
                "chromeRenderPath": chromeRenderPath,
                "htmlPath": htmlPath,
                "image": image.dictionary,
                "resultImage": resultImage.dictionary,
                "chromeImage": chromeImage.dictionary,
                "chrome": chrome.dictionary,
                "browserSmoke": browserSmoke.dictionary,
                "nativeHitTargets": nativeHitTargets.dictionary
            ],
            options: [.prettyPrinted, .sortedKeys]
        )
    }
}

struct QuillCodeDesktopSmokePixelReport {
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

struct QuillCodeDesktopSmokePixelStats {
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

    func validate(
        expectedWidth: Int,
        expectedHeight: Int,
        minDistinctColorBuckets: Int,
        minBrightPixelRatio: Double,
        minBlueAccentPixelRatio: Double
    ) throws {
        guard report.width == expectedWidth, report.height == expectedHeight else {
            throw QuillCodeDesktopSmokeFailure.invalidImageSize(report.width, report.height)
        }
        guard report.opaquePixelRatio > 0.98 else {
            throw QuillCodeDesktopSmokeFailure.imageTooTransparent(report.opaquePixelRatio)
        }
        guard report.distinctColorBuckets > minDistinctColorBuckets else {
            throw QuillCodeDesktopSmokeFailure.imageTooFlat(report.distinctColorBuckets)
        }
        guard report.brightPixelRatio > minBrightPixelRatio else {
            throw QuillCodeDesktopSmokeFailure.imageMissingBrightPixels(report.brightPixelRatio)
        }
        guard minBlueAccentPixelRatio <= 0 || report.blueAccentPixelRatio > minBlueAccentPixelRatio else {
            throw QuillCodeDesktopSmokeFailure.imageMissingAccentPixels(report.blueAccentPixelRatio)
        }
    }
}

struct QuillCodeDesktopWindowSmokeReport {
    var ok: Bool
    var appName: String
    var bundleIdentifier: String
    var windowTitle: String
    var windowFrame: CGRect
    var contentSize: CGSize
    var screenshotPath: String
    var image: QuillCodeDesktopSmokePixelReport
    var nativeHitTargets: QuillCodeNativeHitTargetAuditReport
    var accessibilityFrameSamples: QuillCodeDesktopAccessibilityFrameSampleReport
    var accessibilityActivation: QuillCodeDesktopAccessibilityActivationReport
    var surface: QuillCodeDesktopWindowSmokeSurfaceReport

    func prettyJSON() throws -> Data {
        try JSONSerialization.data(
            withJSONObject: [
                "ok": ok,
                "appName": appName,
                "bundleIdentifier": bundleIdentifier,
                "windowTitle": windowTitle,
                "windowFrame": [
                    "x": windowFrame.origin.x,
                    "y": windowFrame.origin.y,
                    "width": windowFrame.size.width,
                    "height": windowFrame.size.height
                ],
                "contentSize": [
                    "width": contentSize.width,
                    "height": contentSize.height
                ],
                "screenshotPath": screenshotPath,
                "image": image.dictionary,
                "nativeHitTargets": nativeHitTargets.dictionary,
                "accessibilityFrameSamples": accessibilityFrameSamples.dictionary,
                "accessibilityActivation": accessibilityActivation.dictionary,
                "surface": surface.dictionary
            ],
            options: [.prettyPrinted, .sortedKeys]
        )
    }
}

enum QuillCodeDesktopNativeHitTargetSmoke {
    static func validatedReport(for surface: WorkspaceSurface) throws -> QuillCodeNativeHitTargetAuditReport {
        let nativeHitTargets = QuillCodeNativeHitTargetAudit.report(for: surface)
        guard nativeHitTargets.isValid else {
            throw QuillCodeDesktopSmokeFailure.nativeHitTargetAuditFailed(issueMessages(for: nativeHitTargets))
        }
        return nativeHitTargets
    }

    private static func issueMessages(
        for report: QuillCodeNativeHitTargetAuditReport
    ) -> [String] {
        report.validationIssues
            + report.missingDesignKinds.map { "missing design kind: \($0)" }
            + report.missingSurfaceFamilies.map { "missing surface family: \($0)" }
            + report.missingRequiredFocusTargets.map { "missing focus target: \($0)" }
            + report.missingRequiredCommandIDs.map { "missing command: \($0)" }
            + report.missingClickProbeContractIDs.map { "missing click probe: \($0)" }
            + report.clickProbeValidationIssues
    }
}

struct QuillCodeDesktopWindowSmokeSurfaceReport {
    static let requiredCommandIDs = [
        "add-project",
        "new-chat",
        "command-palette",
        "keyboard-shortcuts",
        "settings",
        "toggle-terminal",
        "toggle-browser",
        "stop-all",
        "disconnect-all"
    ]

    static let requiredStarterActionIDs = [
        "review-changes",
        "run-tests",
        "explain-project"
    ]

    var appName: String
    var primaryTitle: String
    var subtitle: String
    var modelLabel: String
    var modeLabel: String
    var agentStatus: String
    var composerPlaceholder: String
    var composerCanSend: Bool
    var sidebarTitle: String
    var sidebarItemCount: Int
    var commandIDs: [String]
    var starterActionIDs: [String]

    init(surface: WorkspaceSurface) throws {
        self.appName = surface.topBar.appName
        self.primaryTitle = surface.topBar.primaryTitle
        self.subtitle = surface.topBar.subtitle
        self.modelLabel = surface.topBar.modelLabel
        self.modeLabel = surface.topBar.modeLabel
        self.agentStatus = surface.topBar.agentStatus
        self.composerPlaceholder = surface.composer.placeholder
        self.composerCanSend = surface.composer.canSend
        self.sidebarTitle = surface.sidebar.title
        self.sidebarItemCount = surface.sidebar.items.count
        self.commandIDs = surface.commands.map(\.id).sorted()
        self.starterActionIDs = surface.transcript.emptyStarterActions.map(\.id)

        try validate()
    }

    var dictionary: [String: Any] {
        [
            "appName": appName,
            "primaryTitle": primaryTitle,
            "subtitle": subtitle,
            "modelLabel": modelLabel,
            "modeLabel": modeLabel,
            "agentStatus": agentStatus,
            "composerPlaceholder": composerPlaceholder,
            "composerCanSend": composerCanSend,
            "sidebarTitle": sidebarTitle,
            "sidebarItemCount": sidebarItemCount,
            "commandIDs": commandIDs,
            "requiredCommandIDs": Self.requiredCommandIDs,
            "starterActionIDs": starterActionIDs,
            "requiredStarterActionIDs": Self.requiredStarterActionIDs
        ]
    }

    private func validate() throws {
        try require(appName == "QuillCode", "top bar app name was \(appName)")
        try require(!primaryTitle.trimmedForSmoke.isEmpty, "primary title was empty")
        try require(!modelLabel.trimmedForSmoke.isEmpty, "model label was empty")
        try require(!modeLabel.trimmedForSmoke.isEmpty, "mode label was empty")
        try require(!agentStatus.trimmedForSmoke.isEmpty, "agent status was empty")
        try require(!composerPlaceholder.trimmedForSmoke.isEmpty, "composer placeholder was empty")
        try require(composerCanSend == false, "empty composer should not be sendable")
        try require(sidebarTitle == "Chats", "sidebar title was \(sidebarTitle)")

        let missingCommands = Self.requiredCommandIDs.filter { !commandIDs.contains($0) }
        try require(missingCommands.isEmpty, "missing commands: \(missingCommands.joined(separator: ", "))")

        let missingStarterActions = Self.requiredStarterActionIDs.filter { !starterActionIDs.contains($0) }
        try require(
            missingStarterActions.isEmpty,
            "missing starter actions: \(missingStarterActions.joined(separator: ", "))"
        )
    }

    private func require(_ condition: Bool, _ message: String) throws {
        guard condition else {
            throw QuillCodeDesktopSmokeFailure.windowSurfaceIncomplete(message)
        }
    }
}

private extension String {
    var trimmedForSmoke: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum QuillCodeDesktopSmokeFailure: Error {
    case bitmapContextFailed
    case chromeCommandDidNotRoute(String)
    case chromeCommandMissing(String)
    case chromeSurfaceIncomplete
    case createdFileMismatch(String)
    case browserSmokeFailed(String)
    case followUpReadMismatch(String)
    case imageMissingAccentPixels(Double)
    case imageMissingBrightPixels(Double)
    case imageTooFlat(Int)
    case imageTooTransparent(Double)
    case htmlMissingResult
    case incompleteTranscript
    case invalidImageSize(Int, Int)
    case nativeAccessibilityActivationFailed([String])
    case nativeAccessibilityFrameSamplingFailed([String])
    case nativeHitTargetAuditFailed([String])
    case pngEncodingFailed
    case renderFailed
    case timedOut
    case toolCardDidNotComplete
    case windowCaptureFailed
    case windowContentTooSmall(Double, Double)
    case windowNotFound
    case windowSurfaceIncomplete(String)
}
