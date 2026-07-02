import Foundation
import QuillCodeCore

/// How the auxiliary model was chosen, recorded into telemetry so an unexpected model on a
/// summary/compaction call is diagnosable from the thread's notice payload.
public enum AuxiliaryModelSelectionSource: String, Codable, Sendable, Hashable {
    /// Picked from the live model catalog by the cost/recency heuristic.
    case catalogHeuristic = "catalog_heuristic"
    /// No priced catalog candidates existed; the session's current model was kept.
    case sessionModelFallback = "session_model_fallback"
    /// The catalog had candidates, but every winner was pricier than the (priced) session model —
    /// the aux call must never cost more than doing nothing, so the session model was kept.
    case sessionModelCheaper = "session_model_cheaper"
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
/// auxiliary call, and it never returns a model pricier than a priced session model. (TrustedRouter
/// has no dedicated "cheap" route today; if one is added, prefer it in
/// `selection(models:sessionModelID:)` before the session-model fallback.)
public enum AuxiliaryModelSelector {
    /// Names OpenCode treats as small-model markers; matching models get a scoring bonus.
    static let smallModelNameHints: Set<String> = ["nano", "flash", "lite", "haiku", "mini"]
    static let costWeight = 0.8
    static let recencyWeight = 0.2
    static let smallModelNameBonus = 0.15

    public static func selection(models: [ModelInfo], sessionModelID: String) -> AuxiliaryModelSelection {
        let sessionID = TrustedRouterDefaults.normalizedDefaultModelID(sessionModelID)
        guard let best = bestCandidate(in: models) else {
            return AuxiliaryModelSelection(modelID: sessionID, source: .sessionModelFallback)
        }
        // Hard cost ceiling: a heuristic winner (recency/name bonus can prefer a slightly pricier
        // model) must never make the aux call MORE expensive than the session model it replaces.
        if let sessionCost = blendedCost(ofCanonicalModelID: sessionID, in: models), best.cost > sessionCost {
            return AuxiliaryModelSelection(modelID: sessionID, source: .sessionModelCheaper)
        }
        return AuxiliaryModelSelection(modelID: best.modelID, source: .catalogHeuristic)
    }

    private struct Candidate {
        var modelID: String
        var cost: Double
        var releaseDate: Date?
        var hasSmallModelName: Bool
    }

    private static func bestCandidate(in models: [ModelInfo]) -> Candidate? {
        let candidates = models.compactMap(candidate(from:))
        guard let cheapestCost = candidates.map(\.cost).min() else { return nil }
        let releaseTimes = candidates.compactMap { $0.releaseDate?.timeIntervalSince1970 }
        // The cost score is the ratio to the CHEAPEST candidate — scale-invariant, so an expensive
        // catalog outlier cannot compress real cost differences among the cheap models (a range-based
        // normalization would let the 0.2 recency weight or the name bonus override a 62x price gap).
        // A model at 62x the cheapest scores ~0.013 of the 0.8 cost weight; near-equal cheap models
        // stay near-equal so the small-model name bonus can still act.
        let scored = candidates.map { candidate in
            (
                candidate: candidate,
                score: costWeight * (cheapestCost / candidate.cost)
                    + recencyWeight * recencyScore(for: candidate, in: releaseTimes)
                    + (candidate.hasSmallModelName ? smallModelNameBonus : 0)
            )
        }
        // Deterministic winner: highest score, then cheaper, then stable ID order. All score inputs
        // are finite (the candidate guard rejects non-finite costs and dates), so the comparator is
        // a strict weak ordering regardless of catalog order.
        return scored.max { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score < rhs.score }
            if lhs.candidate.cost != rhs.candidate.cost { return lhs.candidate.cost > rhs.candidate.cost }
            return lhs.candidate.modelID > rhs.candidate.modelID
        }?.candidate
    }

    /// A model is a candidate only when the catalog prices it with finite, positive numbers
    /// (zero-priced entries usually mean "price unknown", not free, and a non-finite price would
    /// poison every score) and nothing marks it unsuitable for a plain text call.
    private static func candidate(from model: ModelInfo) -> Candidate? {
        guard let cost = blendedCost(model.capabilities),
              producesText(model.capabilities),
              !isRetired(model.capabilities)
        else { return nil }
        return Candidate(
            modelID: model.id,
            cost: cost,
            releaseDate: finiteReleaseDate(model.capabilities.releaseDate),
            hasSmallModelName: hasSmallModelName(model)
        )
    }

    /// Auxiliary calls are prompt-heavy and reply short, so weight input cost 3:1.
    /// nil when either price is missing, non-finite, zero, or negative — or when the blend itself
    /// overflows to infinity (finite prices above ~6e307 do; an infinite blend would put NaN into
    /// the cost-ratio scores and break the comparator's strict weak ordering).
    private static func blendedCost(_ capabilities: ModelCapabilities) -> Double? {
        guard let input = capabilities.inputPricePerMillionTokens,
              let output = capabilities.outputPricePerMillionTokens,
              input.isFinite, output.isFinite,
              input > 0, output > 0
        else { return nil }
        let blended = (3 * input + output) / 4
        guard blended.isFinite else { return nil }
        return blended
    }

    private static func blendedCost(ofCanonicalModelID modelID: String, in models: [ModelInfo]) -> Double? {
        models
            .first { TrustedRouterDefaults.canonicalModelID($0.id) == modelID }
            .flatMap { blendedCost($0.capabilities) }
    }

    /// Hints match whole name tokens, not raw substrings — "mini" must hit "gpt-5-mini" but never
    /// "gemini-3-ultra" or "minimax-m2" (a flagship with an accidental substring would otherwise
    /// collect the small-model bonus).
    private static func hasSmallModelName(_ model: ModelInfo) -> Bool {
        !smallModelNameHints.isDisjoint(with: nameTokens(of: model))
    }

    private static func nameTokens(of model: ModelInfo) -> Set<String> {
        Set(
            "\(model.id) \(model.displayName)"
                .lowercased()
                .components(separatedBy: CharacterSet(charactersIn: "/-_.: "))
                .filter { !$0.isEmpty }
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

    private static func finiteReleaseDate(_ date: Date?) -> Date? {
        guard let date, date.timeIntervalSince1970.isFinite else { return nil }
        return date
    }

    private static func recencyScore(for candidate: Candidate, in releaseTimes: [Double]) -> Double {
        // Models without a release date sit at the neutral midpoint so an undated bargain still
        // beats a dated flagship, but a dated equal-cost peer wins the recency component.
        guard let time = candidate.releaseDate?.timeIntervalSince1970 else { return 0.5 }
        guard let min = releaseTimes.min(), let max = releaseTimes.max(), max > min else { return 1 }
        return (time - min) / (max - min)
    }
}
