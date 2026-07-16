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
        let windowTokens = contextWindowTokens()
        // Provider-reported usage against a model whose window the catalog does not know is NOT a
        // percentage of anything: substituting the 32k fallback invented "58.4k / 32k · 183% · 0
        // left" for a model with a far larger window. In that case show the honest usage-only chip.
        // The fallback stays only for the LOCAL-estimate mode, which is explicitly labeled Estimated.
        if usage != nil, windowTokens == nil {
            return usageOnlySurface(usedTokens: usedTokens, usage: usage)
        }
        let limitTokens = windowTokens ?? max(1, fallbackTokenBudget)
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
            primaryLabel: "\(WorkspaceTokenUsageLabelBuilder.abbreviate(usedTokens)) / \(WorkspaceTokenUsageLabelBuilder.abbreviate(limitTokens))",
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
        Self.modelContextWindowTokens(
            threadModel: thread?.model,
            selectedModelID: selectedModelID,
            modelCatalog: modelCatalog
        )
    }

    /// The catalog-reported context window for the thread's model (falling back to the top-bar
    /// selection), or nil when the catalog does not know it. Shared with the context-limit banner so
    /// the chip and the banner can never disagree about what the window is.
    static func modelContextWindowTokens(
        threadModel: String?,
        selectedModelID: String,
        modelCatalog: [ModelInfo]
    ) -> Int? {
        let canonicalModelID = TrustedRouterDefaults.canonicalModelID(threadModel ?? selectedModelID)
        let model = TrustedRouterDefaults.normalizedModelCatalog(modelCatalog).first {
            TrustedRouterDefaults.canonicalModelID($0.id) == canonicalModelID
        }
        guard let tokens = model?.capabilities.contextWindowTokens, tokens > 0 else { return nil }
        return tokens
    }

    /// The honest chip for provider-reported usage against an UNKNOWN window: real numbers, no
    /// invented limit, no percent, no "0 left". The progress bar renders empty (0%).
    private func usageOnlySurface(usedTokens: Int, usage: ModelTokenUsage?) -> TokenBudgetSurface {
        var secondaryParts: [String] = []
        if let usage {
            secondaryParts.append(
                "↑\(WorkspaceTokenUsageLabelBuilder.abbreviate(usage.promptTokens)) ↓\(WorkspaceTokenUsageLabelBuilder.abbreviate(usage.completionTokens))"
            )
        }
        secondaryParts.append("window unknown")
        var detailParts = ["Provider reported \(decimal(usedTokens)) tokens used; the model's context window is not in the catalog"]
        if let usage {
            detailParts.append("input \(decimal(usage.promptTokens))")
            detailParts.append("output \(decimal(usage.completionTokens))")
        }
        return TokenBudgetSurface(
            usedTokens: usedTokens,
            limitTokens: max(1, usedTokens),
            remainingTokens: 0,
            usedPercent: 0,
            progressPercent: 0,
            primaryLabel: WorkspaceTokenUsageLabelBuilder.abbreviate(usedTokens),
            secondaryLabel: secondaryParts.joined(separator: " · "),
            detailLabel: detailParts.joined(separator: " · "),
            sourceLabel: "Provider reported",
            quotaLimits: quotaLimits
        )
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
