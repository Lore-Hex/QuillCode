import AppKit
import Foundation
import QuillCodeAgent
import QuillCodeApp
import QuillCodeCore

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
        let screenshot = try await captureFinalWindow(to: request.screenshotPath)
        let ok = !timedOut
            && (stopReason == .finished || scheduledAutomation != nil)
            && selectedModelID == request.modelID
            && runIsConfidential == request.isConfidential
            && surface.lastError == nil
            && !finalAnswer.isEmpty
            && !tools.contains(where: { $0.status == "running" })
            && unrecoveredToolFailureCount == 0

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
            screenshot: screenshot,
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
        to screenshotPath: String?
    ) async throws -> QuillCodeDesktopCoworkEvalReport.Screenshot? {
        guard let screenshotPath, !screenshotPath.isEmpty else { return nil }

        NSApplication.shared.activate(ignoringOtherApps: true)
        var window: NSWindow?
        for _ in 0..<40 {
            window = NSApplication.shared.windows.first(where: { candidate in
                candidate.isVisible
                    && candidate.contentView != nil
                    && candidate.frame.width >= 900
                    && candidate.frame.height >= 620
            })
            if window != nil { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        guard let window, let contentView = window.contentView else {
            throw QuillCodeDesktopSmokeFailure.windowNotFound
        }

        window.makeKeyAndOrderFront(nil)
        window.displayIfNeeded()
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

enum QuillCodeDesktopCoworkEvalFailure: Error {
    case browserPreviewFailed(String)
    case emptyPrompt
    case missingPromptPath
}
