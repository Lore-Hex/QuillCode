import Foundation

struct WorkspaceSubagentTranscriptCommand: Equatable, Sendable {
    private static let openPrefix = "activity-subagent-open:"

    var parentThreadID: UUID
    var runID: UUID
    var workerID: String

    init?(commandID: String) {
        guard commandID.hasPrefix(Self.openPrefix) else { return nil }
        let components = commandID.dropFirst(Self.openPrefix.count).split(separator: ":", maxSplits: 2)
        guard components.count == 3,
              let parentThreadID = UUID(uuidString: String(components[0])),
              let runID = UUID(uuidString: String(components[1]))
        else { return nil }
        let workerID = String(components[2]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !workerID.isEmpty else { return nil }
        self.parentThreadID = parentThreadID
        self.runID = runID
        self.workerID = workerID
    }

    static func openCommandID(parentThreadID: UUID, runID: UUID, workerID: String) -> String {
        "\(openPrefix)\(parentThreadID.uuidString):\(runID.uuidString):\(workerID)"
    }
}
