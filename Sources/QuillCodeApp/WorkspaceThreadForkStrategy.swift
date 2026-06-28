import QuillCodeCore

enum WorkspaceThreadForkStrategy: String, CaseIterable, Sendable, Hashable {
    case latestTurn
    case summarizedContext
    case fullContext

    init?(commandID: String) {
        guard let strategy = Self.allCases.first(where: { $0.commandID == commandID }) else {
            return nil
        }
        self = strategy
    }

    var commandID: String {
        switch self {
        case .latestTurn:
            "fork-from-last"
        case .summarizedContext:
            "fork-with-summary"
        case .fullContext:
            "fork-full-context"
        }
    }

    var commandTitle: String {
        switch self {
        case .latestTurn:
            "Fork from last"
        case .summarizedContext:
            "Fork summary"
        case .fullContext:
            "Fork full"
        }
    }

    var commandKeywords: [String] {
        switch self {
        case .latestTurn:
            ["thread", "context", "continue", "latest"]
        case .summarizedContext:
            ["thread", "context", "summarize", "fork", "compact"]
        case .fullContext:
            ["thread", "context", "full", "fork", "copy"]
        }
    }

    var threadTitlePrefix: String {
        switch self {
        case .latestTurn:
            "Fork"
        case .summarizedContext:
            "Fork summary"
        case .fullContext:
            "Fork full"
        }
    }

    var noticeSummaryPrefix: String {
        switch self {
        case .latestTurn:
            "Forked"
        case .summarizedContext:
            "Forked with summary"
        case .fullContext:
            "Forked with full visible context"
        }
    }

    var contextBannerTestID: String {
        switch self {
        case .latestTurn:
            "context-fork-last"
        case .summarizedContext:
            "context-fork-summary"
        case .fullContext:
            "context-fork-full"
        }
    }

    func command(isEnabled: Bool = true) -> WorkspaceCommandSurface {
        WorkspaceCommandSurface(
            id: commandID,
            title: commandTitle,
            category: WorkspaceCommandPalette.threadCategory,
            keywords: commandKeywords,
            isEnabled: isEnabled
        )
    }
}
