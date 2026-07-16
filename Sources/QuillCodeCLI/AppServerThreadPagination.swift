import Foundation

struct AppServerAnchoredPage<Element> {
    let data: [Element]
    let nextCursor: String?
    let backwardsCursor: String?
}

enum AppServerThreadPagination {
    static let defaultLimit = 25
    static let maximumLimit = 100

    static func anchoredPage<Element>(
        _ orderedValues: [Element],
        cursor: String?,
        requestedLimit: Int?,
        cursorIDKey: String,
        anchorDescription: String,
        identifier: (Element) -> String
    ) throws -> AppServerAnchoredPage<Element> {
        try filteredAnchoredPage(
            orderedValues,
            cursor: cursor,
            requestedLimit: requestedLimit,
            cursorIDKey: cursorIDKey,
            anchorDescription: anchorDescription,
            identifier: identifier,
            isIncluded: { _ in true }
        )
    }

    static func filteredAnchoredPage<Element>(
        _ orderedValues: [Element],
        cursor: String?,
        requestedLimit: Int?,
        cursorIDKey: String,
        anchorDescription: String,
        identifier: (Element) -> String,
        isIncluded: (Element) -> Bool
    ) throws -> AppServerAnchoredPage<Element> {
        let limit = try boundedLimit(requestedLimit)
        guard !orderedValues.isEmpty else {
            return AppServerAnchoredPage(data: [], nextCursor: nil, backwardsCursor: nil)
        }

        let startIndex: Int
        if let cursor {
            let anchor = try decodeCursor(cursor, idKey: cursorIDKey)
            guard let index = orderedValues.firstIndex(where: { identifier($0) == anchor.id }) else {
                throw AppServerRPCError.invalidRequest(
                    "invalid cursor: anchor \(anchorDescription) is no longer present"
                )
            }
            startIndex = anchor.includeAnchor ? index : index + 1
        } else {
            startIndex = 0
        }

        guard startIndex < orderedValues.count else {
            return AppServerAnchoredPage(data: [], nextCursor: nil, backwardsCursor: nil)
        }
        let remaining = orderedValues[startIndex...].filter(isIncluded)
        let data = Array(remaining.prefix(limit))
        let hasMore = remaining.count > data.count
        let backwardsCursor = try data.first.map {
            try encodeCursor(id: identifier($0), includeAnchor: true, idKey: cursorIDKey)
        }
        let nextCursor = try hasMore ? data.last.map {
            try encodeCursor(id: identifier($0), includeAnchor: false, idKey: cursorIDKey)
        } : nil
        return AppServerAnchoredPage(
            data: data,
            nextCursor: nextCursor,
            backwardsCursor: backwardsCursor
        )
    }

    static func boundedLimit(_ requestedLimit: Int?) throws -> Int {
        guard let requestedLimit else { return defaultLimit }
        return min(maximumLimit, max(1, try unsignedLimit(requestedLimit)))
    }

    static func loadedLimit(_ requestedLimit: Int?, total: Int) throws -> Int {
        guard let requestedLimit else { return total }
        return max(1, try unsignedLimit(requestedLimit))
    }

    private static func unsignedLimit(_ value: Int) throws -> Int {
        guard value >= 0, UInt64(value) <= UInt64(UInt32.max) else {
            throw AppServerRPCError.invalidRequest(
                "Invalid request: invalid value: integer `\(value)`, expected u32"
            )
        }
        return value
    }

    private static func encodeCursor(
        id: String,
        includeAnchor: Bool,
        idKey: String
    ) throws -> String {
        let value = CLIJSONValue.object([
            idKey: .string(id),
            "includeAnchor": .bool(includeAnchor)
        ])
        return String(decoding: try CLIJSONCodec.encode(value), as: UTF8.self)
    }

    private static func decodeCursor(_ cursor: String, idKey: String) throws -> Anchor {
        guard let object = try? CLIJSONCodec.decode(cursor).objectValue,
              let id = object[idKey]?.stringValue,
              !id.isEmpty,
              let includeAnchor = object["includeAnchor"]?.boolValue else {
            throw AppServerRPCError.invalidRequest("invalid cursor: \(cursor)")
        }
        return Anchor(id: id, includeAnchor: includeAnchor)
    }
}

private struct Anchor {
    let id: String
    let includeAnchor: Bool
}
