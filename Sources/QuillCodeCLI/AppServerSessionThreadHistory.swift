import Foundation

extension AppServerSession {
    func listThreadTurns(_ raw: CLIJSONValue) async throws -> CLIJSONValue {
        let params = try AppServerParams(raw)
        let threadID = try threadID(from: params)
        let itemsView = try turnItemsView(try params.optionalString("itemsView"))
        let direction = try turnSortDirection(try params.optionalString("sortDirection"))
        let record = try await threadHistoryRecord(threadID)
        var turns = AppServerThreadHistoryProjection.turns(record)
        if let active = activeProjectedTurn(threadID) {
            if let index = turns.firstIndex(where: { turnIdentifier($0) == turnIdentifier(active) }) {
                turns[index] = active
            } else {
                turns.append(active)
            }
        }
        turns = turns.map { applyingItemsView(itemsView, to: $0) }
        if direction == .desc { turns.reverse() }

        let page = try AppServerThreadPagination.anchoredPage(
            turns,
            cursor: try params.optionalString("cursor"),
            requestedLimit: try params.optionalInt("limit"),
            cursorIDKey: "turnId",
            anchorDescription: "turn",
            identifier: { turnIdentifier($0) }
        )
        return .object([
            "data": .array(page.data),
            "nextCursor": page.nextCursor.map(CLIJSONValue.string) ?? .null,
            "backwardsCursor": page.backwardsCursor.map(CLIJSONValue.string) ?? .null
        ])
    }

    private func threadHistoryRecord(_ threadID: UUID) async throws -> AppServerThreadRecord {
        if let active = activeTurns[threadID] {
            return AppServerThreadRecord(thread: active.latestThread, settings: active.settings)
        }
        if let active = activeCompactions[threadID] {
            return AppServerThreadRecord(thread: active.latestThread, settings: active.settings)
        }
        if let active = activeReviews[threadID] {
            return AppServerThreadRecord(thread: active.latestThread, settings: active.settings)
        }
        if let active = activeUserShellTurns[threadID] {
            return AppServerThreadRecord(thread: active.latestThread, settings: active.settings)
        }
        return try await loadRecord(threadID)
    }

    private func activeProjectedTurn(_ threadID: UUID) -> CLIJSONValue? {
        if let active = activeTurns[threadID] {
            return AppServerThreadProjection.turn(
                id: active.id,
                items: active.projector.items,
                status: "inProgress",
                startedAt: active.startedAt,
                completedAt: nil,
                itemsView: "full"
            )
        }
        if let active = activeReviews[threadID] {
            return AppServerThreadProjection.turn(
                id: active.id,
                items: active.projector.items,
                status: "inProgress",
                startedAt: active.startedAt,
                completedAt: nil,
                itemsView: "full"
            )
        }
        if let active = activeCompactions[threadID] {
            return AppServerThreadProjection.turn(
                id: active.id,
                items: [.object([
                    "type": .string("contextCompaction"),
                    "id": .string(active.itemID)
                ])],
                status: "inProgress",
                startedAt: active.startedAt,
                completedAt: nil,
                itemsView: "full"
            )
        }
        if let active = activeUserShellTurns[threadID] {
            return AppServerThreadProjection.turn(
                id: active.id,
                items: [],
                status: "inProgress",
                startedAt: active.startedAt,
                completedAt: nil,
                itemsView: "notLoaded"
            )
        }
        return nil
    }

    private func applyingItemsView(
        _ view: AppServerTurnItemsView,
        to turn: CLIJSONValue
    ) -> CLIJSONValue {
        guard var object = turn.objectValue else { return turn }
        let items = object["items"]?.arrayValue ?? []
        switch view {
        case .notLoaded:
            object["items"] = .array([])
        case .summary:
            let firstUser = items.first { itemType($0) == "userMessage" }
            let finalAgent = items.last { itemType($0) == "agentMessage" }
            if let firstUser, let finalAgent, itemIdentifier(firstUser) != itemIdentifier(finalAgent) {
                object["items"] = .array([firstUser, finalAgent])
            } else if let firstUser {
                object["items"] = .array([firstUser])
            } else if let finalAgent {
                object["items"] = .array([finalAgent])
            } else {
                object["items"] = .array([])
            }
        case .full:
            break
        }
        object["itemsView"] = .string(view.rawValue)
        return .object(object)
    }

    private func turnItemsView(_ value: String?) throws -> AppServerTurnItemsView {
        let value = value ?? AppServerTurnItemsView.summary.rawValue
        guard let view = AppServerTurnItemsView(rawValue: value) else {
            throw AppServerRPCError.invalidRequest(
                "Invalid request: unknown variant `\(value)`, expected one of "
                    + "`notLoaded`, `summary`, `full`"
            )
        }
        return view
    }

    private func turnSortDirection(_ value: String?) throws -> AppServerTurnSortDirection {
        let value = value ?? AppServerTurnSortDirection.desc.rawValue
        guard let direction = AppServerTurnSortDirection(rawValue: value) else {
            throw AppServerRPCError.invalidRequest(
                "Invalid request: unknown variant `\(value)`, expected `asc` or `desc`"
            )
        }
        return direction
    }

    private func turnIdentifier(_ value: CLIJSONValue) -> String {
        value.objectValue?["id"]?.stringValue ?? ""
    }

    private func itemType(_ value: CLIJSONValue) -> String? {
        value.objectValue?["type"]?.stringValue
    }

    private func itemIdentifier(_ value: CLIJSONValue) -> String? {
        value.objectValue?["id"]?.stringValue
    }
}

private enum AppServerTurnItemsView: String {
    case notLoaded
    case summary
    case full
}

private enum AppServerTurnSortDirection: String {
    case asc
    case desc
}
