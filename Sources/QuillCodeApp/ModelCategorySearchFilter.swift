import Foundation

enum ModelCategorySearchFilter {
    static func filter(_ categories: [ModelCategorySurface], matching query: String) -> [ModelCategorySurface] {
        let terms = normalizedTerms(from: query)
        guard !terms.isEmpty else {
            return categories
        }

        return categories.compactMap { category in
            guard categoryScopeMatches(category, terms: terms) else {
                return nil
            }
            let models = category.models.filter { option in
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
