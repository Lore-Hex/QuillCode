import Foundation
import QuillCodeCore

enum ModelCategorySearchFilter {
    static func filter(_ categories: [ModelCategorySurface], matching query: String) -> [ModelCategorySurface] {
        var terms = normalizedTerms(from: query)
        // Region enforcement terms ("us-only", "eu-only", "china-only") are CONSTRAINTS, not text:
        // they restrict results to models whose routing is entirely within that region, and are
        // removed from the text terms so "us-only" alone lists every US-resident model.
        let requiredRegion = extractRegionOnlyConstraint(from: &terms)
        guard !terms.isEmpty || requiredRegion != nil else {
            return categories
        }

        return categories.compactMap { category in
            guard categoryScopeMatches(category, terms: terms) else {
                return nil
            }
            let models = category.models.filter { option in
                if let requiredRegion, !isRegionOnly(option, region: requiredRegion) {
                    return false
                }
                guard !terms.isEmpty else { return true }
                let haystack = searchableText(for: option, in: category).lowercased()
                let compactHaystack = compactSearchText(haystack)
                return terms.allSatisfy { term in
                    let compactTerm = compactSearchText(term)
                    return haystack.contains(term) || (!compactTerm.isEmpty && compactHaystack.contains(compactTerm))
                }
            }
            guard !models.isEmpty else {
                return nil
            }
            return ModelCategorySurface(category: category.category, models: models)
        }
    }

    /// A model qualifies as "<region>-only" when the catalog made an explicit residency claim and
    /// EVERY claimed region is the required one. Unknown residency (empty) never qualifies —
    /// enforcement must fail closed.
    static func isRegionOnly(_ option: ModelOptionSurface, region: String) -> Bool {
        !option.capabilities.regions.isEmpty
            && option.capabilities.regions.allSatisfy { $0 == region }
    }

    /// Recognizes "<region>-only" search tokens ("us-only", "usa-only", "eu-only", "europe-only",
    /// "cn-only", "china-only" — hyphenated or compact) and removes them from the text terms,
    /// returning the canonical region code they enforce. Only the first region token wins.
    static func extractRegionOnlyConstraint(from terms: inout [String]) -> String? {
        var required: String? = nil
        terms.removeAll { term in
            guard required == nil else { return false }
            var stem = term
            if let range = stem.range(of: "-only", options: [.anchored, .backwards]) {
                stem.removeSubrange(range)
            } else if let range = stem.range(of: "only", options: [.anchored, .backwards]), stem.count > 4 {
                stem.removeSubrange(range)
            } else {
                return false
            }
            guard let canonical = ModelCapabilities.normalizedRegions([stem]).first,
                  ["us", "eu", "cn"].contains(canonical)
            else { return false }
            required = canonical
            return true
        }
        return required
    }

    static func scopeSummary(for categories: [ModelCategorySurface]) -> String? {
        let categoryNames = orderedUnique(categories.map(\.category), limit: 3)
        let providerNames = orderedUnique(categories.flatMap { $0.models.map(\.provider) }, limit: 3)
        let categoryText = listSummary(categoryNames, overflow: overflowCount(in: categories.map(\.category), limit: 3))
        let providerText = listSummary(
            providerNames,
            overflow: overflowCount(in: categories.flatMap { $0.models.map(\.provider) }, limit: 3)
        )

        switch (categoryText, providerText) {
        case let (category?, provider?):
            return "Categories: \(category) · Providers: \(provider)"
        case let (category?, nil):
            return "Categories: \(category)"
        case let (nil, provider?):
            return "Providers: \(provider)"
        case (nil, nil):
            return nil
        }
    }

    private static func normalizedTerms(from query: String) -> [String] {
        query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
    }

    private static func categoryScopeMatches(_ category: ModelCategorySurface, terms: [String]) -> Bool {
        let wantsFavorites = terms.contains("favorite") || terms.contains("favorites")
        let wantsRecent = terms.contains("recent")

        if wantsFavorites, category.category != "Favorites" {
            return false
        }
        if wantsRecent, category.category != "Recent" {
            return false
        }
        if category.category == "Favorites", !wantsFavorites {
            return false
        }
        if category.category == "Recent", !wantsRecent {
            return false
        }
        return true
    }

    private static func searchableText(for option: ModelOptionSurface, in category: ModelCategorySurface) -> String {
        [
            category.category,
            option.id,
            option.provider,
            option.displayName,
            option.category,
            option.detailTitle,
            option.metadataSummary,
            option.capabilitySummary,
            option.metadataDetails.joined(separator: " "),
            searchableMetadataRows(option.metadataRows),
            option.badges.joined(separator: " ")
        ].joined(separator: " ")
    }

    private static func searchableMetadataRows(_ rows: [ModelMetadataRowSurface]) -> String {
        rows
            .map { row in
                row.label == "State" ? "state \(row.value)" : row.value
            }
            .joined(separator: " ")
    }

    private static func compactSearchText(_ text: String) -> String {
        let scalars = text
            .lowercased()
            .unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
        return String(String.UnicodeScalarView(scalars))
    }

    private static func orderedUnique(_ values: [String], limit: Int) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            guard seen.insert(key).inserted else { continue }
            result.append(trimmed)
            if result.count == limit { break }
        }
        return result
    }

    private static func overflowCount(in values: [String], limit: Int) -> Int {
        var seen = Set<String>()
        var count = 0
        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if seen.insert(trimmed.lowercased()).inserted {
                count += 1
            }
        }
        return max(0, count - limit)
    }

    private static func listSummary(_ values: [String], overflow: Int) -> String? {
        guard !values.isEmpty else { return nil }
        let suffix = overflow > 0 ? " +\(overflow) more" : ""
        return values.joined(separator: ", ") + suffix
    }
}
