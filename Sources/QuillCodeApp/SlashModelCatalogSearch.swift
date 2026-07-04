import Foundation
import QuillCodeCore

/// One row in the composer `/model` sub-search: a catalog model with a formatted per-Mtok price
/// label. `insertText` is the exact draft that runs the model switch when selected (`/model <id>`),
/// so accepting a row goes through the SAME live `/model` dispatch path as typing the command by
/// hand (issue #879) — the popup is a discovery surface, never a second, divergent writer.
public struct ModelCommandSuggestionSurface: Codable, Sendable, Hashable, Identifiable {
    public var id: String { modelID }
    /// Canonical catalog model ID (e.g. `trustedrouter/fast`). Used as the switch target.
    public var modelID: String
    /// Human title shown first in the row (e.g. `Nike 1.0`, or the model ID when unbranded).
    public var title: String
    /// Provider + category subtitle line.
    public var detail: String
    /// Per-Mtok price line — see `ModelCommandPriceLabel`. Empty when the catalog carries no price.
    public var priceLabel: String
    /// Whether this row is the thread's currently selected model.
    public var isCurrent: Bool
    /// The draft that runs the switch when this row is accepted.
    public var insertText: String

    public init(
        modelID: String,
        title: String,
        detail: String,
        priceLabel: String,
        isCurrent: Bool,
        insertText: String
    ) {
        self.modelID = modelID
        self.title = title
        self.detail = detail
        self.priceLabel = priceLabel
        self.isCurrent = isCurrent
        self.insertText = insertText
    }
}

/// Formats a catalog model's input/output price as a compact per-Mtok label. Pure and total: it
/// never crashes on a missing, zero, negative, or absurdly large price. Missing prices yield an
/// empty string so the caller can render the model gracefully without a price (offline/mock).
public enum ModelCommandPriceLabel {
    /// The label for a model's capabilities, or "" when no price is known.
    public static func label(for capabilities: ModelCapabilities) -> String {
        switch (capabilities.inputPricePerMillionTokens, capabilities.outputPricePerMillionTokens) {
        case let (.some(input), .some(output)):
            return "\(currency(input)) in / \(currency(output)) out per 1M"
        case let (.some(input), .none):
            return "\(currency(input)) input per 1M"
        case let (.none, .some(output)):
            return "\(currency(output)) output per 1M"
        case (.none, .none):
            return ""
        }
    }

    /// Formats a single non-negative dollar amount. `ModelCapabilities` already clamps prices to
    /// `>= 0`, but this guards independently so a hand-built capability with a negative value can
    /// never render a stray minus sign, and non-finite values (NaN/inf) fall back to `$0`.
    static func currency(_ value: Double) -> String {
        guard value.isFinite else { return "$0" }
        let safe = max(0, value)
        // Fixed 4-decimal format then trim trailing zeros, so tiny per-Mtok prices ($0.0002) stay
        // legible and whole-dollar prices ($15) read cleanly. Huge values format without crashing.
        let formatted = String(format: "%.4f", safe)
        let trimmed = formatted
            .replacingOccurrences(of: #"0+$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\.$"#, with: "", options: .regularExpression)
        return "$\(trimmed)"
    }
}

/// Pure, testable core of the composer `/model` sub-search. It owns two decisions:
///
/// 1. **Trigger** (`query(in:)`): the sub-search is active only when the draft starts (after leading
///    whitespace) with the `/model` command AND a space follows the command word — i.e. the user has
///    committed to `/model ` and is now typing a model query. A bare `/model` (no trailing space)
///    stays in the top-level slash popup as the `/model` command row, exactly like every other
///    command; a `/model` mid-sentence never triggers because the slash rule requires command-start.
///    A newline ends the sub-search (the draft is now multi-line prose, not a command).
///
/// 2. **Filter/rank** (`suggestions(...)`): every catalog model is matched against the query with a
///    prefix > substring ranking over the model ID, provider, display name, and category, then
///    bounded to `limit`. An empty query lists the catalog head. Ranking and matching are
///    deduplicated by canonical model ID so favorites/recent duplicates never double-list.
enum SlashModelCatalogSearch {
    static let commandPrefixes = ["/model", "/models"]

