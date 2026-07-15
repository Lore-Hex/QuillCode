import Foundation
import QuillCodeCore

extension AppServerSession {
    func setThreadGoal(_ raw: CLIJSONValue) async throws -> CLIJSONValue {
        let params = try AppServerParams(raw)
        let id = try threadID(from: params)
        var record = try await loadRecord(id)
        let status = try goalStatus(try params.optionalString("status") ?? "active")
        record.thread.goal = try updatedGoal(
            current: record.thread.goal,
            objective: try params.optionalString("objective"),
            status: status
        )
        record.thread.updatedAt = Date()
        try await repository.save(record)

        guard let currentGoal = record.thread.goal else {
            throw AppServerRPCError.internalError("goal disappeared while being updated")
        }
        let goal = goalJSON(currentGoal, threadID: id)
        await sendNotification("thread/goal/updated", params: .object([
            "threadId": .string(AppServerThreadProjection.identifier(id)),
            "turnId": .null,
            "goal": goal
        ]))
        return .object(["goal": goal])
    }

    func getThreadGoal(_ raw: CLIJSONValue) async throws -> CLIJSONValue {
        let params = try AppServerParams(raw)
        let id = try threadID(from: params)
        let record = try await loadRecord(id)
        let goal = record.thread.goal.map { goalJSON($0, threadID: id) } ?? .null
        return .object(["goal": goal])
    }

    func clearThreadGoal(_ raw: CLIJSONValue) async throws -> CLIJSONValue {
        let params = try AppServerParams(raw)
        let id = try threadID(from: params)
        var record = try await loadRecord(id)
        record.thread.goal = nil
        record.thread.updatedAt = Date()
        try await repository.save(record)
        await sendNotification(
            "thread/goal/cleared",
            params: .object(["threadId": .string(AppServerThreadProjection.identifier(id))])
        )
        return .object([:])
    }

    private func updatedGoal(
        current: ThreadGoal?,
        objective: String?,
        status: ThreadGoalStatus
    ) throws -> ThreadGoal {
        if let objective {
            guard let goal = ThreadGoal(objective: objective, status: status) else {
                throw AppServerRPCError.invalidParams("objective must be non-empty")
            }
            return goal
        }
        guard let current else {
            throw AppServerRPCError.invalidParams("objective is required when no goal exists")
        }
        return current.updating(status: status)
    }

    private func goalStatus(_ raw: String) throws -> ThreadGoalStatus {
        guard let status = ThreadGoalStatus(rawValue: raw) else {
            throw AppServerRPCError.invalidParams("status must be active, blocked, or completed")
        }
        return status
    }

    private func goalJSON(_ goal: ThreadGoal, threadID: UUID) -> CLIJSONValue {
        .object([
            "threadId": .string(AppServerThreadProjection.identifier(threadID)),
            "objective": .string(goal.objective),
            "status": .string(goal.status.rawValue),
            "tokenBudget": .null,
            "tokensUsed": .number(0),
            "timeUsedSeconds": .number(max(0, Date().timeIntervalSince(goal.createdAt)).rounded()),
            "createdAt": .number(goal.createdAt.timeIntervalSince1970.rounded(.down)),
            "updatedAt": .number(goal.updatedAt.timeIntervalSince1970.rounded(.down))
        ])
    }
}
