import QuillCodeCore

struct WorkspaceStatusContext: Sendable, Hashable {
    var projectName: String
    var threadTitle: String
    var instructions: [ProjectInstruction]
    var memories: [MemoryNote]
    var mode: AgentMode
    var model: String
    var agentStatus: String

    init(
        projectName: String,
        threadTitle: String,
        instructions: [ProjectInstruction] = [],
        memories: [MemoryNote] = [],
        mode: AgentMode,
        model: String,
        agentStatus: String
    ) {
        self.projectName = projectName
        self.threadTitle = threadTitle
        self.instructions = instructions
        self.memories = memories
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
        guard let recommended = recommendedModelDisplay(for: modelID) else {
            return TrustedRouterDefaults.canonicalModelID(modelID)
        }
        return recommended.displayName
    }

    static func statusModelLabel(_ modelID: String) -> String {
        guard let recommended = recommendedModelDisplay(for: modelID) else {
            return TrustedRouterDefaults.canonicalModelID(modelID)
        }
        return "\(recommended.displayName) (\(TrustedRouterDefaults.preferredDisplayModelID(recommended.modelID)))"
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
}
