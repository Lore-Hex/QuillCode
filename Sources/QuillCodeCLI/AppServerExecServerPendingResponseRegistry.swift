struct AppServerExecServerPendingResponseRegistry {
    struct PendingResponse: Sendable {
        var generation: UInt64
        var continuation: AsyncThrowingStream<CLIJSONValue, Error>.Continuation
    }

    private var pendingResponses: [Int64: PendingResponse] = [:]
    private var abandonedResponseIDs: Set<Int64> = []

    var abandonedCount: Int {
        abandonedResponseIDs.count
    }

    mutating func register(
        requestID: Int64,
        generation: UInt64,
        continuation: AsyncThrowingStream<CLIJSONValue, Error>.Continuation
    ) throws {
        guard abandonedResponseIDs.contains(requestID) == false else {
            throw AppServerExecServerError.invalidResponse(
                "request id \(requestID) is still waiting for an abandoned response"
            )
        }
        guard pendingResponses[requestID] == nil else {
            throw AppServerExecServerError.invalidResponse(
                "duplicate pending response for request id \(requestID)"
            )
        }
        pendingResponses[requestID] = PendingResponse(
            generation: generation,
            continuation: continuation
        )
    }

    mutating func abandon(_ requestID: Int64) -> Bool {
        guard pendingResponses[requestID] != nil else { return false }
        abandonedResponseIDs.insert(requestID)
        return true
    }

    mutating func take(_ requestID: Int64) throws -> PendingResponse? {
        if abandonedResponseIDs.remove(requestID) != nil {
            pendingResponses.removeValue(forKey: requestID)?.continuation.finish()
            return nil
        }
        if let pending = pendingResponses.removeValue(forKey: requestID) {
            return pending
        }
        throw AppServerExecServerError.invalidResponse(
            "received response for unexpected request id \(requestID)"
        )
    }

    mutating func finish(_ requestID: Int64) {
        pendingResponses.removeValue(forKey: requestID)?.continuation.finish()
    }

    mutating func failAll(throwing error: Error) {
        for pending in pendingResponses.values {
            pending.continuation.finish(throwing: error)
        }
        pendingResponses.removeAll()
        abandonedResponseIDs.removeAll()
    }
}
