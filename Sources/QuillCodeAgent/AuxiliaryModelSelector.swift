import Foundation
import QuillCodeCore

/// How the auxiliary model was chosen, recorded into telemetry so an unexpected model on a
/// summary/compaction call is diagnosable from the thread's notice payload.
public enum AuxiliaryModelSelectionSource: String, Codable, Sendable, Hashable {
    /// Picked from the live model catalog by the cost/recency heuristic.
    case catalogHeuristic = "catalog_heuristic"
    /// No priced catalog candidates existed; the session's current model was kept.
    case sessionModelFallback = "session_model_fallback"
}

public struct AuxiliaryModelSelection: Codable, Sendable, Hashable {
    public var modelID: String
    public var source: AuxiliaryModelSelectionSource

    public init(modelID: String, source: AuxiliaryModelSelectionSource) {
        self.modelID = modelID
        self.source = source
    }
}

/// Picks the model for internal/auxiliary LLM calls (context summaries, compaction) so unattended
/// loops stop burning flagship tokens on housekeeping. Mirrors OpenCode's small-model heuristic:
/// score = cost 80% + recency 20%, biased toward models named nano/flash/lite/haiku/mini.
///
/// Pure and total: it never throws and always returns a usable model ID — when the catalog carries
/// no priced text models it falls back to the session's current model rather than failing the
/// auxiliary call. (TrustedRouter has no dedicated "cheap" route today; if one is added, prefer it
/// in `selection(models:sessionModelID:)` before the session-model fallback.)
public enum AuxiliaryModelSelector {
    /// Names OpenCode treats as small-model markers; matching models get a scoring bonus.
    static let smallModelNameHints = ["nano", "flash", "lite", "haiku", "mini"]
    static let costWeight = 0.8
    static let recencyWeight = 0.2
    static let smallModelNameBonus = 0.15

    public static func selection(models: [ModelInfo], sessionModelID: String) -> AuxiliaryModelSelection {
        if let best = bestCandidate(in: models) {
            return AuxiliaryModelSelection(modelID: best, source: .catalogHeuristic)
        }
        return AuxiliaryModelSelection(
            modelID: TrustedRouterDefaults.normalizedDefaultModelID(sessionModelID),
            source: .sessionModelFallback
        )
    }

    private struct Candidate {
        var modelID: String
        var cost: Double
        var releaseDate: Date?
        var hasSmallModelName: Bool
    }

    private static func bestCandidate(in models: [ModelInfo]) -> String? {
        let candidates = models.compactMap(candidate(from:))
        guard !candidates.isEmpty else { return nil }
        let maxCost = candidates.map(\.cost).max() ?? 0
        let releaseTimes = candidates.compactMap { $0.releaseDate?.timeIntervalSince1970 }
        let scored = candidates.map { candidate in
            (
                candidate: candidate,
                score: costWeight * costScore(for: candidate, maxCost: maxCost)
                    + recencyWeight * recencyScore(for: candidate, in: releaseTimes)
                    + (candidate.hasSmallModelName ? smallModelNameBonus : 0)
            )
        }
        // Deterministic winner: highest score, then cheaper, then stable ID order.
        return scored.max { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score < rhs.score }
            if lhs.candidate.cost != rhs.candidate.cost { return lhs.candidate.cost > rhs.candidate.cost }
            return lhs.candidate.modelID > rhs.candidate.modelID
        }?.candidate.modelID
    }

    /// A model is a candidate only when the catalog prices it (zero-priced entries usually mean
    /// "price unknown", not free) and nothing marks it unsuitable for a plain text call.
    private static func candidate(from model: ModelInfo) -> Candidate? {
        guard let input = model.capabilities.inputPricePerMillionTokens,
              let output = model.capabilities.outputPricePerMillionTokens,
              input + output > 0,
              producesText(model.capabilities),
              !isRetired(model.capabilities)
        else { return nil }
        let name = "\(model.id) \(model.displayName)".lowercased()
        return Candidate(
            modelID: model.id,
            // Auxiliary calls are prompt-heavy and reply short, so weight input cost 3:1.
            cost: (3 * input + output) / 4,
            releaseDate: model.capabilities.releaseDate,
            hasSmallModelName: smallModelNameHints.contains { name.contains($0) }
        )
    }

    private static func producesText(_ capabilities: ModelCapabilities) -> Bool {
        capabilities.outputModalities.isEmpty
            || capabilities.outputModalities.contains { $0.lowercased() == "text" }
    }

    private static func isRetired(_ capabilities: ModelCapabilities) -> Bool {
        guard let status = capabilities.status?.lowercased() else { return false }
        return status.contains("deprecat") || status.contains("retired") || status.contains("disabled")
    }

    /// Cost is scored as a ratio against the priciest candidate (not min-max) so a couple of
    /// near-equal cheap models stay near-equal instead of a fractionally-cheaper one absorbing the
    /// entire 80% weight — that would make the small-model name bias unreachable.
    private static func costScore(for candidate: Candidate, maxCost: Double) -> Double {
        guard maxCost > 0 else { return 1 }
        return 1 - candidate.cost / maxCost
    }

    private static func recencyScore(for candidate: Candidate, in releaseTimes: [Double]) -> Double {
        // Models without a release date sit at the neutral midpoint so an undated bargain still
        // beats a dated flagship, but a dated equal-cost peer wins the recency component.
        guard let time = candidate.releaseDate?.timeIntervalSince1970 else { return 0.5 }
        guard let min = releaseTimes.min(), let max = releaseTimes.max(), max > min else { return 1 }
        return (time - min) / (max - min)
    }
}
