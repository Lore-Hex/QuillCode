import Foundation

struct QuillCodeDesktopUpdateReminderStore {
    static let productionInterval: TimeInterval = 24 * 60 * 60

    private static let schemaVersion = 1
    private static let maximumRecordBytes = 1_024
    private static let maximumClockRollbackAllowance: TimeInterval = 24 * 60 * 60

    private let defaults: UserDefaults
    private let reminderInterval: TimeInterval

    init(
        defaults: UserDefaults,
        reminderInterval: TimeInterval = productionInterval
    ) {
        self.defaults = defaults
        self.reminderInterval = Self.normalizedInterval(reminderInterval)
    }

    func recordDeferral(
        _ release: QuillCodeDesktopUpdateRelease,
        configuration: QuillCodeDesktopUpdateConfiguration,
        now: Date
    ) {
        guard release.channel == configuration.channel else {
            clear(configuration: configuration)
            return
        }
        let record = Record(
            schemaVersion: Self.schemaVersion,
            channel: release.channel,
            commit: release.commit,
            version: release.version,
            build: release.build,
            deferredUntil: now.addingTimeInterval(reminderInterval)
        )
        let key = storageKey(configuration: configuration)
        guard let data = try? JSONEncoder().encode(record),
              data.count <= Self.maximumRecordBytes
        else {
            defaults.removeObject(forKey: key)
            return
        }
        defaults.set(data, forKey: key)
    }

    func shouldPresentAutomatically(
        _ release: QuillCodeDesktopUpdateRelease,
        configuration: QuillCodeDesktopUpdateConfiguration,
        now: Date
    ) -> Bool {
        remainingDeferral(
            for: release,
            configuration: configuration,
            now: now
        ) == nil
    }

    func remainingDeferral(
        for release: QuillCodeDesktopUpdateRelease,
        configuration: QuillCodeDesktopUpdateConfiguration,
        now: Date
    ) -> TimeInterval? {
        let key = storageKey(configuration: configuration)
        guard let data = defaults.data(forKey: key),
              data.count <= Self.maximumRecordBytes,
              let record = try? JSONDecoder().decode(Record.self, from: data),
              record.schemaVersion == Self.schemaVersion,
              record.channel == configuration.channel,
              release.channel == configuration.channel,
              record.matches(release),
              hasPlausibleFutureDeadline(record.deferredUntil, now: now)
        else {
            defaults.removeObject(forKey: key)
            return nil
        }
        return record.deferredUntil.timeIntervalSince(now)
    }

    func clear(configuration: QuillCodeDesktopUpdateConfiguration) {
        defaults.removeObject(forKey: storageKey(configuration: configuration))
    }

    private func hasPlausibleFutureDeadline(_ deadline: Date, now: Date) -> Bool {
        let remaining = deadline.timeIntervalSince(now)
        return remaining.isFinite
            && remaining > 0
            && remaining <= reminderInterval + Self.maximumClockRollbackAllowance
    }

    private func storageKey(configuration: QuillCodeDesktopUpdateConfiguration) -> String {
        "QuillCodeUpdater.deferredRelease.\(configuration.bundleIdentifier).\(configuration.channel.rawValue)"
    }

    private static func normalizedInterval(_ interval: TimeInterval) -> TimeInterval {
        guard interval.isFinite, interval > 0 else { return productionInterval }
        return min(interval, 7 * 24 * 60 * 60)
    }
}

private extension QuillCodeDesktopUpdateReminderStore {
    struct Record: Codable {
        var schemaVersion: Int
        var channel: QuillCodeDesktopUpdateChannel
        var commit: String
        var version: String
        var build: String
        var deferredUntil: Date

        func matches(_ release: QuillCodeDesktopUpdateRelease) -> Bool {
            channel == release.channel
                && commit == release.commit
                && version == release.version
                && build == release.build
        }
    }
}