    /// The model query the user is typing after `/model `, or nil when the sub-search is inactive.
    /// Returns "" (active, empty query) for `/model ` with nothing yet typed.
    static func query(in draft: String) -> String? {
        let leading = draft.drop { $0 == " " || $0 == "\t" }
        guard !leading.contains("\n") else { return nil }
        let lowered = leading.lowercased()
        for prefix in commandPrefixes {
            // Require the command word to be FOLLOWED by a space: `/model ` (sub-search) vs `/model`
            // (top-level command row) vs `/modelfoo` (not our command — a different token).
            let withSpace = prefix + " "
            if lowered.hasPrefix(withSpace) {
                let start = leading.index(leading.startIndex, offsetBy: withSpace.count)
                return String(leading[start...]).trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    /// Whether the draft is currently in the `/model` sub-search (a query is being typed).
    static func isActive(in draft: String) -> Bool {
        query(in: draft) != nil
    }

    /// The ranked, bounded model suggestions for a draft. Returns [] when the sub-search is inactive.
    static func suggestions(
        for draft: String,
        categories: [ModelCategorySurface],
        limit: Int = 6
    ) -> [ModelCommandSuggestionSurface] {
        guard let query = query(in: draft) else { return [] }
        return rank(options: dedupedOptions(from: categories), query: query, limit: limit)
    }

    /// Flattens categories to a single deduped option list keyed by canonical model ID. The picker
    /// surface lists a model once per category (Favorites/Recent/base), so dedup keeps a model from
    /// appearing several times in the flat `/model` popup; the first occurrence (highest-priority
    /// category) wins, preserving the "Current" flag.
    private static func dedupedOptions(from categories: [ModelCategorySurface]) -> [ModelOptionSurface] {
        var seen = Set<String>()
        var result: [ModelOptionSurface] = []
        for option in categories.flatMap(\.models) {
            let key = TrustedRouterDefaults.canonicalModelID(option.id)
            guard seen.insert(key).inserted else { continue }
            result.append(option)
        }
        return result
    }

    private static func rank(
        options: [ModelOptionSurface],
        query: String,
        limit: Int
    ) -> [ModelCommandSuggestionSurface] {
        let normalizedQuery = normalize(query)
        let scored = options.enumerated().compactMap { index, option -> (Int, Int, ModelOptionSurface)? in
            score(option, query: normalizedQuery).map { ($0, index, option) }
        }
        return scored
            .sorted { lhs, rhs in
                if lhs.0 != rhs.0 { return lhs.0 > rhs.0 }
                return lhs.1 < rhs.1
            }
            .prefix(max(0, limit))
            .map { _, _, option in suggestion(for: option) }
    }

    private static func score(_ option: ModelOptionSurface, query: String) -> Int? {
        guard !query.isEmpty else { return 50 }
        let fields = [
            option.id,
            option.provider,
            option.displayName,
            option.detailTitle,
            option.category,
            option.metadataSummary,
            option.capabilitySummary
        ]
            .map(normalize)
        if fields.contains(where: { $0.hasPrefix(query) }) { return 120 }
        // Allow multi-term substring matching ("moon k2") so the popup mirrors the picker's search.
        let haystack = fields.joined(separator: " ")
        let terms = query.split(whereSeparator: \.isWhitespace).map(String.init)
        if terms.allSatisfy({ haystack.contains($0) }) { return 90 }
        return nil
    }

    private static func suggestion(for option: ModelOptionSurface) -> ModelCommandSuggestionSurface {
        let modelID = TrustedRouterDefaults.canonicalModelID(option.id)
        return ModelCommandSuggestionSurface(
            modelID: modelID,
            title: option.detailTitle,
            detail: "\(option.provider) · \(option.category)",
            priceLabel: ModelCommandPriceLabel.label(for: option.capabilities),
            isCurrent: option.isSelected,
            insertText: "/model \(modelID)"
        )
    }

    private static func normalize(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
