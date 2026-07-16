import Foundation

extension AppServerSession {
    struct ThreadControlReference {
        var id: UUID
        var rawValue: String
    }

    func markThreadLoaded(
        _ threadID: UUID,
        subscription: AppServerThreadSubscriptionMode
    ) {
        let newlyLoaded = loadedThreadIDs.insert(threadID).inserted
        if newlyLoaded || subscription == .always {
            subscribedThreadIDs.insert(threadID)
        }
    }

    func unsubscribeThread(_ raw: CLIJSONValue) throws -> CLIJSONValue {
        let reference = try threadControlReference(from: raw)
        guard loadedThreadIDs.contains(reference.id) else {
            return .object(["status": .string("notLoaded")])
        }
        let removed = subscribedThreadIDs.remove(reference.id) != nil
        return .object([
            "status": .string(removed ? "unsubscribed" : "notSubscribed")
        ])
    }

    func incrementThreadElicitation(_ raw: CLIJSONValue) async throws -> CLIJSONValue {
        let reference = try threadControlReference(from: raw)
        _ = try await loadThreadControlRecord(reference)
        let (count, overflowed) = outOfBandElicitationCounts[reference.id, default: 0]
            .addingReportingOverflow(1)
        guard !overflowed else {
            throw AppServerRPCError.invalidRequest(
                "out-of-band elicitation count overflow"
            )
        }
        outOfBandElicitationCounts[reference.id] = count
        return elicitationResult(count)
    }

    func decrementThreadElicitation(_ raw: CLIJSONValue) async throws -> CLIJSONValue {
        let reference = try threadControlReference(from: raw)
        _ = try await loadThreadControlRecord(reference)
        let count = outOfBandElicitationCounts[reference.id, default: 0]
        guard count > 0 else {
            throw AppServerRPCError.invalidRequest(
                "out-of-band elicitation count is already zero"
            )
        }
        let updated = count - 1
        outOfBandElicitationCounts[reference.id] = updated == 0 ? nil : updated
        return elicitationResult(updated)
    }

    func setThreadMemoryMode(_ raw: CLIJSONValue) async throws -> CLIJSONValue {
        let params = try AppServerParams(raw)
        let reference = try threadControlReference(from: params)
        var record = try await loadThreadControlRecord(reference)
        guard let rawMode = params.object["mode"]?.stringValue,
              let mode = AppServerThreadMemoryMode(rawValue: rawMode) else {
            let rawMode = params.object["mode"]?.stringValue ?? "null"
            throw AppServerRPCError.invalidRequest(
                "Invalid request: unknown variant `\(rawMode)`, expected `enabled` or `disabled`"
            )
        }
        guard record.settings.effectiveMemoryMode != mode else { return .object([:]) }
        record.settings.memoryMode = mode
        record.thread.updatedAt = Date()
        try await repository.save(record)
        return .object([:])
    }

    func threadControlReference(from raw: CLIJSONValue) throws -> ThreadControlReference {
        try threadControlReference(from: AppServerParams(raw))
    }

    func threadControlReference(from params: AppServerParams) throws -> ThreadControlReference {
        guard let value = params.object["threadId"] else {
            throw AppServerRPCError.invalidRequest("Invalid request: missing field `threadId`")
        }
        guard let rawValue = value.stringValue else {
            throw AppServerRPCError.invalidRequest(
                "Invalid request: invalid type for `threadId`, expected a string"
            )
        }
        guard let id = UUID(uuidString: rawValue) else {
            throw AppServerRPCError.invalidRequest(
                "invalid thread id: invalid length: expected length 32 for simple format, "
                    + "found \(rawValue.count)"
            )
        }
        return ThreadControlReference(id: id, rawValue: rawValue)
    }

    func loadThreadControlRecord(
        _ reference: ThreadControlReference
    ) async throws -> AppServerThreadRecord {
        do {
            return try await repository.load(reference.id)
        } catch {
            throw AppServerRPCError.invalidRequest("thread not found: \(reference.rawValue)")
        }
    }
}

private extension AppServerSession {
    func elicitationResult(_ count: UInt64) -> CLIJSONValue {
        .object([
            "count": .number(Double(count)),
            "paused": .bool(count > 0)
        ])
    }
}
