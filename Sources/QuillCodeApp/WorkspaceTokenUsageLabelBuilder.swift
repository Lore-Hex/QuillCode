import QuillCodeCore

/// Builds the quiet top-bar token-usage label from a model's reported usage, e.g.
/// `847 ctx · ↑500 ↓347` (the renderers show it in tabular digits). Returns `nil` when
/// there is no usage to show. The string is formatted ONCE here so the native, HTML, and
/// harness surfaces all display the same server-built value and can never drift — the same
/// single-source pattern the branch chip uses.
public enum WorkspaceTokenUsageLabelBuilder {
    public static func label(for usage: ModelTokenUsage?) -> String? {
        // A nil — or an all-zero/malformed (the decoder defaults missing fields to 0) —
        // usage has nothing meaningful to show, so the chip is suppressed entirely.
        guard let usage, usage.contextTokens > 0 else { return nil }
        return "\(abbreviate(usage.contextTokens)) ctx · ↑\(abbreviate(usage.promptTokens)) ↓\(abbreviate(usage.completionTokens))"
    }

    /// Compact count: exact below 1k, one-decimal k below 1m, one-decimal m above — so the
    /// chip stays narrow and never causes layout jitter. The unit is chosen on the ROUNDED
    /// value, so 999_999 reads `1m` (not `1000k`).
    static func abbreviate(_ count: Int) -> String {
        let value = max(0, count)
        if value < 1_000 { return "\(value)" }
        if value < 1_000_000 {
            let thousands = roundedOneDecimal(Double(value) / 1_000)
            if thousands < 1_000 { return "\(trim(thousands))k" }
            // Rounding crossed into millions; fall through to the m unit.
        }
        return "\(trim(roundedOneDecimal(Double(value) / 1_000_000)))m"
    }

    private static func roundedOneDecimal(_ value: Double) -> Double {
        (value * 10).rounded() / 10
    }

    private static func trim(_ value: Double) -> String {
        value == value.rounded() ? "\(Int(value))" : String(format: "%.1f", value)
    }
}
