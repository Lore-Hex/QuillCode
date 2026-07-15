import Foundation
import XCTest
import QuillCodeCore
@testable import QuillCodePersistence

final class ConfigStorePersonalityTests: PersistenceTestCase {
    func testConfigStoreRoundTripsDefaultPersonality() throws {
        let store = ConfigStore(fileURL: try makeTempDirectory().appendingPathComponent("config.toml"))

        try store.save(AppConfig(defaultPersonality: .friendly))

        XCTAssertEqual(try store.load().defaultPersonality, .friendly)
        let stored = try String(contentsOf: store.fileURL, encoding: .utf8)
        XCTAssertTrue(stored.contains(#"personality = "friendly""#))
    }

    func testLegacyConfigParsesPersonalityAndDefaultsWhenAbsent() throws {
        let directory = try makeTempDirectory()
        let configuredURL = directory.appendingPathComponent("configured.toml")
        try #"personality = "none""#.write(to: configuredURL, atomically: true, encoding: .utf8)

        XCTAssertEqual(try ConfigStore(fileURL: configuredURL).load().defaultPersonality, .none)
        XCTAssertEqual(
            try ConfigStore(fileURL: directory.appendingPathComponent("missing.toml")).load().defaultPersonality,
            .pragmatic
        )
    }
}
