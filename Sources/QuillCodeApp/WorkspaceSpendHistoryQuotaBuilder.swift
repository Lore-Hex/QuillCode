import Foundation
import QuillCodeCore

struct WorkspaceSpendHistoryQuotaBuilder: Sendable, Hashable {
    var threads: [ChatThread]
    var modelCatalog: [ModelInfo]
    var calendar: Calendar = .current
    var now: Date = Date()

    func quotaLimits() -> [TokenQuotaLimitSurface] {
        let periods: [Period] = [
            Period(label: "Today", start: calendar.startOfDay(for: now)),
            Period(label: "Week", start: startOfCurrentWeek()),
            Period(label: "Month", start: startOfCurrentMonth())
        ]

        return periods.compactMap { period in
            let total = spendSince(period.start)
            guard total > 0 else { return nil }
            let cost = RunSpendLedger.costLabel(total)
            return TokenQuotaLimitSurface(
                periodLabel: period.label,
                usageLabel: cost,
                detailLabel: "Local priced model spend \(period.label.lowercased()): \(cost)"
            )
        }
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
    }
}
