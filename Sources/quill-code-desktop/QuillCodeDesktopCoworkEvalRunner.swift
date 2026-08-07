import AppKit
import Foundation
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
        guard request.modelID == QuillCodeDesktopCoworkEvalRequest.exactModelID else {
            throw QuillCodeDesktopCoworkEvalFailure.wrongModel(request.modelID)
        }
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

        controller.setModel(request.modelID)
        let previousTimelineCount = controller.surface.transcript.timelineItems.count
        let started = ContinuousClock.now
        controller.draft = prompt
        controller.send()

        var timedOut = false
        while controller.tasks.isSendRunning(threadID: controller.model.selectedThread?.id)
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
        let ok = !timedOut
            && selectedModelID == request.modelID
            && surface.lastError == nil
            && !finalAnswer.isEmpty
            && !tools.contains(where: { $0.status == "running" })
            && unrecoveredToolFailureCount == 0

        return QuillCodeDesktopCoworkEvalReport(
            ok: ok,
            timedOut: timedOut,
            requestedModelID: request.modelID,
            selectedModelID: selectedModelID,
            prompt: prompt,
            finalAnswer: finalAnswer,
            lastError: surface.lastError,
            browserURL: surface.browser.currentURL,
            workspacePath: request.workspacePath,
            durationMilliseconds: durationMilliseconds,
            usage: usage,
            messageCount: surface.transcript.messages.count,
            timelineItemCount: surface.transcript.timelineItems.count,
            failedToolCount: failedToolCount,
            unrecoveredToolFailureCount: unrecoveredToolFailureCount,
            tools: tools
        )
    }
}

enum QuillCodeDesktopCoworkEvalFailure: Error {
    case browserPreviewFailed(String)
    case emptyPrompt
    case missingPromptPath
    case wrongModel(String)
}
