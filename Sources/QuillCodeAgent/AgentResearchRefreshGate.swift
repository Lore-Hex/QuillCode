import Foundation

/// Prevents a research run from finalizing an artifact that predates evidence gathered later.
/// A successful page fetch can change the answer even when the artifact already passed readback,
/// so the model must incorporate or explicitly disposition that evidence and verify the rewrite.
enum AgentResearchRefreshGate {
    struct Correction: Equatable {
        var path: String
        var prompt: String
    }

    static let correctionLimitPerPath = 2

    static func correction(
        stalePaths: Set<String>,
        correctionCounts: [String: Int]
    ) -> Correction? {
        guard let path = stalePaths.sorted().first(where: {
            correctionCounts[$0, default: 0] < correctionLimitPerPath
        }) else { return nil }
        return Correction(
            path: path,
            prompt: """
            Research-completion check: you successfully fetched live source evidence after the latest \
            write of ./\(path). Update that exact deliverable now so it incorporates the relevant \
            verified facts and citations, or explicitly records why the fetched evidence is unusable. \
            Then read ./\(path) back after the rewrite before giving a final answer. Do not finish with \
            the pre-research draft.
            """
        )
    }
}
