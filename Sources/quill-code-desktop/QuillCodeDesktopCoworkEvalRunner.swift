import AppKit
import Foundation
import QuillCodeAgent
import QuillCodeApp
import QuillCodeCore
import SwiftUI

@MainActor
enum QuillCodeDesktopCoworkEvalRunner {
    static func runAndExit(
        _ request: QuillCodeDesktopCoworkEvalRequest,
        controller: QuillCodeDesktopController
    ) async {
        do {
            let report = try await run(request, controller: controller)
            let data = try report.prettyJSON()
            if let reportPath = request.reportPath, !reportPath.isEmpty {
                let reportURL = URL(fileURLWithPath: reportPath)
                try FileManager.default.createDirectory(
                    at: reportURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try data.write(to: reportURL, options: .atomic)
            }
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data("\n".utf8))
            exit(report.ok ? 0 : 1)
        } catch {
            FileHandle.standardError.write(Data("quill-code-desktop cowork eval failed: \(error)\n".utf8))
            exit(1)
        }
    }

    static func run(
        _ request: QuillCodeDesktopCoworkEvalRequest,
        controller: QuillCodeDesktopController
    ) async throws -> QuillCodeDesktopCoworkEvalReport {
        guard !request.promptPath.isEmpty else {
            throw QuillCodeDesktopCoworkEvalFailure.missingPromptPath
        }

        let prompt = try String(contentsOfFile: request.promptPath, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else {
            throw QuillCodeDesktopCoworkEvalFailure.emptyPrompt
        }

        let physicalWindow = try await QuillCodeDesktopCoworkEvalWindow.acquire(
            controller: controller
        )

        if let browserPath = request.browserPath, !browserPath.isEmpty {
            controller.browserAddressDraft = browserPath
            controller.openBrowserPreview()
            guard controller.surface.browser.currentURL != nil else {
                throw QuillCodeDesktopCoworkEvalFailure.browserPreviewFailed(browserPath)
            }
            while controller.tasks.isRunning(.browserPreview) {
                try await Task.sleep(for: .milliseconds(50))
            }
        }

        if request.isConfidential {
            controller.model.newConfidentialChat(projectID: controller.model.selectedProject?.id)
            controller.refresh()
        } else {
            controller.setModel(request.modelID)
        }
        let runIsConfidential = controller.model.selectedThread?.runtimeContext.isConfidential == true
        let previousTimelineCount = controller.surface.transcript.timelineItems.count
        let existingAutomationIDs = Set(controller.model.automations.items.map(\.id))
        let started = ContinuousClock.now
        controller.draft = prompt
        controller.send()
        let runThreadID = controller.model.selectedThread?.id

        var timedOut = false
        while controller.tasks.isSendRunning(threadID: runThreadID)
            || controller.surface.composer.isSending
            || controller.surface.transcript.timelineItems.count <= previousTimelineCount {
            if started.duration(to: .now) >= .seconds(request.timeoutSeconds) {
                timedOut = true
                controller.stopAll()
                break
            }
            try await Task.sleep(for: .milliseconds(100))
        }

        let surface = controller.surface
        let finalAnswer = surface.transcript.messages.last(where: { $0.role == .assistant })?.text ?? ""
        let tools = surface.transcript.toolCards.map {
            QuillCodeDesktopCoworkEvalReport.Tool(
                name: $0.title,
                status: $0.status.rawValue,
                inputJSON: $0.inputJSON,
                outputJSON: $0.outputJSON
            )
        }
        let usage = controller.model.selectedThread?.events.compactMap(ModelTokenUsageEvent.usage(from:))
            .reduce(into: ModelTokenUsage()) { total, next in
                total.promptTokens += next.promptTokens
                total.completionTokens += next.completionTokens
                total.totalTokens += next.totalTokens
            } ?? ModelTokenUsage()
        let selectedModelID = surface.topBar.selectedModelID
        let elapsed = started.duration(to: .now).components
        let durationMilliseconds = Int(elapsed.seconds * 1_000)
            + Int(elapsed.attoseconds / 1_000_000_000_000_000)
        let failedToolCount = tools.count(where: { $0.status == "failed" })
        let unrecoveredToolFailureCount = QuillCodeDesktopCoworkEvalReport.unrecoveredFailureCount(in: tools)
        let stopReason = controller.model.lastAgentRunStopReason(for: runThreadID)
        let scheduledAutomation = controller.model.automations.items
            .first(where: { !existingAutomationIDs.contains($0.id) })
            .map(QuillCodeDesktopCoworkEvalReport.ScheduledAutomation.init)
        let stopReasonFields = scheduledAutomation.map {
            (name: Optional("scheduled"), detail: Optional($0.scheduleDescription))
        } ?? QuillCodeDesktopCoworkEvalReport.stopReasonFields(stopReason)
        let screenshot: QuillCodeDesktopCoworkEvalReport.Screenshot?
        let desktopCaptureError: String?
        do {
            screenshot = try await captureFinalWindow(
                physicalWindow.window,
                to: request.screenshotPath
            )
            desktopCaptureError = nil
        } catch {
            screenshot = nil
            desktopCaptureError = String(describing: error)
        }
        let workspaceWindowCount = QuillCodeDesktopCoworkEvalWindow.visibleWindowCount
        let ok = !timedOut
            && (stopReason == .finished || scheduledAutomation != nil)
            && selectedModelID == request.modelID
            && runIsConfidential == request.isConfidential
            && surface.lastError == nil
            && !finalAnswer.isEmpty
            && !tools.contains(where: { $0.status == "running" })
            && unrecoveredToolFailureCount == 0
            && desktopCaptureError == nil
            && workspaceWindowCount == 1

        return QuillCodeDesktopCoworkEvalReport(
            ok: ok,
            timedOut: timedOut,
            stopReason: stopReasonFields.name,
            stopReasonDetail: stopReasonFields.detail,
            requestedModelID: request.modelID,
            selectedModelID: selectedModelID,
            isConfidential: runIsConfidential,
            prompt: prompt,
            finalAnswer: finalAnswer,
            lastError: surface.lastError,
            browserURL: surface.browser.currentURL,
            workspacePath: request.workspacePath,
            windowSource: physicalWindow.source.rawValue,
            workspaceWindowCount: workspaceWindowCount,
            screenshot: screenshot,
            desktopCaptureError: desktopCaptureError,
            scheduledAutomation: scheduledAutomation,
            durationMilliseconds: durationMilliseconds,
            usage: usage,
            messageCount: surface.transcript.messages.count,
            timelineItemCount: surface.transcript.timelineItems.count,
            failedToolCount: failedToolCount,
            unrecoveredToolFailureCount: unrecoveredToolFailureCount,
            tools: tools
        )
    }

    private static func captureFinalWindow(
        _ window: NSWindow,
        to screenshotPath: String?
    ) async throws -> QuillCodeDesktopCoworkEvalReport.Screenshot? {
        guard let screenshotPath, !screenshotPath.isEmpty else { return nil }

        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        window.displayIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        guard let contentView = window.contentView else {
            throw QuillCodeDesktopSmokeFailure.windowNotFound
        }
        contentView.layoutSubtreeIfNeeded()
        let bounds = contentView.bounds.integral
        guard bounds.width >= 900, bounds.height >= 620 else {
            throw QuillCodeDesktopSmokeFailure.windowContentTooSmall(bounds.width, bounds.height)
        }
        guard let bitmap = contentView.bitmapImageRepForCachingDisplay(in: bounds) else {
            throw QuillCodeDesktopSmokeFailure.windowCaptureFailed
        }
        contentView.cacheDisplay(in: bounds, to: bitmap)
        guard let image = bitmap.cgImage else {
            throw QuillCodeDesktopSmokeFailure.windowCaptureFailed
        }
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw QuillCodeDesktopSmokeFailure.pngEncodingFailed
        }

        let screenshotURL = URL(fileURLWithPath: screenshotPath)
        try FileManager.default.createDirectory(
            at: screenshotURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: screenshotURL, options: .atomic)

        let stats = try QuillCodeDesktopSmokePixelStats(image: image)
        try stats.validate(
            expectedWidth: image.width,
            expectedHeight: image.height,
            minDistinctColorBuckets: 14,
            minBrightPixelRatio: 0.0005,
            minAccentPixelRatio: 0
        )
        let report = stats.report
        return QuillCodeDesktopCoworkEvalReport.Screenshot(
            path: screenshotURL.path,
            width: report.width,
            height: report.height,
            opaquePixelRatio: report.opaquePixelRatio,
            brightPixelRatio: report.brightPixelRatio,
            accentPixelRatio: report.accentPixelRatio,
            distinctColorBuckets: report.distinctColorBuckets
        )
    }
}

