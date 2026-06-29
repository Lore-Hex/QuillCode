import XCTest
import QuillCodeCore
@testable import QuillCodePersistence

final class PersistenceTests: XCTestCase {
    func testConfigRoundTrips() throws {
        let root = try makeTempDirectory()
        let store = ConfigStore(fileURL: root.appendingPathComponent("config.toml"))
        let config = AppConfig(defaultModel: "/synth", mode: .auto, apiBaseURL: "https://api.trustedrouter.com/v1", developerOverrideEnabled: true)
        try store.save(config)
        XCTAssertEqual(try store.load(), config)
        XCTAssertEqual(config.defaultModel, TrustedRouterDefaults.synthModel)
    }

    func testConfigDefaultsToOAuthAuthMode() throws {
        let root = try makeTempDirectory()
        let store = ConfigStore(fileURL: root.appendingPathComponent("config.toml"))
        try store.save(AppConfig())

        let loaded = try store.load()
        XCTAssertEqual(loaded.authMode, .oauth)
        XCTAssertFalse(loaded.developerOverrideEnabled)
    }

    func testConfigRoundTripsTrustedRouterAccountProfile() throws {
        let root = try makeTempDirectory()
        let store = ConfigStore(fileURL: root.appendingPathComponent("config.toml"))
        let config = AppConfig(
            defaultModel: TrustedRouterDefaults.synthModel,
            mode: .auto,
            apiBaseURL: "https://api.trustedrouter.com/v1",
            authMode: .oauth,
            trustedRouterAccount: TrustedRouterAccountProfile(
                userID: "usr_123",
                subject: "sub_quoted\"value",
                email: "quill@example.com",
                walletAddress: "0xabc"
            )
        )

        try store.save(config)
        let loaded = try store.load()

        XCTAssertEqual(loaded, config)
        XCTAssertEqual(loaded.trustedRouterAccount?.displayLabel, "quill@example.com")
    }

