import Foundation

/// Session-only ownership for agent work that can continue independently in multiple chats.
///
/// Conversation state remains in `ChatThread`; this registry only answers which threads currently
/// own a live task and which status should be projected when one of those threads is selected.
public struct WorkspaceAgentRunRegistry: Sendable, Hashable {
    private var statusesByThreadID: [UUID: String]

    public init(statusesByThreadID: [UUID: String] = [:]) {
        self.statusesByThreadID = statusesByThreadID
    }

    public var activeThreadIDs: Set<UUID> {
        Set(statusesByThreadID.keys)
    }

    public var activeCount: Int {
        statusesByThreadID.count
    }

    public func isRunning(_ threadID: UUID?) -> Bool {
        threadID.map { statusesByThreadID[$0] != nil } ?? false
    }

    public func status(for threadID: UUID?) -> String? {
        threadID.flatMap { statusesByThreadID[$0] }
    }

    @discardableResult
    public mutating func begin(threadID: UUID, status: String) -> Bool {
        let inserted = statusesByThreadID[threadID] == nil
        statusesByThreadID[threadID] = status
        return inserted
    }

    public mutating func update(threadID: UUID, status: String) {
        guard statusesByThreadID[threadID] != nil else { return }
        statusesByThreadID[threadID] = status
    }

    @discardableResult
    public mutating func finish(threadID: UUID) -> String? {
        statusesByThreadID.removeValue(forKey: threadID)
    }

    @discardableResult
    public mutating func finishAll() -> Bool {
        guard !statusesByThreadID.isEmpty else { return false }
        statusesByThreadID.removeAll(keepingCapacity: true)
        return true
    }
}
