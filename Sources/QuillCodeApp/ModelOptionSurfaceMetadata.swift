import Foundation
import QuillCodeCore

extension ModelOptionSurface {
    static func metadataSummary(
        modelID: String,
        category: String,
        capabilities: ModelCapabilities
    ) -> String {
        if let summary = capabilities.summary {
            return summary
        }
        let canonicalModelID = TrustedRouterDefaults.canonicalModelID(modelID)
        if let summary = TrustedRouterDefaults.recommendedSummaries[canonicalModelID] {
            return summary
        }
        if category == TrustedRouterDefaults.safetyCategory {
            return "Auto safety reviewer"
        }
        return "\(category) model"
    }

    static func detailTitle(modelID: String, provider: String, displayName: String) -> String {
        let canonicalModelID = TrustedRouterDefaults.canonicalModelID(modelID)
        if let recommendedName = TrustedRouterDefaults.recommendedDisplayNames[canonicalModelID] {
            return recommendedName
        }
        let trimmedDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedDisplayName.isEmpty {
            return trimmedDisplayName
        }
        return modelID
    }

    static func capabilitySummary(
        modelID: String,
        category: String,
        badges: [String],
        capabilities: ModelCapabilities
    ) -> String {
        let facts = capabilityFacts(capabilities)
        if !facts.isEmpty {
            return facts.joined(separator: " · ")
        }
        let canonicalModelID = TrustedRouterDefaults.canonicalModelID(modelID)
        if let summary = TrustedRouterDefaults.recommendedCapabilitySummaries[canonicalModelID] {
            return summary
        }
        if badges.contains("Recommended") {
            return "Recommended model profile available through TrustedRouter."
        }
        if category == "Safety" {
            return "Lightweight reviewer model for Auto safety decisions."
        }
        return "\(category) model available through TrustedRouter."
    }

    static func metadataRows(
        provider: String,
        modelID: String,
        category: String,
        capabilities: ModelCapabilities,
        isSelected: Bool,
        isFavorite: Bool,
        badges: [String]
    ) -> [ModelMetadataRowSurface] {
        var rows = [
            ModelMetadataRowSurface(label: "Provider", value: provider),
            ModelMetadataRowSurface(
                label: "Model ID",
                value: TrustedRouterDefaults.preferredDisplayModelID(modelID)
            ),
            ModelMetadataRowSurface(label: "Category", value: category)
        ]
        rows.append(contentsOf: capabilityRows(capabilities))
        let state = stateLabels(
            isSelected: isSelected,
            isFavorite: isFavorite,
            badges: badges
        )
        rows.append(ModelMetadataRowSurface(
            label: "State",
            value: state.joined(separator: ", ")
        ))
        return rows
    }

    static func metadataDetails(
        provider: String,
        modelID: String,
        category: String,
        capabilities: ModelCapabilities,
        isSelected: Bool,
        isFavorite: Bool,
        badges: [String]
    ) -> [String] {
        var details = [
            "Provider: \(provider)",
            "Model ID: \(TrustedRouterDefaults.preferredDisplayModelID(modelID))",
            "Category: \(category)"
        ]
        details.append(contentsOf: capabilityRows(capabilities).map { "\($0.label): \($0.value)" })
        if isSelected {
            details.append("Current selection")
        }
        if isFavorite {
            details.append("Favorite")
        }
        for badge in badges {
            switch badge {
            case "Default":
                details.append("Default model")
            case "Recommended":
                details.append("Recommended by QuillCode")
            case "Recent":
                details.append("Recently used")
            case "Current", "Favorite":
                continue
            default:
                details.append(badge)
            }
        }
        return unique(details)
    }

    var accessibilityLabel: String {
        let stateRow = metadataRows.first { $0.label == "State" }?.value ?? "Available"
        return [
            detailTitle,
            "Provider \(provider)",
            "Category \(category)",
            "State \(stateRow)",
            capabilitySummary
        ]
        .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        .joined(separator: ", ")
    }

