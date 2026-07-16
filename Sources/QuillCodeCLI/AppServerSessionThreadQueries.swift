import Foundation

extension AppServerSession {
    func listThreads(_ raw: CLIJSONValue) async throws -> CLIJSONValue {
        let params = try AppServerParams(raw)
        guard try includesTrustedRouter(params), try includesAppServerSource(params) else {
            return emptyThreadPage
        }

        let query = try threadListQuery(params)
        var records = await repository.list().filter { query.includes($0) }
        records.sort { query.precedes($0, $1) }

        let offset = try decodeCursor(try params.optionalString("cursor"))
        let requestedLimit = try params.optionalInt("limit") ?? 20
        guard requestedLimit > 0 else {
            throw AppServerRPCError.invalidParams("limit must be greater than zero")
        }
        let limit = min(100, requestedLimit)
        let page = Array(records.dropFirst(offset).prefix(limit))
        let nextOffset = offset + page.count
        return .object([
            "data": .array(page.map { record in
                projectedThread(record, includeTurns: false, isActive: hasActiveOperation(for: record.thread.id))
            }),
            "nextCursor": cursorValue(nextOffset < records.count ? nextOffset : nil),
            "backwardsCursor": cursorValue(offset > 0 ? max(0, offset - limit) : nil)
        ])
    }

    func readThread(_ raw: CLIJSONValue) async throws -> CLIJSONValue {
        let params = try AppServerParams(raw)
        let id = try threadID(from: params)
        let record = try await loadRecord(id)
        return .object([
            "thread": projectedThread(
                record,
                includeTurns: try params.optionalBool("includeTurns") ?? false,
                isActive: hasActiveOperation(for: id)
            )
        ])
    }

    func projectedThread(
        _ record: AppServerThreadRecord,
        includeTurns: Bool,
        isActive: Bool
    ) -> CLIJSONValue {
        AppServerThreadProjection.thread(
            record,
            includeTurns: includeTurns,
            isActive: isActive,
            threadFile: threadFile(for: record.thread.id, ephemeral: record.settings.ephemeral)
        )
    }

    private var emptyThreadPage: CLIJSONValue {
        .object(["data": .array([]), "nextCursor": .null, "backwardsCursor": .null])
    }

    private func includesTrustedRouter(_ params: AppServerParams) throws -> Bool {
        let filters = try stringArray("modelProviders", from: params)
        return filters.isEmpty || filters.contains("trustedrouter")
    }

    private func includesAppServerSource(_ params: AppServerParams) throws -> Bool {
        let filters = try stringArray("sourceKinds", from: params)
        let supported = Set([
            "cli", "vscode", "exec", "appServer", "subAgent", "subAgentReview",
            "subAgentCompact", "subAgentThreadSpawn", "subAgentOther", "unknown"
        ])
        guard filters.allSatisfy(supported.contains) else {
            throw AppServerRPCError.invalidParams("sourceKinds contains an unsupported source kind")
        }
        return filters.isEmpty || filters.contains("appServer")
    }

    private func stringArray(_ key: String, from params: AppServerParams) throws -> [String] {
        try (params.optionalArray(key) ?? []).map { value in
            guard let string = value.stringValue else {
                throw AppServerRPCError.invalidParams("\(key) must contain strings")
            }
            return string
        }
    }

    private func threadListQuery(_ params: AppServerParams) throws -> AppServerThreadListQuery {
        _ = try params.optionalBool("useStateDbOnly")
        let sortKey = try params.optionalString("sortKey") ?? "created_at"
        guard ["created_at", "updated_at", "recency_at"].contains(sortKey) else {
            throw AppServerRPCError.invalidParams("sortKey is not supported")
        }
        let sortDirection = try params.optionalString("sortDirection") ?? "desc"
        guard ["asc", "desc"].contains(sortDirection) else {
            throw AppServerRPCError.invalidParams("sortDirection is not supported")
        }
        return AppServerThreadListQuery(
            archived: try params.optionalBool("archived") ?? false,
            searchTerm: try params.optionalString("searchTerm"),
            cwdFilters: try cwdFilters(from: params.object["cwd"]),
            sortKey: sortKey,
            ascending: sortDirection == "asc"
        )
    }

    private func cwdFilters(from value: CLIJSONValue?) throws -> Set<String> {
        guard let value, value != .null else { return [] }
        if let string = value.stringValue {
            return [URL(fileURLWithPath: string).standardizedFileURL.path]
        }
        guard let array = value.arrayValue else {
            throw AppServerRPCError.invalidParams("cwd must be a string, array, or null")
        }
        return Set(try array.map { item in
            guard let string = item.stringValue else {
                throw AppServerRPCError.invalidParams("cwd array must contain strings")
            }
            return URL(fileURLWithPath: string).standardizedFileURL.path
        })
    }

    private func cursorValue(_ offset: Int?) -> CLIJSONValue {
        offset.map { .string(encodeCursor($0)) } ?? .null
    }

    private func encodeCursor(_ offset: Int) -> String {
        Data("offset:\(offset)".utf8).base64EncodedString()
    }

    private func decodeCursor(_ cursor: String?) throws -> Int {
        guard let cursor else { return 0 }
        guard let data = Data(base64Encoded: cursor),
              let text = String(data: data, encoding: .utf8),
              text.hasPrefix("offset:"),
              let offset = Int(text.dropFirst("offset:".count)),
              offset >= 0 else {
            throw AppServerRPCError.invalidParams("cursor is invalid")
        }
        return offset
    }
}

private struct AppServerThreadListQuery {
    let archived: Bool
    let searchTerm: String?
    let cwdFilters: Set<String>
    let sortKey: String
    let ascending: Bool

    init(
        archived: Bool,
        searchTerm: String?,
        cwdFilters: Set<String>,
        sortKey: String,
        ascending: Bool
    ) {
        self.archived = archived
        self.searchTerm = searchTerm?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        self.cwdFilters = cwdFilters
        self.sortKey = sortKey
        self.ascending = ascending
    }

    func includes(_ record: AppServerThreadRecord) -> Bool {
        guard record.thread.isArchived == archived else { return false }
        if !cwdFilters.isEmpty, !cwdFilters.contains(record.settings.cwd.path) { return false }
        guard let searchTerm, !searchTerm.isEmpty else { return true }
        return record.thread.title.lowercased().contains(searchTerm)
    }

    func precedes(_ lhs: AppServerThreadRecord, _ rhs: AppServerThreadRecord) -> Bool {
        let usesRecency = sortKey == "updated_at" || sortKey == "recency_at"
        let left = usesRecency ? lhs.thread.updatedAt : lhs.thread.createdAt
        let right = usesRecency ? rhs.thread.updatedAt : rhs.thread.createdAt
        return ascending ? left < right : left > right
    }
}
