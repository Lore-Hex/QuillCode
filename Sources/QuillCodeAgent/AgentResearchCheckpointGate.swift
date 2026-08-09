import Foundation
import QuillCodeCore

/// Forces a durable draft before a named-artifact research run spends its entire budget reading.
/// The draft is a checkpoint, not a completion signal: ordinary research-refresh and readback
/// gates still require the final artifact to include later evidence and be verified.
enum AgentResearchCheckpointGate {
    struct Correction: Equatable {
        var path: String
        var prompt: String
    }

    static let minimumPreDraftResearchWeight = 8
    static let minimumPostCheckpointResearchSteps = 6
    static let maximumPostDraftResearchWeight = 36
    static let delegatedResearchWeight = 3
    static let correctionLimitPerPath = 2
    static let finalizationCorrectionLimitPerPath = 8

    static func correction(
        path: String?,
        proposedToolRisk: ToolRiskClass?,
        canWriteFiles: Bool,
        correctionCounts: [String: Int]
    ) -> Correction? {
        guard proposedToolRisk == .read,
              canWriteFiles,
              let path,
              correctionCounts[path, default: 0] < correctionLimitPerPath
        else { return nil }

        return Correction(
            path: path,
            prompt: """
            Research checkpoint required. Before any additional read, search, fetch, or skill-load \
            action, write the best current draft to ./\(path) now. Include the verified facts and \
            source URLs already gathered, plus an explicit Evidence gaps section for facts still \
            missing. This is a checkpoint, not completion: after writing it, continue the remaining \
            research and rewrite the final artifact with later evidence. Respond with \
            host.file.write for exactly ./\(path); do not perform another read-only action first.
            """
        )
    }

    static func exhaustionCorrection(
        path: String?,
        proposedToolName: String,
        canWriteFiles: Bool,
        correctionCounts: [String: Int]
    ) -> Correction? {
        guard isResearchCollectionTool(proposedToolName),
              canWriteFiles,
              let path,
              correctionCounts[path, default: 0] < correctionLimitPerPath
        else { return nil }

        return Correction(
            path: path,
            prompt: """
            The bounded direct-research budget for this deliverable is exhausted. Do not search, \
            fetch, or delegate again. Synthesize the strongest verified evidence already present in \
            the tool results into the complete final artifact at ./\(path) now. Preserve exact source \
            URLs, state genuinely unavailable facts honestly, remove pending/draft status language, \
            and then read the rewritten artifact back. Respond with host.file.write for exactly \
            ./\(path).
            """
        )
    }

    static func isResearchCollectionTool(_ name: String) -> Bool {
        name == ToolDefinition.webSearch.name
            || name == ToolDefinition.webFetch.name
            || name == ToolDefinition.subagentsRun.name
    }

    static func continuationCorrection(
        path: String?,
        didResumeResearch: Bool,
        correctionCounts: [String: Int]
    ) -> Correction? {
        guard let path,
              correctionCounts[path, default: 0] < correctionLimitPerPath
        else { return nil }

        let nextStep = if didResumeResearch {
            "Use the evidence gathered after the checkpoint to rewrite"
        } else {
            "Resume the missing research with host.web.search and host.web.fetch, then rewrite"
        }
        return Correction(
            path: path,
            prompt: """
            The current artifact at ./\(path) is only the required research checkpoint and cannot \
            complete the task. \(nextStep) ./\(path) as the complete final deliverable, then read \
            that final version back. Do not return a final answer while Evidence gaps, draft, \
            checkpoint, pending, or in-progress status remains. Respond with the next concrete tool \
            action now.
            """
        )
    }

    static func finalizationCorrection(
        path: String?,
        proposedToolRisk: ToolRiskClass?,
        canWriteFiles: Bool,
        correctionCounts: [String: Int]
    ) -> Correction? {
        guard proposedToolRisk == .read,
              canWriteFiles,
              let path,
              correctionCounts[path, default: 0] < finalizationCorrectionLimitPerPath
        else { return nil }

        return Correction(
            path: path,
            prompt: """
            The post-checkpoint research budget is complete. Before another read, search, fetch, \
            skill-load, or delegated-research action, synthesize all evidence gathered so far into \
            the complete final artifact at ./\(path). Replace the checkpoint rather than appending \
            another status update. Resolve every evidence gap you can from the current tool results; \
            do not leave TBD, pending, draft, checkpoint, or in-progress markers. Then read the \
            rewritten artifact back before completing. Respond with host.file.write for exactly \
            ./\(path) now.
            """
        )
    }

    static func repeatedDelegationCorrection(path: String) -> Correction {
        Correction(
            path: path,
            prompt: """
            A delegated research batch has already returned and the named deliverable exists at \
            ./\(path). Do not launch another delegated batch. Preserve the completed worker \
            evidence and all later direct research by rewriting ./\(path) as the complete final \
            artifact now. State any genuinely unavailable fact honestly instead of restarting \
            broad research, then read the rewritten artifact back. Respond with host.file.write for \
            exactly ./\(path).
            """
        )
    }
}
