import QuillCodeCore

struct WorkspaceTokenBudgetSurfaceBuilder: Sendable, Hashable {
    var thread: ChatThread?
    var selectedModelID: String
    var modelCatalog: [ModelInfo]
    var fallbackTokenBudget: Int = WorkspaceContextBannerBuilder.defaultTokenBudget
    var quotaLimits: [TokenQuotaLimitSurface] = []

    func surface() -> TokenBudgetSurface? {
        guard let thread else { return nil }
        let usage = WorkspaceContextBannerBuilder.latestProviderUsage(for: thread)
        let usedTokens = max(0, usage?.contextTokens ?? WorkspaceContextBannerBuilder.estimatedContextTokens(for: thread))
        let limitTokens = contextWindowTokens() ?? max(1, fallbackTokenBudget)
        let remainingTokens = max(0, limitTokens - usedTokens)
        let usedPercent = Int((Double(usedTokens) / Double(limitTokens) * 100).rounded())
        let sourceLabel = usage == nil ? "Estimated" : "Provider reported"
        var secondaryParts = [
            "\(WorkspaceTokenUsageLabelBuilder.abbreviate(remainingTokens)) left",
            "\(max(0, usedPercent))%"
        ]
        if let usage {
            secondaryParts.append(
                "↑\(WorkspaceTokenUsageLabelBuilder.abbreviate(usage.promptTokens)) ↓\(WorkspaceTokenUsageLabelBuilder.abbreviate(usage.completionTokens))"
            )
        }
        secondaryParts.append(
            sourceLabel.lowercased()
        )

        return TokenBudgetSurface(
            usedTokens: usedTokens,
            limitTokens: limitTokens,
            remainingTokens: remainingTokens,
            usedPercent: max(0, usedPercent),
            progressPercent: min(100, max(0, usedPercent)),
            primaryLabel: "\(WorkspaceTokenUsageLabelBuilder.abbreviate(usedTokens)) / \(WorkspaceTokenUsageLabelBuilder.abbreviate(limitTokens)) tokens",
            secondaryLabel: secondaryParts.joined(separator: " · "),
            detailLabel: detailLabel(
                usedTokens: usedTokens,
                limitTokens: limitTokens,
                remainingTokens: remainingTokens,
                usedPercent: usedPercent,
                usage: usage,
                sourceLabel: sourceLabel
            ),
            sourceLabel: sourceLabel,
            quotaLimits: quotaLimits
        )
    }

    private func contextWindowTokens() -> Int? {
        let canonicalModelID = TrustedRouterDefaults.canonicalModelID(thread?.model ?? selectedModelID)
        let model = TrustedRouterDefaults.normalizedModelCatalog(modelCatalog).first {
            TrustedRouterDefaults.canonicalModelID($0.id) == canonicalModelID
        }
        guard let tokens = model?.capabilities.contextWindowTokens, tokens > 0 else { return nil }
        return tokens
    }

    private func detailLabel(
        usedTokens: Int,
        limitTokens: Int,
        remainingTokens: Int,
        usedPercent: Int,
        usage: ModelTokenUsage?,
        sourceLabel: String
    ) -> String {
        var parts = [
            "\(sourceLabel) token budget: \(decimal(usedTokens)) used of \(decimal(limitTokens))",
            "\(decimal(remainingTokens)) left",
            "\(max(0, usedPercent))% used"
        ]
        if let usage {
            parts.append("input \(decimal(usage.promptTokens))")
            parts.append("output \(decimal(usage.completionTokens))")
        }
        return parts.joined(separator: " · ")
    }

    private func decimal(_ value: Int) -> String {
        let digits = String(max(0, value))
        var output = ""
        for (offset, character) in digits.reversed().enumerated() {
            if offset > 0, offset.isMultiple(of: 3) {
                output.append(",")
            }
            output.append(character)
        }
        return String(output.reversed())
    }
}
