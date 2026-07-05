import Foundation

struct WorkspaceQuotaLimitSurfaceBuilder: Sendable, Hashable {
    var runtimeIssue: RuntimeIssueSurface?

    func quotaLimits() -> [TokenQuotaLimitSurface] {
        guard let runtimeIssue,
              runtimeIssue.recovery?.reason == .rateLimited
        else { return [] }

        var quotas: [TokenQuotaLimitSurface] = []

        if let remaining = diagnosticValue("rate limit remaining", in: runtimeIssue.diagnostics) {
            quotas.append(TokenQuotaLimitSurface(
                periodLabel: "Quota",
                usageLabel: "\(remaining) left",
                detailLabel: "Provider rate-limit quota: \(remaining) remaining"
            ))
        }

        if let reset = diagnosticValue("rate limit reset", in: runtimeIssue.diagnostics)
            ?? diagnosticValue("retry after", in: runtimeIssue.diagnostics) {
            let label = Self.compactDurationLabel(reset)
            quotas.append(TokenQuotaLimitSurface(
                periodLabel: "Reset",
                usageLabel: label,
                detailLabel: "Provider rate-limit reset or retry window: \(reset)"
            ))
        }

        return quotas
    }

    private func diagnosticValue(_ label: String, in diagnostics: [RuntimeDiagnosticSurface]) -> String? {
        diagnostics.first { $0.label.compare(label, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }?
            .value
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func compactDurationLabel(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let seconds = seconds(from: trimmed) else { return value }
        if seconds < 60 {
            return "\(Int(seconds.rounded()))s"
        }
        if seconds < 3_600 {
            return "\(Int((seconds / 60).rounded()))m"
        }
        if seconds < 86_400 {
            let hours = (seconds / 3_600 * 10).rounded() / 10
            return hours == hours.rounded() ? "\(Int(hours))h" : String(format: "%.1fh", hours)
        }
        let days = (seconds / 86_400 * 10).rounded() / 10
        return days == days.rounded() ? "\(Int(days))d" : String(format: "%.1fd", days)
    }

    private static func seconds(from value: String) -> Double? {
        let unitless = value.trimmingCharacters(in: CharacterSet(charactersIn: " s"))
        if let seconds = Double(unitless), seconds.isFinite {
            return max(0, seconds)
        }
        if value.hasSuffix("ms"), let millis = Double(value.dropLast(2)) {
            return max(0, millis / 1_000)
        }
        for suffix in ["seconds", "second", "secs", "sec"] {
            if value.hasSuffix(suffix), let seconds = Double(value.dropLast(suffix.count)) {
                return max(0, seconds)
            }
        }
        return nil
    }
}
