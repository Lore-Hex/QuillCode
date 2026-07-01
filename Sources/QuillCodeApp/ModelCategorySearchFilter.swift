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
                return terms.allSatisfy { haystack.contains($0) }
            }
            guard !models.isEmpty else {
                return nil
            }
            return ModelCategorySurface(category: category.category, models: models)
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
}
