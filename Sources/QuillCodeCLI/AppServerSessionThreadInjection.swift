import Foundation
import QuillCodeCore

extension AppServerSession {
    func injectThreadItems(_ raw: CLIJSONValue) async throws -> CLIJSONValue {
        let request = try AppServerThreadInjectItemsRequest(raw)
        var record = try await injectableThreadRecord(
            request.threadID,
            rawThreadID: request.rawThreadID
        )
        let anchor = record.thread.messages.last?.id
        let injected = try request.items.enumerated().map { index, item in
            try AppServerResponseItemValidator.validate(item, index: index)
            return ThreadModelContextItem(
                afterMessageID: anchor,
                responseItem: item.quillJSONValue
            )
        }
        record.thread.modelContextItems.append(contentsOf: injected)
        record.thread.updatedAt = Date()
        try await repository.save(record)
        applyInjectedThread(record.thread, toActiveOperationFor: request.threadID)
        return .object([:])
    }

    private func injectableThreadRecord(
        _ threadID: UUID,
        rawThreadID: String
    ) async throws -> AppServerThreadRecord {
        let record: AppServerThreadRecord
        if let active = activeTurns[threadID] {
            record = AppServerThreadRecord(thread: active.latestThread, settings: active.settings)
        } else if let active = activeCompactions[threadID] {
            record = AppServerThreadRecord(thread: active.latestThread, settings: active.settings)
        } else if let active = activeReviews[threadID] {
            record = AppServerThreadRecord(thread: active.latestThread, settings: active.settings)
        } else if let active = activeUserShellTurns[threadID] {
            record = AppServerThreadRecord(thread: active.latestThread, settings: active.settings)
        } else {
            do {
                record = try await repository.load(threadID)
            } catch {
                throw AppServerRPCError.invalidRequest("thread not found: \(rawThreadID)")
            }
        }
        guard !record.thread.isArchived else {
            throw AppServerRPCError.invalidRequest("thread not found: \(rawThreadID)")
        }
        return record
    }

    private func applyInjectedThread(_ thread: ChatThread, toActiveOperationFor threadID: UUID) {
        if var active = activeTurns[threadID] {
            active.latestThread = thread
            activeTurns[threadID] = active
        } else if var active = activeCompactions[threadID] {
            active.latestThread = thread
            activeCompactions[threadID] = active
        } else if var active = activeReviews[threadID] {
            active.latestThread = thread
            activeReviews[threadID] = active
        } else if var active = activeUserShellTurns[threadID] {
            active.latestThread = thread
            activeUserShellTurns[threadID] = active
        }
    }
}
