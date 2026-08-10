import Foundation
import QuillCodeTools

enum WorkspaceTerminalRetentionPolicy {
    static let maximumEntryCount = 100
    static let maximumOutputLines = 2_200
    static let maximumOutputBytes = 64_000

    static func cap(_ text: String) -> String {
        ShellOutputCapper.cap(
            text,
            maxLines: maximumOutputLines,
            maxBytes: maximumOutputBytes
        ).text
    }

    static func prepareForNewEntry(terminal: inout TerminalState) {
        while terminal.entries.count >= maximumEntryCount {
            guard let removableIndex = terminal.entries.firstIndex(where: { $0.status != .running }) else {
                return
            }
            terminal.entries.remove(at: removableIndex)
            terminal.discardedEntryCount = saturatingIncrement(terminal.discardedEntryCount)
        }
    }

    static func normalizedInitialEntries(
        _ entries: [TerminalCommandState],
        discardedEntryCount: Int
    ) -> (entries: [TerminalCommandState], discardedEntryCount: Int) {
        var retained = entries
        var discarded = max(0, discardedEntryCount)
        while retained.count > maximumEntryCount {
            let removableIndex = retained.firstIndex(where: { $0.status != .running })
                ?? retained.startIndex
            retained.remove(at: removableIndex)
            discarded = saturatingIncrement(discarded)
        }
        return (retained, discarded)
    }

    static func retentionNotice(discardedEntryCount: Int) -> String? {
        guard discardedEntryCount > 0 else { return nil }
        let noun = discardedEntryCount == 1 ? "command" : "commands"
        return "\(discardedEntryCount) older \(noun) released to keep terminal memory bounded."
    }

    private static func saturatingIncrement(_ value: Int) -> Int {
        value == Int.max ? value : value + 1
    }
}

extension TerminalCommandState {
    mutating func appendLiveOutput(stdout: String, stderr: String) {
        if !stdout.isEmpty {
            liveStdout.append(stdout)
        }
        if !stderr.isEmpty {
            liveStderr.append(stderr)
        }
    }

    mutating func finishOutput(
        stdout: String,
        stderr: String,
        exitCode: Int32?,
        ok: Bool,
        status: TerminalCommandStatus
    ) {
        retainedStdout = WorkspaceTerminalRetentionPolicy.cap(stdout)
        retainedStderr = WorkspaceTerminalRetentionPolicy.cap(stderr)
        self.exitCode = exitCode
        self.ok = ok
        self.status = status
        releaseLiveOutputBuffers()
    }

    mutating func releaseLiveOutputBuffers() {
        liveStdout = ShellOutputAccumulator()
        liveStderr = ShellOutputAccumulator()
    }

    mutating func freezeLiveOutput() {
        retainedStdout = liveStdout.text
        retainedStderr = liveStderr.text
    }

    mutating func stopOutput(message: String) {
        freezeLiveOutput()
        status = .stopped
        if retainedStderr.isEmpty {
            retainedStderr = WorkspaceTerminalRetentionPolicy.cap(message)
        }
        exitCode = nil
        ok = false
        releaseLiveOutputBuffers()
    }
}
