import XCTest
import QuillCodeCore
@testable import QuillCodePersistence

final class PersistenceTests: XCTestCase {
    func testConfigRoundTrips() throws {
        let root = try makeTempDirectory()
        let store = ConfigStore(fileURL: root.appendingPathComponent("config.toml"))
        let config = AppConfig(defaultModel: "trustedrouter/fusion", mode: .auto, apiBaseURL: "https://api.quillrouter.com/v1", developerOverrideEnabled: true)
        try store.save(config)
        XCTAssertEqual(try store.load(), config)
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

    func testFileSecretStoreRoundTrips() throws {
        let root = try makeTempDirectory()
        let store = FileSecretStore(directory: root)
        try store.write("sk-test", for: "trustedrouter:key")
        XCTAssertEqual(try store.read("trustedrouter:key"), "sk-test")
        try store.delete("trustedrouter:key")
        XCTAssertNil(try store.read("trustedrouter:key"))
    }

    private func makeTempDirectory() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("QuillCodePersistenceTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
