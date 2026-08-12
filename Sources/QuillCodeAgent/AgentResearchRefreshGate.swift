import Foundation
import QuillCodeCore
import QuillCodeTools

/// Prevents a research run from finalizing an artifact that predates evidence gathered later.
/// A successful page fetch can change the answer even when the artifact already passed readback,
/// so the model must incorporate or explicitly disposition that evidence and verify the rewrite.
enum AgentResearchRefreshGate {
    struct Correction: Equatable {
        var path: String
        var prompt: String
    }

    static let correctionLimitPerPath = 2

    static func correctionBeforeNonResearchRead(
        stalePaths: Set<String>,
        proposedToolName: String,
        proposedToolRisk: ToolRiskClass?,
        canWriteFiles: Bool,
        correctionCounts: [String: Int]
    ) -> Correction? {
        guard canWriteFiles,
              proposedToolRisk == .read,
              !researchToolNames.contains(proposedToolName)
        else { return nil }
        return correction(
            stalePaths: stalePaths,
            correctionCounts: correctionCounts,
            reason: "before using another local read tool"
        )
    }

    static func correction(
        stalePaths: Set<String>,
        correctionCounts: [String: Int]
    ) -> Correction? {
        correction(
            stalePaths: stalePaths,
            correctionCounts: correctionCounts,
            reason: "before giving a final answer"
        )
    }

    private static func correction(
        stalePaths: Set<String>,
        correctionCounts: [String: Int],
        reason: String
    ) -> Correction? {
        guard let path = stalePaths.sorted().first(where: {
            correctionCounts[$0, default: 0] < correctionLimitPerPath
        }) else { return nil }
        return Correction(
            path: path,
            prompt: """
            Research-completion check: you successfully fetched live source evidence after the latest \
            write of ./\(path). Rewrite that exact artifact as a complete current deliverable, not a \
            progress update. Incorporate the relevant verified facts and exact source URLs, or state \
            honestly why evidence is unusable or unavailable. Resolve every evidence gap possible \
            from the current tool results. Remove TODO, pending, draft, checkpoint, in-progress, \
            next-pass, and other future-work language. Do this \(reason), then read ./\(path) back \
            after the rewrite. Treat the pre-research draft's structure as disposable. You may resume \
            genuinely necessary research after readback, but do not describe that future work inside \
            the deliverable.
            """
        )
    }

    private static let researchToolNames: Set<String> = [
        ToolDefinition.webSearch.name,
        ToolDefinition.webFetch.name,
        ToolDefinition.subagentsRun.name,
    ]
}
