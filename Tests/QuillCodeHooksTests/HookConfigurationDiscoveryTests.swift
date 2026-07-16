import Foundation
import QuillCodeCore
import QuillCodePersistence
import XCTest
@testable import QuillCodeHooks

final class HookConfigurationDiscoveryTests: XCTestCase {
    func testMissingHookDocumentsAreQuiet() throws {
        let root = try temporaryDirectory()

        let discovery = ProjectHookConfigurationLoader.discover(from: root)

        XCTAssertTrue(discovery.hooks.isEmpty)
        XCTAssertTrue(discovery.warnings.isEmpty)
    }

    func testValidDocumentsSurviveAParseFailureInAnotherLayer() throws {
        let root = try temporaryDirectory()
        try write(
            #"{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"printf valid"}]}]}}"#,
            to: ".quillcode/hooks.json",
            in: root
        )
        try write("not valid TOML", to: ".codex/config.toml", in: root)

        let discovery = ProjectHookConfigurationLoader.discover(from: root)

        XCTAssertEqual(discovery.hooks.map(\.command), ["printf valid"])
        XCTAssertEqual(discovery.warnings.count, 1)
        XCTAssertTrue(discovery.warnings[0].contains("failed to parse hooks config"))
        XCTAssertTrue(discovery.warnings[0].contains(".codex/config.toml"))
    }

    func testUnsafeAndOversizedDocumentsReportBoundedWarnings() throws {
        let root = try temporaryDirectory()
        let outside = try temporaryDirectory()
        let outsideHooks = outside.appendingPathComponent("hooks.json")
        try #"{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"printf escaped"}]}]}}"#
            .write(to: outsideHooks, atomically: true, encoding: .utf8)

        let link = root.appendingPathComponent(".codex/hooks.json")
        try FileManager.default.createDirectory(
            at: link.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outsideHooks)
        try write(
            String(repeating: "x", count: ProjectHookConfigurationLoader.maxDocumentBytes + 1),
            to: ".quillcode/config.toml",
            in: root
        )

        let discovery = ProjectHookConfigurationLoader.discover(from: root)

        XCTAssertTrue(discovery.hooks.isEmpty)
        XCTAssertEqual(discovery.warnings.count, 2)
        XCTAssertTrue(discovery.warnings.contains { $0.contains("refusing symlinked hooks config") })
        XCTAssertTrue(discovery.warnings.contains { $0.contains("byte limit") })
    }

    func testDiscoveryRetainsCatalogMetadataStateAndProjectPolicy() throws {
        let root = try temporaryDirectory()
        try write(
            """
            [features]
            hooks = false

            [[hooks.Stop]]

            [[hooks.Stop.hooks]]
            type = "command"
            command = "printf catalog"

            [hooks.state.valid]
            enabled = false
            trusted_hash = "abc123"

            [hooks.state.invalid]
            enabled = "not-a-boolean"
            """,
            to: ".quillcode/config.toml",
            in: root
        )

        let discovery = ProjectHookConfigurationLoader.discover(from: root)

        let definition = try XCTUnwrap(discovery.definitions.first)
        XCTAssertEqual(discovery.hooks, [definition.hook])
        XCTAssertEqual(definition.source, .project)
        XCTAssertEqual(
            definition.sourcePath.path,
            root.appendingPathComponent(".quillcode/config.toml").path
        )
        XCTAssertEqual(definition.key, "\(definition.sourcePath.path):stop:0:0")
        XCTAssertEqual(discovery.hookStates["valid"]?.enabled, false)
        XCTAssertEqual(discovery.hookStates["valid"]?.trustedHash, "abc123")
        XCTAssertNil(discovery.hookStates["invalid"])
        XCTAssertEqual(discovery.hooksFeatureOverride, false)
    }

    func testCatalogResolverAppliesStateTrustAndStableDisplayOrder() throws {
        let root = try temporaryDirectory()
        try write(
            """
            [[hooks.Stop]]

            [[hooks.Stop.hooks]]
            type = "command"
            command = "printf resolve"
            """,
            to: ".quillcode/config.toml",
            in: root
        )
        let definition = try XCTUnwrap(
            ProjectHookConfigurationLoader.discover(from: root).definitions.first
        )

        let unresolved = try XCTUnwrap(HookCatalogResolver.resolve(
            [definition],
            displayOrderOffset: 4
        ).first)
        XCTAssertTrue(unresolved.enabled)
        XCTAssertEqual(unresolved.displayOrder, 4)
        XCTAssertEqual(unresolved.trustStatus, .untrusted)

        let trusted = try XCTUnwrap(HookCatalogResolver.resolve(
            [definition],
            states: [definition.key: HookConfigurationState(
                enabled: false,
                trustedHash: definition.hook.definitionHash
            )]
        ).first)
        XCTAssertFalse(trusted.enabled)
        XCTAssertEqual(trusted.trustStatus, .trusted)

        let modified = try XCTUnwrap(HookCatalogResolver.resolve(
            [definition],
            states: [definition.key: HookConfigurationState(trustedHash: "stale")]
        ).first)
        XCTAssertEqual(modified.trustStatus, .modified)

        let legacyTrust = ProjectHookTrustLoadResult(records: [ProjectHookTrustRecord(
            hookID: definition.hook.id,
            definitionHash: definition.hook.definitionHash,
            decision: .trusted
        )])
        XCTAssertEqual(
            HookCatalogResolver.resolve([definition], trust: legacyTrust).first?.trustStatus,
            .trusted
        )

        let legacyDisabled = ProjectHookTrustLoadResult(records: [ProjectHookTrustRecord(
            hookID: definition.hook.id,
            definitionHash: definition.hook.definitionHash,
            decision: .disabled
        )])
        XCTAssertFalse(
            try XCTUnwrap(HookCatalogResolver.resolve([definition], trust: legacyDisabled).first)
                .enabled
        )
        XCTAssertTrue(
            try XCTUnwrap(HookCatalogResolver.resolve(
                [definition],
                states: [definition.key: HookConfigurationState(enabled: true)],
                trust: legacyDisabled
            ).first).enabled
        )
    }

    private func temporaryDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuillCodeHooksTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }

    private func write(_ value: String, to relativePath: String, in root: URL) throws {
        let destination = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try value.write(to: destination, atomically: true, encoding: .utf8)
    }
}