@MainActor
enum QuillCodeDesktopCoworkEvalWindow {
    enum Source: String, Equatable {
        case swiftUIScene = "swiftui-scene"
        case evalFallback = "eval-native-fallback"
    }

    struct PhysicalWindow {
        var window: NSWindow
        var source: Source
    }

    private static var retainedFallbackWindow: NSWindow?

    static var visibleWindowCount: Int {
        NSApplication.shared.windows.count(where: isWorkspaceWindow)
    }

    static func acquire(
        controller: QuillCodeDesktopController,
        sceneSettleAttempts: Int = 10
    ) async throws -> PhysicalWindow {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)

        for _ in 0..<sceneSettleAttempts {
            if let window = NSApplication.shared.windows.first(where: isWorkspaceWindow) {
                window.makeKeyAndOrderFront(nil)
                window.orderFrontRegardless()
                let source: Source = window === retainedFallbackWindow ? .evalFallback : .swiftUIScene
                return PhysicalWindow(window: window, source: source)
            }
            try await Task.sleep(for: .milliseconds(100))
        }

        let rootView = QuillCodeDesktopRootView(controller: controller)
            .frame(minWidth: 1280, minHeight: 900)
        return retainFallbackWindow(contentView: NSHostingView(rootView: rootView))
    }

    static func retainFallbackForTesting(contentView: NSView) -> PhysicalWindow {
        retainFallbackWindow(contentView: contentView)
    }

    static func releaseFallbackForTesting() {
        retainedFallbackWindow?.close()
        retainedFallbackWindow = nil
    }

    private static func retainFallbackWindow(contentView: NSView) -> PhysicalWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 900),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = QuillCodeProduct.displayName
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.contentView = contentView
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        retainedFallbackWindow = window
        return PhysicalWindow(window: window, source: .evalFallback)
    }

    private static func isWorkspaceWindow(_ window: NSWindow) -> Bool {
        guard window.isVisible, window.title == QuillCodeProduct.displayName else {
            return false
        }
        guard let contentView = window.contentView else { return false }
        return contentView.bounds.width >= 900 && contentView.bounds.height >= 620
    }
}

enum QuillCodeDesktopCoworkEvalFailure: Error {
    case browserPreviewFailed(String)
    case emptyPrompt
    case missingPromptPath
}
