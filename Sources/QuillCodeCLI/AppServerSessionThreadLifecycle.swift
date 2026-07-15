import Foundation
import QuillCodeCore

extension AppServerSession {
    func startThread(_ raw: CLIJSONValue) async throws -> CLIJSONValue {
        let params = try AppServerParams(raw)
        try validateTrustedRouterProvider(in: params)
        try rejectUnsupportedValues(
            ["config", "personality", "serviceName", "serviceTier", "sessionStartSource", "threadSource"],
            in: params
        )
        var settings = try threadSettings(from: params, base: defaultThreadSettings())
        var thread = ChatThread(
            mode: mode(for: settings),
            model: try model(from: params, fallback: request.model ?? appConfig.defaultModel)
        )
        settings.sessionID = thread.id
        try appendInstructions(from: params, to: &thread)

        let record = AppServerThreadRecord(thread: thread, settings: settings)
        try await validateRequiredMCPServers(for: record)
        try await repository.create(record)
        await notifyThreadStarted(record)
        return startOrResumeResponse(record, includeTurns: false, isActive: false)
    }

    func resumeThread(_ raw: CLIJSONValue) async throws -> CLIJSONValue {
        let params = try AppServerParams(raw)
        try validateTrustedRouterProvider(in: params)
        try rejectUnsupportedValues(["config", "personality", "serviceTier"], in: params)
        let id = try threadID(from: params)
        var record = try await loadRecord(id)
        record.settings = try threadSettings(from: params, base: record.settings)
        record.thread.model = try model(from: params, fallback: record.thread.model)
        try appendInstructions(from: params, to: &record.thread)
        record.thread.updatedAt = Date()
        try await validateRequiredMCPServers(for: record)
        try await repository.save(record)
        return startOrResumeResponse(record, includeTurns: true, isActive: activeTurns[id] != nil)
    }

    func forkThread(_ raw: CLIJSONValue) async throws -> CLIJSONValue {
        let params = try AppServerParams(raw)
        try validateTrustedRouterProvider(in: params)
        try rejectUnsupportedValues(["config", "serviceTier", "threadSource"], in: params)
        let sourceID = try threadID(from: params)
        let source = try await loadRecord(sourceID)
        var thread = forkedThread(from: source.thread, sourceID: sourceID)
        thread.model = try model(from: params, fallback: thread.model)
        try appendInstructions(from: params, to: &thread)

        var settings = try threadSettings(from: params, base: source.settings)
        settings.sessionID = source.settings.sessionID ?? sourceID
        settings.forkedFromID = sourceID
        let record = AppServerThreadRecord(thread: thread, settings: settings)
        try await validateRequiredMCPServers(for: record)
        try await repository.create(record)
        await notifyThreadStarted(record)
        return startOrResumeResponse(record, includeTurns: true, isActive: false)
    }

    func setThreadArchived(_ raw: CLIJSONValue, archived: Bool) async throws -> CLIJSONValue {
        let params = try AppServerParams(raw)
        let id = try threadID(from: params)
        guard activeTurns[id] == nil else {
            throw AppServerRPCError.invalidParams("cannot archive an active thread")
        }
        var record = try await loadRecord(id)
        record.thread.isArchived = archived
        record.thread.updatedAt = Date()
        try await repository.save(record)
        await sendNotification(
            archived ? "thread/archived" : "thread/unarchived",
            params: .object(["threadId": .string(AppServerThreadProjection.identifier(id))])
        )
        return .object([:])
    }

    func deleteThread(_ raw: CLIJSONValue) async throws -> CLIJSONValue {
        let params = try AppServerParams(raw)
        let id = try threadID(from: params)
        guard activeTurns[id] == nil else {
            throw AppServerRPCError.invalidParams("cannot delete an active thread")
        }
        _ = try await loadRecord(id)
        try await repository.delete(id)
        await sendNotification(
            "thread/deleted",
            params: .object(["threadId": .string(AppServerThreadProjection.identifier(id))])
        )
        return .object([:])
    }

    func setThreadName(_ raw: CLIJSONValue) async throws -> CLIJSONValue {
        let params = try AppServerParams(raw)
        let id = try threadID(from: params)
        let name = String(try params.requiredString("name").prefix(200))
        var record = try await loadRecord(id)
        record.thread.title = name
        record.thread.updatedAt = Date()
        try await repository.save(record)
        await sendNotification("thread/name/updated", params: .object([
            "threadId": .string(AppServerThreadProjection.identifier(id)),
            "threadName": .string(name)
        ]))
        return .object([:])
    }

    private func forkedThread(from source: ChatThread, sourceID: UUID) -> ChatThread {
        var thread = source
        let now = Date()
        thread.id = UUID()
        thread.createdAt = now
        thread.updatedAt = now
        thread.isArchived = false
        thread.isPinned = false
        thread.forkParentThreadID = sourceID
        return thread
    }

    private func notifyThreadStarted(_ record: AppServerThreadRecord) async {
        await sendNotification("thread/started", params: .object([
            "thread": projectedThread(record, includeTurns: false, isActive: false)
        ]))
    }

    private func startOrResumeResponse(
        _ record: AppServerThreadRecord,
        includeTurns: Bool,
        isActive: Bool
    ) -> CLIJSONValue {
        AppServerThreadProjection.startOrResumeResponse(
            record,
            includeTurns: includeTurns,
            isActive: isActive,
            threadFile: threadFile(for: record.thread.id, ephemeral: record.settings.ephemeral)
        )
    }
}
