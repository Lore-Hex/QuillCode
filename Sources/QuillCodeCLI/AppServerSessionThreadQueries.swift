import Foundation
import QuillCodeCore

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

    func searchThreads(_ raw: CLIJSONValue) async throws -> CLIJSONValue {
        let request = try AppServerThreadSearchRequest(raw)
        let searchTerm = request.searchTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !searchTerm.isEmpty else {
            throw AppServerRPCError.invalidRequest(
                "thread/search requires a non-empty searchTerm"
            )
        }
        guard request.includesAppServerSource else { return emptyThreadSearchPage }

        var matches = await repository.list().compactMap { record -> AppServerThreadSearchMatch? in
            guard record.thread.isArchived == request.archived,
                  let snippet = AppServerThreadSearchSnippet.match(
                      searchTerm,
                      in: record.thread
                  ) else { return nil }
            return AppServerThreadSearchMatch(record: record, snippet: snippet)
        }
        matches.sort { request.sort.precedes($0.record, $1.record) }

        let page = try AppServerThreadPagination.anchoredPage(
            matches,
            cursor: request.cursor,
            requestedLimit: request.limit,
            cursorIDKey: "threadId",
            anchorDescription: "thread",
            identifier: { AppServerThreadProjection.identifier($0.record.thread.id) }
        )
        return .object([
            "data": .array(page.data.map { match in
                .object([
                    "thread": projectedThread(
                        match.record,
                        includeTurns: false,
                        isActive: hasActiveOperation(for: match.record.thread.id)
                    ),
                    "snippet": .string(match.snippet)
                ])
            }),
            "nextCursor": page.nextCursor.map(CLIJSONValue.string) ?? .null,
            "backwardsCursor": page.backwardsCursor.map(CLIJSONValue.string) ?? .null
        ])
    }

    func listLoadedThreads(_ raw: CLIJSONValue) throws -> CLIJSONValue {
        let params = try AppServerParams(raw)
        let identifiers = loadedThreadIDs
            .map(AppServerThreadProjection.identifier)
            .sorted()
        let limit = try AppServerThreadPagination.loadedLimit(
            try params.optionalInt("limit"),
            total: identifiers.count
        )
        guard !identifiers.isEmpty else {
            return .object(["data": .array([]), "nextCursor": .null])
        }

        let start: Int
        if let cursor = try params.optionalString("cursor") {
            guard let id = UUID(uuidString: cursor) else {
                throw AppServerRPCError.invalidRequest("invalid cursor: \(cursor)")
            }
            let canonical = AppServerThreadProjection.identifier(id)
            start = identifiers.firstIndex(where: { $0 > canonical }) ?? identifiers.endIndex
        } else {
            start = identifiers.startIndex
        }

        let page = Array(identifiers.dropFirst(start).prefix(limit))
        let hasMore = start + page.count < identifiers.count
        return .object([
            "data": .array(page.map(CLIJSONValue.string)),
            "nextCursor": hasMore ? page.last.map(CLIJSONValue.string) ?? .null : .null
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

    private var emptyThreadSearchPage: CLIJSONValue {
        .object(["data": .array([]), "nextCursor": .null, "backwardsCursor": .null])
    }

    private func includesTrustedRouter(_ params: AppServerParams) throws -> Bool {
        let filters = try stringArray("modelProviders", from: params)
        return filters.isEmpty || filters.contains("trustedrouter")
    }

    private func includesAppServerSource(_ params: AppServerParams) throws -> Bool {
        let filters = try stringArray("sourceKinds", from: params)
        let supported = Set(AppServerThreadSourceKind.allCases.map(\.rawValue))
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
        return AppServerThreadListQuery(
            archived: try params.optionalBool("archived") ?? false,
            searchTerm: try params.optionalString("searchTerm"),
            cwdFilters: try cwdFilters(from: params.object["cwd"]),
            sort: try threadSort(from: params)
        )
    }

    private func threadSort(from params: AppServerParams) throws -> AppServerThreadSort {
        let rawSortKey = try params.optionalString("sortKey") ?? AppServerThreadSortKey.createdAt.rawValue
        guard let sortKey = AppServerThreadSortKey(rawValue: rawSortKey) else {
            throw AppServerRPCError.invalidParams("sortKey is not supported")
        }
        let rawDirection = try params.optionalString("sortDirection")
            ?? AppServerThreadSortDirection.desc.rawValue
        guard let direction = AppServerThreadSortDirection(rawValue: rawDirection) else {
            throw AppServerRPCError.invalidParams("sortDirection is not supported")
        }
        return AppServerThreadSort(key: sortKey, direction: direction)
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
    let sort: AppServerThreadSort

    init(
        archived: Bool,
        searchTerm: String?,
        cwdFilters: Set<String>,
        sort: AppServerThreadSort
    ) {
        self.archived = archived
        self.searchTerm = searchTerm?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        self.cwdFilters = cwdFilters
        self.sort = sort
    }

    func includes(_ record: AppServerThreadRecord) -> Bool {
        guard record.thread.isArchived == archived else { return false }
        if !cwdFilters.isEmpty, !cwdFilters.contains(record.settings.cwd.path) { return false }
        guard let searchTerm, !searchTerm.isEmpty else { return true }
        return record.thread.title.lowercased().contains(searchTerm)
    }

    func precedes(_ lhs: AppServerThreadRecord, _ rhs: AppServerThreadRecord) -> Bool {
        sort.precedes(lhs, rhs)
    }
}

struct AppServerThreadSort {
    let key: AppServerThreadSortKey
    let direction: AppServerThreadSortDirection

    init(key: AppServerThreadSortKey, direction: AppServerThreadSortDirection) {
        self.key = key
        self.direction = direction
    }

    func precedes(_ lhs: AppServerThreadRecord, _ rhs: AppServerThreadRecord) -> Bool {
        let usesRecency = key == .updatedAt || key == .recencyAt
        let left = usesRecency ? lhs.thread.updatedAt : lhs.thread.createdAt
        let right = usesRecency ? rhs.thread.updatedAt : rhs.thread.createdAt
        if left != right { return direction == .asc ? left < right : left > right }
        let leftID = lhs.thread.id.uuidString
        let rightID = rhs.thread.id.uuidString
        return direction == .asc ? leftID < rightID : leftID > rightID
    }
}

enum AppServerThreadSortKey: String {
    case createdAt = "created_at"
    case updatedAt = "updated_at"
    case recencyAt = "recency_at"
}

enum AppServerThreadSortDirection: String {
    case asc
    case desc
}

enum AppServerThreadSourceKind: String, CaseIterable {
    case cli
    case vscode
    case exec
    case appServer
    case subAgent
    case subAgentReview
    case subAgentCompact
    case subAgentThreadSpawn
    case subAgentOther
    case unknown

    static let expectedValues = "one of `cli`, `vscode`, `exec`, `appServer`, `subAgent`, "
        + "`subAgentReview`, `subAgentCompact`, `subAgentThreadSpawn`, `subAgentOther`, `unknown`"
}

private struct AppServerThreadSearchMatch {
    let record: AppServerThreadRecord
    let snippet: String
}

private enum AppServerThreadSearchSnippet {
    static let maximumCharacters = 240
    static let contextBeforeMatch = 72

    static func match(_ searchTerm: String, in thread: ChatThread) -> String? {
        for message in thread.messages where message.role == .user || message.role == .assistant {
            let text = normalized(message.content)
            guard let range = text.range(
                of: searchTerm,
                options: [.caseInsensitive, .diacriticInsensitive]
            ) else { continue }
            return excerpt(text, around: range)
        }
        return nil
    }

    private static func normalized(_ value: String) -> String {
        value
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func excerpt(_ text: String, around range: Range<String.Index>) -> String {
        guard text.count > maximumCharacters else { return text }
        let matchOffset = text.distance(from: text.startIndex, to: range.lowerBound)
        let startOffset = min(
            max(0, matchOffset - contextBeforeMatch),
            max(0, text.count - maximumCharacters)
        )
        let start = text.index(text.startIndex, offsetBy: startOffset)
        let end = text.index(start, offsetBy: maximumCharacters, limitedBy: text.endIndex)
            ?? text.endIndex
        let prefix = start == text.startIndex ? "" : "..."
        let suffix = end == text.endIndex ? "" : "..."
        return prefix + String(text[start..<end]) + suffix
    }
}
