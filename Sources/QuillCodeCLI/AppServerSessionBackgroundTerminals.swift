import Foundation

extension AppServerSession {
    func cleanBackgroundTerminals(_ raw: CLIJSONValue) async throws -> CLIJSONValue {
        let threadID = try threadID(from: AppServerParams(raw))
        _ = try await loadRecord(threadID)
        requestUserShellCommandTermination { $0.launch.threadID == threadID }
        return .object([:])
    }

    func listBackgroundTerminals(_ raw: CLIJSONValue) async throws -> CLIJSONValue {
        let params = try AppServerParams(raw)
        let threadID = try threadID(from: params)
        _ = try await loadRecord(threadID)
        let cursor = try backgroundTerminalCursor(params.optionalString("cursor"))
        let limit = try backgroundTerminalLimit(params.optionalInt("limit"))
        let terminals = activeUserShellCommands.values.compactMap { command in
            BackgroundTerminal(command: command, threadID: threadID)
        }.sorted { $0.processID < $1.processID }

        let start = cursor.flatMap { cursor in
            terminals.firstIndex { $0.processID > cursor }
        } ?? (cursor == nil ? 0 : terminals.count)
        let pageLimit = max(1, limit ?? terminals.count)
        let end = min(terminals.count, start.saturatingAdd(pageLimit))
        let page = Array(terminals[start..<end])
        let nextCursor = end < terminals.count ? page.last?.processID.description : nil
        return .object([
            "data": .array(page.map(\.value)),
            "nextCursor": nextCursor.map(CLIJSONValue.string) ?? .null
        ])
    }

    func terminateBackgroundTerminal(_ raw: CLIJSONValue) async throws -> CLIJSONValue {
        let params = try AppServerParams(raw)
        let threadID = try threadID(from: params)
        _ = try await loadRecord(threadID)
        let rawProcessID = try params.requiredString("processId")
        guard let processID = Int32(rawProcessID) else {
            throw AppServerRPCError.invalidRequest(
                "invalid background terminal process id: expected a 32-bit signed integer"
            )
        }
        let terminated = requestUserShellCommandTermination { command in
            command.launch.threadID == threadID
                && command.session?.processIdentifier == processID
        } > 0
        return .object(["terminated": .bool(terminated)])
    }

    private func backgroundTerminalCursor(_ raw: String?) throws -> Int32? {
        guard let raw else { return nil }
        guard let cursor = Int32(raw) else {
            throw AppServerRPCError.invalidRequest(
                "invalid cursor: expected a 32-bit signed integer"
            )
        }
        return cursor
    }

    private func backgroundTerminalLimit(_ raw: Int?) throws -> Int? {
        guard let raw else { return nil }
        guard raw >= 0, UInt64(raw) <= UInt64(UInt32.max) else {
            throw AppServerRPCError.invalidParams(
                "limit must be an unsigned 32-bit integer or null"
            )
        }
        return raw
    }
}

private struct BackgroundTerminal {
    var itemID: String
    var processID: Int32
    var command: String
    var cwd: URL

    init?(command: AppServerSession.ActiveUserShellCommand, threadID: UUID) {
        guard command.launch.threadID == threadID,
              !command.terminationRequested,
              let processID = command.session?.processIdentifier else { return nil }
        self.itemID = command.launch.itemID
        self.processID = processID
        self.command = command.launch.command
        self.cwd = command.launch.cwd
    }

    var value: CLIJSONValue {
        .object([
            "itemId": .string(itemID),
            "processId": .string(processID.description),
            "command": .string(command),
            "cwd": .string(cwd.path),
            "osPid": .number(Double(processID)),
            "cpuPercent": .null,
            "rssKb": .null
        ])
    }
}

private extension Int {
    func saturatingAdd(_ other: Int) -> Int {
        let (sum, overflow) = addingReportingOverflow(other)
        return overflow ? Int.max : sum
    }
}
