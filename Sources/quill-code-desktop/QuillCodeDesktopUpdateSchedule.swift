import Foundation

struct QuillCodeDesktopUpdateSchedule: Equatable, Sendable {
    static let production = Self(
        initialDelay: 3,
        testerInterval: 6 * 60 * 60,
        stableInterval: 24 * 60 * 60,
        failureRetryInterval: 30 * 60,
        busyRetryInterval: 5 * 60
    )

    var initialDelay: TimeInterval
    var testerInterval: TimeInterval
    var stableInterval: TimeInterval
    var failureRetryInterval: TimeInterval
    var busyRetryInterval: TimeInterval

    init(
        initialDelay: TimeInterval,
        testerInterval: TimeInterval,
        stableInterval: TimeInterval,
        failureRetryInterval: TimeInterval,
        busyRetryInterval: TimeInterval
    ) {
        self.initialDelay = Self.normalized(initialDelay, minimum: 0, fallback: 3)
        self.testerInterval = Self.normalized(testerInterval, minimum: 0.01, fallback: 6 * 60 * 60)
        self.stableInterval = Self.normalized(stableInterval, minimum: 0.01, fallback: 24 * 60 * 60)
        self.failureRetryInterval = Self.normalized(
            failureRetryInterval,
            minimum: 0.01,
            fallback: 30 * 60
        )
        self.busyRetryInterval = Self.normalized(
            busyRetryInterval,
            minimum: 0.01,
            fallback: 5 * 60
        )
    }

    func interval(for channel: QuillCodeDesktopUpdateChannel) -> TimeInterval {
        channel == .tester ? testerInterval : stableInterval
    }

    func firstDelay(
        lastSuccessfulCheck: Date?,
        now: Date,
        channel: QuillCodeDesktopUpdateChannel
    ) -> TimeInterval {
        let remaining = remainingDelay(
            lastSuccessfulCheck: lastSuccessfulCheck,
            now: now,
            channel: channel
        )
        return remaining > 0 ? remaining : initialDelay
    }

    func remainingDelay(
        lastSuccessfulCheck: Date?,
        now: Date,
        channel: QuillCodeDesktopUpdateChannel
    ) -> TimeInterval {
        guard let lastSuccessfulCheck else { return 0 }
        let elapsed = now.timeIntervalSince(lastSuccessfulCheck)
        guard elapsed.isFinite else { return 0 }
        return max(0, interval(for: channel) - max(0, elapsed))
    }

    private static func normalized(
        _ value: TimeInterval,
        minimum: TimeInterval,
        fallback: TimeInterval
    ) -> TimeInterval {
        value.isFinite && value >= minimum ? value : fallback
    }
}
