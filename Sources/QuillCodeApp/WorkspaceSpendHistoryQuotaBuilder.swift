import Foundation
import QuillCodeCore

struct WorkspaceSpendHistoryQuotaBuilder: Sendable, Hashable {
    var threads: [ChatThread]
    var modelCatalog: [ModelInfo]
    var periodLimits: RunSpendPeriodLimits = RunSpendPeriodLimits()
    var calendar: Calendar = .current
    var now: Date = Date()

    func quotaLimits() -> [TokenQuotaLimitSurface] {
        let periods: [Period] = [
            Period(label: "Today", start: calendar.startOfDay(for: now), limitUSD: periodLimits.dailyUSD),
            Period(label: "Week", start: startOfCurrentWeek(), limitUSD: periodLimits.weeklyUSD),
            Period(label: "Month", start: startOfCurrentMonth(), limitUSD: periodLimits.monthlyUSD)
        ]

        return periods.compactMap { period in
            let total = spendSince(period.start)
            guard total > 0 || period.limitUSD != nil else { return nil }
            return TokenQuotaLimitSurface(
                periodLabel: period.label,
                usageLabel: usageLabel(spendUSD: total, limitUSD: period.limitUSD),
                detailLabel: detailLabel(period: period.label, spendUSD: total, limitUSD: period.limitUSD)
            )
        }
    }

    private func usageLabel(spendUSD: Double, limitUSD: Double?) -> String {
        let spend = RunSpendLedger.costLabel(spendUSD)
        guard let limitUSD else { return spend }
        return "\(spend) / \(RunSpendLedger.costLabel(limitUSD))"
    }

    private func detailLabel(period: String, spendUSD: Double, limitUSD: Double?) -> String {
        let spend = RunSpendLedger.costLabel(spendUSD)
        guard let limitUSD else {
            return "Local priced model spend \(period.lowercased()): \(spend)"
        }
        let limit = RunSpendLedger.costLabel(limitUSD)
        let percent = Int((spendUSD / max(limitUSD, 0.000_000_001) * 100).rounded())
        return "Local priced model spend \(period.lowercased()): \(spend) of \(limit) · \(max(0, percent))% used"
    }

    private func spendSince(_ start: Date) -> Double {
        threads.reduce(0) { total, thread in
            let periodThread = ChatThread(
                id: thread.id,
                title: thread.title,
                projectID: thread.projectID,
                mode: thread.mode,
                model: thread.model,
                messages: [],
                events: thread.events.filter { $0.createdAt >= start && $0.createdAt <= now },
                createdAt: thread.createdAt,
                updatedAt: thread.updatedAt,
                instructions: thread.instructions,
                memories: thread.memories,
                composerDraft: thread.composerDraft,
                followUpQueue: thread.followUpQueue
            )
            let ledger = RunSpendLedger(thread: periodThread, modelCatalog: modelCatalog, fuseUSD: nil)
            return total + ledger.totalUSD
        }
    }

    private func startOfCurrentWeek() -> Date {
        calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? calendar.startOfDay(for: now)
    }

    private func startOfCurrentMonth() -> Date {
        calendar.dateInterval(of: .month, for: now)?.start ?? calendar.startOfDay(for: now)
    }

    private struct Period: Hashable {
        var label: String
        var start: Date
        var limitUSD: Double?
    }
}
