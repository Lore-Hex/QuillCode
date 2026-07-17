import QuillCodeCore

struct WorkspaceStatusContext: Sendable, Hashable {
    var projectName: String
    var threadTitle: String
    var instructions: [ProjectInstruction]
    var memories: [MemoryNote]
    var goal: ThreadGoal?
    var mode: AgentMode
    var model: String
    var agentStatus: String

    init(
        projectName: String,
        threadTitle: String,
        instructions: [ProjectInstruction] = [],
        memories: [MemoryNote] = [],
        goal: ThreadGoal? = nil,
        mode: AgentMode,
        model: String,
        agentStatus: String
    ) {
        self.projectName = projectName
        self.threadTitle = threadTitle
        self.instructions = instructions
        self.memories = memories
        self.goal = goal
        self.mode = mode
        self.model = model
        self.agentStatus = agentStatus
    }
}

struct WorkspaceStatusTextBuilder {
    static func statusText(for context: WorkspaceStatusContext) -> String {
        """
        Project: \(context.projectName)
        Thread: \(context.threadTitle)
        Instructions: \(instructionLabel(for: context.instructions))
        Memories: \(memoryLabel(for: context.memories))
        Goal: \(goalLabel(for: context.goal))
        Mode: \(modeLabel(context.mode))
        Model: \(statusModelLabel(context.model))
        Agent: \(context.agentStatus)
        """
    }

    static func topBarSubtitle(projectName: String, thread: ChatThread?) -> String {
        guard let thread else {
            return "\(projectName) - Not started"
        }
        return "\(projectName) - \(modeLabel(thread.mode)) - \(subtitleModelLabel(thread.model))"
    }

    static func subtitleModelLabel(_ modelID: String) -> String {
        if let recommended = recommendedModelDisplay(for: modelID) {
            return recommended.displayName
        }
        // Display-only names (e.g. the E2E-encrypted route) are deliberately NOT recommended models,
        // but the top bar must still say "E2E Encrypted" — the composer chip already does, and the
        // raw route id reading "trustedrouter/e2e" next to it looks like a bug. Arbitrary catalog
        // models keep their informative canonical id.
        let canonical = TrustedRouterDefaults.canonicalModelID(modelID)
        if let displayName = TrustedRouterDefaults.recommendedDisplayNames[canonical] {
            return displayName
        }
        return canonical
    }

    static func statusModelLabel(_ modelID: String) -> String {
        if let recommended = recommendedModelDisplay(for: modelID) {
            return "\(recommended.displayName) (\(TrustedRouterDefaults.preferredDisplayModelID(recommended.modelID)))"
        }
        // Same display-only fallback as the subtitle, keeping the id visible for /status auditing.
        let canonical = TrustedRouterDefaults.canonicalModelID(modelID)
        if let displayName = TrustedRouterDefaults.recommendedDisplayNames[canonical] {
            return "\(displayName) (\(canonical))"
        }
        return canonical
    }

    private static func recommendedModelDisplay(for modelID: String) -> (modelID: String, displayName: String)? {
        let canonicalModelID = TrustedRouterDefaults.canonicalModelID(modelID)
        guard TrustedRouterDefaults.isRecommendedModel(canonicalModelID) else {
            return nil
        }
        return (
            modelID: canonicalModelID,
            displayName: TrustedRouterDefaults.displayName(fromModelID: canonicalModelID)
        )
    }

    static func modeLabel(_ mode: AgentMode) -> String {
        switch mode {
        case .readOnly:
            return "Read-only"
        case .review:
            return "Review"
        case .plan:
            return "Plan"
        case .auto:
            return "Auto"
        }
    }

    static func instructionLabel(for instructions: [ProjectInstruction]) -> String {
        guard !instructions.isEmpty else { return "No project instructions" }
        let truncated = instructions.contains { $0.wasTruncated } ? ", truncated" : ""
        return "\(instructions.count) instruction file\(instructions.count == 1 ? "" : "s") loaded\(truncated)"
    }

    static func memoryLabel(for memories: [MemoryNote]) -> String {
        guard !memories.isEmpty else { return "No memories" }
        let truncated = memories.contains { $0.wasTruncated } ? ", truncated" : ""
        return "\(memories.count) memor\(memories.count == 1 ? "y" : "ies")\(truncated)"
    }

    static func goalLabel(for goal: ThreadGoal?) -> String {
        guard let goal else { return "No durable goal" }
        let status: String
        switch goal.status {
        case .active: status = "Active"
        case .blocked: status = "Blocked"
        case .completed: status = "Completed"
        }
        return "\(status) - \(goal.objective)"
    }
}
