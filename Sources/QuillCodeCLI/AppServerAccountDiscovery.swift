import Foundation
import QuillCodeCore

extension AppServerSession {
    func readAccount(_ raw: CLIJSONValue) throws -> CLIJSONValue {
        let params = try AppServerParams(raw)
        _ = try params.optionalBool("refreshToken")
        let account: CLIJSONValue = try resolvedTrustedRouterAPIKey() == nil
            ? .null
            : .object(["type": .string("apiKey")])
        return .object([
            "account": account,
            "requiresOpenaiAuth": .bool(false)
        ])
    }

    func readAccountUsage(_ raw: CLIJSONValue) async throws -> CLIJSONValue {
        try AppServerDiscoveryParams.requireEmpty(raw, method: "account/usage/read")
        return AppServerLocalUsage(threads: await repository.list().map(\.thread)).response
    }

    func readAccountRateLimits(_ raw: CLIJSONValue) async throws -> CLIJSONValue {
        try AppServerDiscoveryParams.requireEmpty(raw, method: "account/rateLimits/read")
        let records = await repository.list()
        let catalog = await discoveryModelCatalog()
        let controls = AppServerLocalSpendControls(
            limits: appConfig.runSpendPeriodLimits,
            threads: records.map(\.thread),
            modelCatalog: catalog.models
        ).snapshots
        let legacy = controls.first?.value ?? Self.emptyRateLimitSnapshot
        return .object([
            "rateLimits": legacy,
            "rateLimitsByLimitId": controls.isEmpty
                ? .null
                : .object(Dictionary(uniqueKeysWithValues: controls)),
            "rateLimitResetCredits": .null
        ])
    }

    private static var emptyRateLimitSnapshot: CLIJSONValue {
        .object([
            "limitId": .null,
            "limitName": .null,
            "primary": .null,
            "secondary": .null,
            "credits": .null,
            "individualLimit": .null,
            "planType": .null,
            "rateLimitReachedType": .null
        ])
    }
}

private struct AppServerLocalUsage {
    private let calendar: Calendar
    private let buckets: [(day: Date, tokens: Int64)]
    private let today: Date

    init(threads: [ChatThread], now: Date = Date()) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? calendar.timeZone
        self.calendar = calendar
        self.today = calendar.startOfDay(for: now)
        var totals: [Date: Int64] = [:]
        for event in threads.flatMap(\.events) {
            guard let record = ModelTokenUsageEvent.record(from: event) else { continue }
            let day = calendar.startOfDay(for: event.createdAt)
            totals[day] = Self.saturatingAdd(totals[day, default: 0], Int64(record.usage.totalTokens))
        }
        self.buckets = totals.map { ($0.key, $0.value) }.sorted { $0.day < $1.day }
    }

    var response: CLIJSONValue {
        let lifetime = buckets.reduce(Int64(0)) { Self.saturatingAdd($0, $1.tokens) }
        let streaks = streakSummary
        return .object([
            "summary": .object([
                "lifetimeTokens": .number(Double(lifetime)),
                "peakDailyTokens": .number(Double(buckets.map(\.tokens).max() ?? 0)),
                "longestRunningTurnSec": .null,
                "currentStreakDays": .number(Double(streaks.current)),
                "longestStreakDays": .number(Double(streaks.longest))
            ]),
            "dailyUsageBuckets": .array(buckets.map { bucket in
                .object([
                    "startDate": .string(dayString(bucket.day)),
                    "tokens": .number(Double(bucket.tokens))
                ])
            })
        ])
    }

    private var streakSummary: (current: Int, longest: Int) {
        guard !buckets.isEmpty else { return (0, 0) }
        var longest = 1
        var running = 1
        for index in 1..<buckets.count {
            if calendar.dateComponents([.day], from: buckets[index - 1].day, to: buckets[index].day).day == 1 {
                running += 1
                longest = max(longest, running)
            } else {
                running = 1
            }
        }
        return (buckets.last?.day == today ? running : 0, longest)
    }

    private func dayString(_ date: Date) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    private static func saturatingAdd(_ lhs: Int64, _ rhs: Int64) -> Int64 {
        let (sum, overflow) = lhs.addingReportingOverflow(rhs)
        return overflow ? Int64.max : sum
    }
}

private struct AppServerLocalSpendControls {
    let snapshots: [(key: String, value: CLIJSONValue)]

    init(
        limits: RunSpendPeriodLimits,
        threads: [ChatThread],
        modelCatalog: [ModelInfo],
        now: Date = Date()
    ) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? calendar.timeZone
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        let ledger = RunSpendPeriodLedger(threads: threads, modelCatalog: modelCatalog, now: now)
        self.snapshots = Self.periods(limits: limits, now: now, calendar: calendar).map { period in
            let used = ledger.spendUSD(since: period.start)
            let usedPercent = min(100, max(0, used / period.limit * 100))
            let remainingPercent = min(100, max(0, 100 - usedPercent))
            return (period.id, Self.snapshot(
                period: period,
                used: used,
                usedPercent: usedPercent,
                remainingPercent: remainingPercent
            ))
        }
    }

    private static func snapshot(
        period: AppServerSpendPeriod,
        used: Double,
        usedPercent: Double,
        remainingPercent: Double
    ) -> CLIJSONValue {
        .object([
            "limitId": .string(period.id),
            "limitName": .string("QuillCode local \(period.label) spend control"),
            "primary": .object([
                "usedPercent": .number(usedPercent),
                "windowDurationMins": .number(period.end.timeIntervalSince(period.start) / 60),
                "resetsAt": .number(period.end.timeIntervalSince1970.rounded(.down))
            ]),
            "secondary": .null,
            "credits": .null,
            "individualLimit": .object([
                "limit": .string(decimalString(period.limit)),
                "used": .string(decimalString(used)),
                "remainingPercent": .number(remainingPercent),
                "resetsAt": .number(period.end.timeIntervalSince1970.rounded(.down))
            ]),
            "planType": .null,
            "rateLimitReachedType": used >= period.limit
                ? .string("rate_limit_reached")
                : .null
        ])
    }

    private static func periods(
        limits: RunSpendPeriodLimits,
        now: Date,
        calendar: Calendar
    ) -> [AppServerSpendPeriod] {
        var values: [AppServerSpendPeriod] = []
        let dayStart = calendar.startOfDay(for: now)
        if let limit = limits.dailyUSD,
           let end = calendar.date(byAdding: .day, value: 1, to: dayStart) {
            values.append(.init(id: "quillcode-local-daily", label: "daily", limit: limit, start: dayStart, end: end))
        }
        if let limit = limits.weeklyUSD,
           let interval = calendar.dateInterval(of: .weekOfYear, for: now) {
            values.append(.init(
                id: "quillcode-local-weekly",
                label: "weekly",
                limit: limit,
                start: interval.start,
                end: interval.end
            ))
        }
        if let limit = limits.monthlyUSD,
           let interval = calendar.dateInterval(of: .month, for: now) {
            values.append(.init(
                id: "quillcode-local-monthly",
                label: "monthly",
                limit: limit,
                start: interval.start,
                end: interval.end
            ))
        }
        return values
    }

    private static func decimalString(_ value: Double) -> String {
        var result = String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), value)
        while result.last == "0" { result.removeLast() }
        if result.last == "." { result.removeLast() }
        return result.isEmpty ? "0" : result
    }
}

private struct AppServerSpendPeriod {
    let id: String
    let label: String
    let limit: Double
    let start: Date
    let end: Date
}