    private static func capabilityRows(_ capabilities: ModelCapabilities) -> [ModelMetadataRowSurface] {
        var rows: [ModelMetadataRowSurface] = []
        if let status = capabilities.status {
            rows.append(ModelMetadataRowSurface(label: "Status", value: status))
        }
        if let contextWindowTokens = capabilities.contextWindowTokens {
            rows.append(ModelMetadataRowSurface(label: "Context", value: tokenCountLabel(contextWindowTokens)))
        }
        if !capabilities.inputModalities.isEmpty || !capabilities.outputModalities.isEmpty {
            rows.append(ModelMetadataRowSurface(label: "Modalities", value: modalitiesLabel(capabilities)))
        }
        if let pricing = pricingLabel(capabilities) {
            rows.append(ModelMetadataRowSurface(label: "Pricing", value: pricing))
        }
        if !capabilities.capabilityTags.isEmpty {
            rows.append(ModelMetadataRowSurface(
                label: "Capabilities",
                value: capabilities.capabilityTags.joined(separator: ", ")
            ))
        }
        return rows
    }

    private static func capabilityFacts(_ capabilities: ModelCapabilities) -> [String] {
        var facts: [String] = []
        if let contextWindowTokens = capabilities.contextWindowTokens {
            facts.append("\(tokenCountLabel(contextWindowTokens)) context")
        }
        if !capabilities.inputModalities.isEmpty || !capabilities.outputModalities.isEmpty {
            facts.append(modalitiesLabel(capabilities))
        }
        if let pricing = pricingLabel(capabilities) {
            facts.append(pricing)
        }
        if !capabilities.capabilityTags.isEmpty {
            facts.append(capabilities.capabilityTags.prefix(4).joined(separator: ", "))
        }
        if let status = capabilities.status {
            facts.append(status)
        }
        return facts
    }

    private static func stateLabels(isSelected: Bool, isFavorite: Bool, badges: [String]) -> [String] {
        var state: [String] = []
        if isSelected {
            state.append("Current")
        }
        if badges.contains("Default") {
            state.append("Default")
        }
        if badges.contains("Recommended") {
            state.append("Recommended")
        }
        if isFavorite || badges.contains("Favorite") {
            state.append("Favorite")
        }
        if badges.contains("Recent") {
            state.append("Recent")
        }
        return state.isEmpty ? ["Available"] : unique(state)
    }

    private static func modalitiesLabel(_ capabilities: ModelCapabilities) -> String {
        let input = modalityListLabel(capabilities.inputModalities)
        let output = modalityListLabel(capabilities.outputModalities)
        return "\(input) -> \(output)"
    }

    private static func modalityListLabel(_ modalities: [String]) -> String {
        modalities.isEmpty ? "any" : modalities.joined(separator: ", ")
    }

    private static func pricingLabel(_ capabilities: ModelCapabilities) -> String? {
        switch (capabilities.inputPricePerMillionTokens, capabilities.outputPricePerMillionTokens) {
        case (.some(let input), .some(let output)):
            return "\(currencyLabel(input)) in / \(currencyLabel(output)) out per 1M"
        case (.some(let input), .none):
            return "\(currencyLabel(input)) input per 1M"
        case (.none, .some(let output)):
            return "\(currencyLabel(output)) output per 1M"
        case (.none, .none):
            return nil
        }
    }

    private static func tokenCountLabel(_ value: Int) -> String {
        if value >= 1_000_000 {
            return "\(trimmed(Double(value) / 1_000_000))M"
        }
        if value >= 1_000 {
            return "\(trimmed(Double(value) / 1_000))K"
        }
        return "\(value)"
    }

    private static func currencyLabel(_ value: Double) -> String {
        "$\(trimmed(value))"
    }

    private static func trimmed(_ value: Double) -> String {
        let formatted = String(format: "%.4f", value)
        return formatted
            .replacingOccurrences(of: #"0+$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\.$"#, with: "", options: .regularExpression)
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values where seen.insert(value).inserted {
            result.append(value)
        }
        return result
    }
}
