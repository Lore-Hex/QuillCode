import XCTest
@testable import quill_code_desktop

final class QuillCodeDesktopUpdateReminderStoreTests: XCTestCase {
    func testExactReleaseIsDeferredAcrossStoreInstancesUntilDeadline() {
        let defaults = makeDefaults()
        let configuration = makeConfiguration()
        let release = makeRelease(version: "0.2.0", build: "7")
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        QuillCodeDesktopUpdateReminderStore(defaults: defaults).recordDeferral(
            release,
            configuration: configuration,
            now: now
        )

        let reloaded = QuillCodeDesktopUpdateReminderStore(defaults: defaults)
        XCTAssertFalse(
            reloaded.shouldPresentAutomatically(
                release,
                configuration: configuration,
                now: now.addingTimeInterval(23 * 60 * 60)
            )
        )
        XCTAssertTrue(
            reloaded.shouldPresentAutomatically(
                release,
                configuration: configuration,
                now: now.addingTimeInterval(24 * 60 * 60)
            )
        )
    }

    func testNewReleaseBypassesAndClearsExistingDeferral() {
        let defaults = makeDefaults()
        let configuration = makeConfiguration()
        let deferredRelease = makeRelease(version: "0.2.0", build: "7")
        let newerRelease = makeRelease(version: "0.2.0", build: "8")
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let store = QuillCodeDesktopUpdateReminderStore(defaults: defaults)
        store.recordDeferral(deferredRelease, configuration: configuration, now: now)

        XCTAssertTrue(
            store.shouldPresentAutomatically(
                newerRelease,
                configuration: configuration,
                now: now.addingTimeInterval(60)
            )
        )
        XCTAssertTrue(
            store.shouldPresentAutomatically(
                deferredRelease,
                configuration: configuration,
                now: now.addingTimeInterval(60)
            )
        )
    }

    func testSmallClockRollbackDoesNotLoseReminderDeferral() {
        let defaults = makeDefaults()
        let configuration = makeConfiguration()
        let release = makeRelease(version: "0.2.0", build: "7")
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let store = QuillCodeDesktopUpdateReminderStore(defaults: defaults)
        store.recordDeferral(release, configuration: configuration, now: now)

        XCTAssertFalse(
            store.shouldPresentAutomatically(
                release,
                configuration: configuration,
                now: now.addingTimeInterval(-60 * 60)
            )
        )
    }

    func testChannelMismatchCannotCreateOrReuseDeferral() {
        let defaults = makeDefaults()
        var configuration = makeConfiguration()
        configuration.channel = .stable
        let testerRelease = makeRelease(version: "0.2.0", build: "7")
        let store = QuillCodeDesktopUpdateReminderStore(defaults: defaults)
        store.recordDeferral(testerRelease, configuration: configuration, now: Date())

        XCTAssertTrue(
            store.shouldPresentAutomatically(
                testerRelease,
                configuration: configuration,
                now: Date()
            )
        )
    }

    func testRecordContainsOnlyPublicReleaseIdentityAndDeadline() throws {
        let defaults = makeDefaults()
        let configuration = makeConfiguration()
        let release = makeRelease(version: "0.2.0", build: "7")
        QuillCodeDesktopUpdateReminderStore(defaults: defaults).recordDeferral(
            release,
            configuration: configuration,
            now: Date(timeIntervalSince1970: 1_800_000_000)
        )

        let data = try XCTUnwrap(defaults.data(forKey: storageKey(configuration: configuration)))
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        XCTAssertLessThanOrEqual(data.count, 1_024)
        XCTAssertEqual(
            Set(object.keys),
            ["schemaVersion", "channel", "commit", "version", "build", "deferredUntil"]
        )
    }

    func testMalformedAndOversizedRecordsFailOpen() {
        let defaults = makeDefaults()
        let configuration = makeConfiguration()
        let release = makeRelease(version: "0.2.0", build: "7")
        let key = storageKey(configuration: configuration)
        let store = QuillCodeDesktopUpdateReminderStore(defaults: defaults)

        defaults.set(Data("not-json".utf8), forKey: key)
        XCTAssertTrue(store.shouldPresentAutomatically(release, configuration: configuration, now: Date()))
        XCTAssertNil(defaults.object(forKey: key))

        defaults.set(Data(repeating: 0x41, count: 1_025), forKey: key)
        XCTAssertTrue(store.shouldPresentAutomatically(release, configuration: configuration, now: Date()))
        XCTAssertNil(defaults.object(forKey: key))
    }

    func testImplausiblyFutureRecordFailsOpen() throws {
        let defaults = makeDefaults()
        let configuration = makeConfiguration()
        let release = makeRelease(version: "0.2.0", build: "7")
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let record = ReminderRecordFixture(
            schemaVersion: 1,
            channel: release.channel,
            commit: release.commit,
            version: release.version,
            build: release.build,
            deferredUntil: now.addingTimeInterval(49 * 60 * 60)
        )
        defaults.set(
            try JSONEncoder().encode(record),
            forKey: storageKey(configuration: configuration)
        )

        XCTAssertTrue(
            QuillCodeDesktopUpdateReminderStore(defaults: defaults).shouldPresentAutomatically(
                release,
                configuration: configuration,
                now: now
            )
        )
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "QuillCodeDesktopUpdateReminderStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func storageKey(configuration: QuillCodeDesktopUpdateConfiguration) -> String {
        "QuillCodeUpdater.deferredRelease.\(configuration.bundleIdentifier).\(configuration.channel.rawValue)"
    }
}

private struct ReminderRecordFixture: Codable {
    var schemaVersion: Int
    var channel: QuillCodeDesktopUpdateChannel
    var commit: String
    var version: String
    var build: String
    var deferredUntil: Date
}
