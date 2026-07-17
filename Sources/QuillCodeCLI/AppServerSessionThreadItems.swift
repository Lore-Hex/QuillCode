import Foundation

extension AppServerSession {
    func listThreadItems(_ raw: CLIJSONValue) async throws -> CLIJSONValue {
        let params = try AppServerParams(raw)
        let threadID = try threadID(from: params)
        let turnFilter = try params.optionalString("turnId")
        let direction = try historySortDirection(
            try params.optionalString("sortDirection"),
            default: .asc
        )
        let turns = try await projectedThreadHistoryTurns(threadID)
        var entries = try threadItemEntries(in: turns)
        if direction == .desc { entries.reverse() }

        let page = try AppServerThreadPagination.filteredAnchoredPage(
            entries,
            cursor: try params.optionalString("cursor"),
            requestedLimit: try params.optionalInt("limit"),
            cursorIDKey: "itemId",
            anchorDescription: "item",
            identifier: \.cursorIdentifier,
            isIncluded: { turnFilter == nil || $0.turnID == turnFilter }
        )
        return .object([
            "data": .array(page.data.map(\.wireValue)),
            "nextCursor": page.nextCursor.map(CLIJSONValue.string) ?? .null,
            "backwardsCursor": page.backwardsCursor.map(CLIJSONValue.string) ?? .null
        ])
    }

    private func threadItemEntries(
        in turns: [CLIJSONValue]
    ) throws -> [AppServerThreadItemEntry] {
        try turns.flatMap { turn -> [AppServerThreadItemEntry] in
            guard let object = turn.objectValue,
                  let turnID = object["id"]?.stringValue,
                  !turnID.isEmpty else {
                throw AppServerRPCError.internalError(
                    "persisted thread history contains a turn without an id"
                )
            }
            return try (object["items"]?.arrayValue ?? []).map { item in
                guard let itemID = item.objectValue?["id"]?.stringValue,
                      !itemID.isEmpty else {
                    throw AppServerRPCError.internalError(
                        "persisted thread history contains an item without an id"
                    )
                }
                return AppServerThreadItemEntry(turnID: turnID, itemID: itemID, item: item)
            }
        }
    }
}

private struct AppServerThreadItemEntry {
    let turnID: String
    let itemID: String
    let item: CLIJSONValue

    var cursorIdentifier: String {
        "\(turnID.utf8.count):\(turnID)\(itemID)"
    }

    var wireValue: CLIJSONValue {
        .object(["turnId": .string(turnID), "item": item])
    }
}
