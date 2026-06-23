import QuillCodeCore

struct WorkspaceContextBannerBuilder: Sendable, Hashable {
    static let defaultTokenBudget = 32_000
    static let defaultWarningThresholdPercent = 80

    var thread: ChatThread?
    var tokenBudget: Int = Self.defaultTokenBudget
    var warningThresholdPercent: Int = Self.defaultWarningThresholdPercent

    func banner() -> ContextBannerSurface? {
        guard let thread, !thread.messages.isEmpty else { return nil }
        let usedPercent = contextUsedPercent(for: thread)
        guard usedPercent >= effectiveWarningThresholdPercent else { return nil }

        return ContextBannerSurface(
            usedPercent: usedPercent,
            title: "\(usedPercent >= 100 ? "Context limit reached" : "Approaching context limit") (\(usedPercent)% used)",
            subtitle: "Older turns may drop out soon. Compact the thread, start fresh, or fork from the latest useful context.",
            newThreadCommand: WorkspaceCommandSurface(id: "new-chat", title: "New thread"),
            forkCommand: WorkspaceCommandSurface(id: "fork-from-last", title: "Fork from last"),
            compactCommand: WorkspaceCommandSurface(id: "compact-context", title: "Compact context")
        )
    }

    func contextUsedPercent(for thread: ChatThread) -> Int {
        let estimatedTokens = max(1, Self.estimatedContextTokens(for: thread))
        return min(100, Int((Double(estimatedTokens) / Double(effectiveTokenBudget) * 100).rounded()))
    }

    static func estimatedContextTokens(for thread: ChatThread) -> Int {
        let messageCharacters = thread.messages.reduce(0) { total, message in
            total + message.content.count + 24
        }
        let eventCharacters = thread.events.reduce(0) { total, event in
            total + event.summary.count + (event.payloadJSON?.count ?? 0)
        }
        let instructionCharacters = thread.instructions.reduce(0) { total, instruction in
            total + instruction.content.count
        }
        return (messageCharacters + eventCharacters + instructionCharacters) / 4
    }

    private var effectiveTokenBudget: Int {
        max(1, tokenBudget)
    }

    private var effectiveWarningThresholdPercent: Int {
        min(100, max(0, warningThresholdPercent))
    }
}
