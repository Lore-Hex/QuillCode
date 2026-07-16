import Foundation
import QuillCodeCore

extension AppServerSession {
    func rollbackThread(_ raw: CLIJSONValue) async throws -> CLIJSONValue {
        let params = try AppServerParams(raw)
        let rawThreadID = try params.requiredString("threadId")
        let turnCount = try rollbackTurnCount(params)
        guard let threadID = UUID(uuidString: rawThreadID) else {
            throw AppServerRPCError.invalidRequest("invalid thread id: \(rawThreadID)")
        }
        if activeRollbacks.contains(threadID) {
            throw AppServerRPCError.invalidRequest("rollback already in progress for this thread")
        }
        guard activeTurns[threadID] == nil, activeCompactions[threadID] == nil else {
            throw AppServerRPCError.invalidRequest("Cannot rollback while a turn is in progress.")
        }

        activeRollbacks.insert(threadID)
        defer { activeRollbacks.remove(threadID) }

        let record: AppServerThreadRecord
        do {
            record = try await repository.load(threadID)
        } catch {
            throw AppServerRPCError.invalidRequest("thread not found: \(rawThreadID)")
        }

        var thread = record.thread
        ThreadHistoryRollback.apply(turnCount: turnCount, to: &thread)
        do {
            try await repository.saveThread(thread)
        } catch {
            throw AppServerRPCError.internalError(
                "failed to persist thread rollback: \(error.localizedDescription)"
            )
        }

        let updated = AppServerThreadRecord(thread: thread, settings: record.settings)
        return .object([
            "thread": projectedThread(updated, includeTurns: true, isActive: false)
        ])
    }

    private func rollbackTurnCount(_ params: AppServerParams) throws -> UInt32 {
        guard let value = try params.optionalInt("numTurns") else {
            throw AppServerRPCError.invalidParams("numTurns is required")
        }
        guard value >= 0, value <= Int(UInt32.max) else {
            throw AppServerRPCError.invalidParams("numTurns must be an unsigned 32-bit integer")
        }
        guard value > 0 else {
            throw AppServerRPCError.invalidRequest("numTurns must be >= 1")
        }
        return UInt32(value)
    }
}