    func testConfigRoundTripsFavoriteModels() throws {
        let root = try makeTempDirectory()
        let store = ConfigStore(fileURL: root.appendingPathComponent("config.toml"))
        let config = AppConfig(favoriteModels: [
            " z-ai/glm-5.2 ",
            "moonshotai/kimi-k2.6",
            "z-ai/glm-5.2",
            ""
        ])

        try store.save(config)

        let loaded = try store.load()
        XCTAssertEqual(loaded.favoriteModels, ["z-ai/glm-5.2", "moonshotai/kimi-k2.6"])
        let stored = try String(contentsOf: store.fileURL, encoding: .utf8)
        XCTAssertTrue(stored.contains(#"favorite_model = "z-ai/glm-5.2""#))
        XCTAssertTrue(stored.contains(#"favorite_model = "moonshotai/kimi-k2.6""#))
    }

    func testExplicitAuthModeWinsOverLegacyDeveloperOverrideFlag() throws {
        let root = try makeTempDirectory()
        let fileURL = root.appendingPathComponent("config.toml")
        try """
        default_model = "/synth"
        mode = "auto"
        api_base_url = "https://api.trustedrouter.com/v1"
        auth_mode = "oauth"
        developer_override_enabled = true
        """.write(to: fileURL, atomically: true, encoding: .utf8)

        let loaded = try ConfigStore(fileURL: fileURL).load()
        XCTAssertEqual(loaded.authMode, .oauth)
        XCTAssertFalse(loaded.developerOverrideEnabled)
        XCTAssertEqual(loaded.defaultModel, TrustedRouterDefaults.synthModel)
    }

    func testThreadStoreRoundTrips() throws {
        let root = try makeTempDirectory()
        let store = JSONThreadStore(directory: root)
        var thread = ChatThread(title: "Test")
        thread.messages.append(.init(role: .user, content: "hello"))
        try store.save(thread)
        XCTAssertEqual(try store.load(thread.id).messages.first?.content, "hello")
        XCTAssertEqual(try store.list().count, 1)
    }

    func testProjectStoreRoundTripsSortedByLastOpened() throws {
        let root = try makeTempDirectory()
        let store = JSONProjectStore(fileURL: root.appendingPathComponent("projects.json"))
        let older = ProjectRef(
            name: "Older",
            path: "/tmp/older",
            lastOpenedAt: Date(timeIntervalSince1970: 1)
        )
        let newer = ProjectRef(
            name: "Newer",
            path: "/tmp/newer",
            lastOpenedAt: Date(timeIntervalSince1970: 2)
        )

        try store.save([older, newer])

        XCTAssertEqual(try store.load().map(\.name), ["Newer", "Older"])
    }

    func testProjectStoreRoundTripsSSHProjectConnection() throws {
        let root = try makeTempDirectory()
        let store = JSONProjectStore(fileURL: root.appendingPathComponent("projects.json"))
        let connection = ProjectConnection.ssh(
            path: "/srv/quill",
            host: "feather.local",
            user: "quill",
            port: 2222
        )
        let project = ProjectRef(name: "Feather", path: connection.path, connection: connection)

        try store.save([project])
        let loaded = try XCTUnwrap(store.load().first)

        XCTAssertEqual(loaded.connection, connection)
        XCTAssertEqual(loaded.displayPath, "ssh://quill@feather.local:2222/srv/quill")
        XCTAssertTrue(loaded.isRemote)
    }

    func testAutomationStoreRoundTripsSortedByStatusAndNextRun() throws {
        let root = try makeTempDirectory()
        let store = JSONAutomationStore(fileURL: root.appendingPathComponent("automations.json"))
        let paused = QuillAutomation(
            title: "Paused monitor",
            detail: "Watch later.",
            kind: .monitor,
            status: .paused,
            scheduleKind: .event,
            scheduleDescription: "Event",
            updatedAt: Date(timeIntervalSince1970: 3)
        )
        let later = QuillAutomation(
            title: "Later",
            detail: "Run later.",
            kind: .workspaceSchedule,
            scheduleKind: .cron,
            scheduleDescription: "Daily",
            updatedAt: Date(timeIntervalSince1970: 2),
            nextRunAt: Date(timeIntervalSince1970: 20),
            recurrence: QuillAutomationRecurrence(interval: 1, unit: .days)
        )
        let sooner = QuillAutomation(
            title: "Sooner",
            detail: "Run soon.",
            kind: .threadFollowUp,
            scheduleKind: .heartbeat,
            scheduleDescription: "In 10 minutes",
            updatedAt: Date(timeIntervalSince1970: 1),
            nextRunAt: Date(timeIntervalSince1970: 10)
        )

        try store.save([paused, later, sooner])

        XCTAssertEqual(try store.load().map(\.title), ["Sooner", "Later", "Paused monitor"])
        XCTAssertEqual(
            try store.load().first { $0.title == "Later" }?.recurrence,
            QuillAutomationRecurrence(interval: 1, unit: .days)
        )
    }

    func testAutomationStoreRoundTripsEventSource() throws {
        let root = try makeTempDirectory()
        let store = JSONAutomationStore(fileURL: root.appendingPathComponent("automations.json"))
        let automation = QuillAutomation(
            title: "Watch logs",
            detail: "Summarize watched file changes.",
            kind: .monitor,
            scheduleKind: .event,
            scheduleDescription: "File changes",
            eventSource: QuillAutomationEventSource(kind: .fileChange, path: "logs/watch.txt"),
            updatedAt: Date(timeIntervalSince1970: 1),
            lastRunAt: Date(timeIntervalSince1970: 2)
        )

        try store.save([automation])

        let loaded = try XCTUnwrap(store.load().first)
        XCTAssertEqual(loaded.eventSource, automation.eventSource)
        XCTAssertEqual(loaded.eventSource?.kind, .fileChange)
        XCTAssertEqual(loaded.eventSource?.path, "logs/watch.txt")
    }

    func testAutomationStoreReturnsEmptyListWhenMissing() throws {
        let root = try makeTempDirectory()
        let store = JSONAutomationStore(fileURL: root.appendingPathComponent("automations.json"))

        XCTAssertEqual(try store.load(), [])
    }

    func testProjectStoreDecodesLegacyProjectAsLocalConnection() throws {
        let root = try makeTempDirectory()
        let fileURL = root.appendingPathComponent("projects.json")
        try """
        [
          {
            "id": "00000000-0000-0000-0000-000000000001",
            "name": "Legacy",
            "path": "/tmp/legacy",
            "instructions": [],
            "localActions": [],
            "extensionManifests": [],
            "memories": [],
            "lastOpenedAt": "1970-01-01T00:00:01Z"
          }
        ]
        """.write(to: fileURL, atomically: true, encoding: .utf8)

        let loaded = try XCTUnwrap(JSONProjectStore(fileURL: fileURL).load().first)

        XCTAssertEqual(loaded.connection, .local(path: "/tmp/legacy"))
        XCTAssertFalse(loaded.isRemote)
        XCTAssertEqual(loaded.displayPath, "/tmp/legacy")
    }

    func testFileSecretStoreRoundTrips() throws {
        let root = try makeTempDirectory()
        let store = FileSecretStore(directory: root)
        try store.write("sk-test", for: "trustedrouter:key")
        XCTAssertEqual(try store.read("trustedrouter:key"), "sk-test")
        try store.delete("trustedrouter:key")
        XCTAssertNil(try store.read("trustedrouter:key"))
    }

    func testFileSecretStoreUsesPrivatePermissions() throws {
        let root = try makeTempDirectory()
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path)
        let store = FileSecretStore(directory: root)

        try store.write("sk-test", for: "trustedrouter:key")

        XCTAssertEqual(try posixPermissions(at: root), 0o700)
        let secretFile = try XCTUnwrap(FileManager.default.contentsOfDirectory(atPath: root.path).first)
        XCTAssertEqual(try posixPermissions(at: root.appendingPathComponent(secretFile)), 0o600)
    }

    func testFileSecretStoreSanitizesKeysToSingleFileNames() throws {
        let root = try makeTempDirectory()
        let store = FileSecretStore(directory: root)

        try store.write("sk-test", for: "../trustedrouter/key:prod")

        XCTAssertEqual(try store.read("../trustedrouter/key:prod"), "sk-test")
        let files = try FileManager.default.contentsOfDirectory(atPath: root.path)
        XCTAssertEqual(files, ["_trustedrouter_key_prod"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("trustedrouter").path))
    }

    private func makeTempDirectory() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("QuillCodePersistenceTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func posixPermissions(at url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let permissions = try XCTUnwrap(attributes[.posixPermissions] as? NSNumber)
        return permissions.intValue & 0o777
    }
}
