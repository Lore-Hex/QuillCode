import Foundation
@testable import QuillCodePersistence
import XCTest

final class MarketplaceRegistryStoreTests: XCTestCase {
    func testRoundTripsRegistrationsAndPreservesUnrelatedConfiguration() throws {
        let directory = try temporaryDirectory()
        let file = directory.appendingPathComponent("config.toml")
        try "model = \"trustedrouter/fast\"\n".write(to: file, atomically: true, encoding: .utf8)
        let store = MarketplaceRegistryStore(fileURL: file)
        let registration = MarketplaceRegistration(
            name: "Team-Tools",
            sourceType: .git,
            source: "https://github.com/lore-hex/team-tools.git",
            refName: "main",
            sparsePaths: [".agents/plugins", "plugins/review"],
            lastUpdated: "2026-07-16T23:59:00Z",
            lastRevision: "abc123"
        )

        try store.upsert(registration)

        XCTAssertEqual(
            try store.registrations(),
            [MarketplaceRegistration(
                name: "team-tools",
                sourceType: .git,
                source: registration.source,
                refName: "main",
                sparsePaths: registration.sparsePaths,
                lastUpdated: registration.lastUpdated,
                lastRevision: "abc123"
            )]
        )
        XCTAssertEqual(
            try ConfigDocumentStore(fileURL: file).load().values["model"],
            .string("trustedrouter/fast")
        )
    }

    func testRemoveDeletesOnlySelectedMarketplace() throws {
        let file = try temporaryDirectory().appendingPathComponent("config.toml")
        let store = MarketplaceRegistryStore(fileURL: file)
        for name in ["alpha", "beta"] {
            try store.upsert(MarketplaceRegistration(
                name: name,
                sourceType: .local,
                source: "/tmp/\(name)",
                lastUpdated: "2026-07-16T23:59:00Z"
            ))
        }

        XCTAssertTrue(try store.remove(named: "ALPHA"))
        XCTAssertFalse(try store.remove(named: "alpha"))
        XCTAssertEqual(try store.registrations().map(\.name), ["beta"])
    }

    func testRejectsMalformedAndOversizedRegistrations() throws {
        let file = try temporaryDirectory().appendingPathComponent("config.toml")
        try #"""
        [marketplaces.bad]
        source_type = "ftp"
        source = "https://example.test/repo.git"
        last_updated = "now"
        """#.write(to: file, atomically: true, encoding: .utf8)
        let store = MarketplaceRegistryStore(fileURL: file)

        XCTAssertThrowsError(try store.registrations())
        XCTAssertThrowsError(try store.upsert(MarketplaceRegistration(
            name: "../escape",
            sourceType: .git,
            source: "https://example.test/repo.git",
            lastUpdated: "now"
        )))
        XCTAssertThrowsError(try store.upsert(MarketplaceRegistration(
            name: "large",
            sourceType: .git,
            source: String(repeating: "x", count: MarketplaceRegistryStore.maximumSourceBytes + 1),
            lastUpdated: "now"
        )))
    }

    func testMutationRefusesToOverwriteMalformedMarketplaceState() throws {
        let file = try temporaryDirectory().appendingPathComponent("config.toml")
        try #"marketplaces = "corrupt""#
            .write(to: file, atomically: true, encoding: .utf8)
        let store = MarketplaceRegistryStore(fileURL: file)
        let registration = MarketplaceRegistration(
            name: "valid",
            sourceType: .local,
            source: "/tmp/valid",
            lastUpdated: "2026-07-16T23:59:00Z"
        )

        XCTAssertThrowsError(try store.upsert(registration))
        XCTAssertThrowsError(try store.remove(named: "valid"))
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), #"marketplaces = "corrupt""#)
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "quillcode-marketplace-registry-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }
}
