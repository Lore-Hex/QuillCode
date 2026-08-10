import Foundation

@MainActor
enum QuillCodeDesktopTerminalRetentionSmoke {
    private static let command = "printf live-start; sleep 0.2; yes terminal-tail | head -n 40000"
    private static let maximumPublishedOutputBytes = 70_000
    private static let pollIntervalNanoseconds: UInt64 = 10_000_000
    private static let maximumPollCount = 1_000

    static func verify(controller: QuillCodeDesktopController) async throws {
        controller.terminalDraft = command
        controller.runTerminalCommand()

        try await waitForLiveOutput(controller: controller)
        try await waitForCompletion(controller: controller)

        guard let entry = controller.surface.terminal.entries.last else {
            throw Failure.missingEntry
        }
        guard entry.statusLabel == "Done" else {
            throw Failure.unexpectedStatus(entry.statusLabel)
        }
        let outputEndsWithTail = entry.stdout
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .hasSuffix("terminal-tail")
        let outputContainsTruncationNotice = entry.stdout.contains("output truncated")
        let outputByteCount = entry.stdout.utf8.count
        guard outputContainsTruncationNotice,
              outputEndsWithTail,
              outputByteCount < maximumPublishedOutputBytes else {
            throw Failure.unexpectedOutput(
                byteCount: outputByteCount,
                containsTruncationNotice: outputContainsTruncationNotice,
                endsWithTail: outputEndsWithTail
            )
        }

        guard controller.model.clearTerminalHistory() else {
            throw Failure.couldNotClearHistory
        }
        controller.model.setTerminalVisible(false)
        controller.refresh()
    }

    private static func waitForLiveOutput(controller: QuillCodeDesktopController) async throws {
        for _ in 0..<maximumPollCount {
            if let entry = controller.surface.terminal.entries.last,
               entry.isRunning,
               entry.stdout.contains("live-start") {
                return
            }
            try await Task.sleep(nanoseconds: pollIntervalNanoseconds)
        }
        throw Failure.liveOutputTimedOut
    }

    private static func waitForCompletion(controller: QuillCodeDesktopController) async throws {
        for _ in 0..<maximumPollCount {
            if !controller.surface.terminal.isRunning,
               controller.surface.terminal.entries.last?.isRunning == false {
                return
            }
            try await Task.sleep(nanoseconds: pollIntervalNanoseconds)
        }
        throw Failure.completionTimedOut
    }

    private enum Failure: LocalizedError {
        case completionTimedOut
        case couldNotClearHistory
        case liveOutputTimedOut
        case missingEntry
        case unexpectedOutput(
            byteCount: Int,
            containsTruncationNotice: Bool,
            endsWithTail: Bool
        )
        case unexpectedStatus(String)

        var errorDescription: String? {
            switch self {
            case .completionTimedOut:
                return "Terminal retention smoke timed out waiting for completion."
            case .couldNotClearHistory:
                return "Terminal retention smoke could not clear completed history."
            case .liveOutputTimedOut:
                return "Terminal retention smoke never published live output."
            case .missingEntry:
                return "Terminal retention smoke did not publish a command entry."
            case .unexpectedOutput(let byteCount, let containsTruncationNotice, let endsWithTail):
                return "Terminal retention smoke published unexpected output "
                    + "(\(byteCount) bytes, truncation notice: \(containsTruncationNotice), "
                    + "newest tail: \(endsWithTail))."
            case .unexpectedStatus(let status):
                return "Terminal retention smoke finished with status \(status)."
            }
        }
    }
}
