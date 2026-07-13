import XCTest
import QuillCodeCore
@testable import QuillCodePersistence

final class ProjectHookTrustStoreTests: XCTestCase {
    func testMissingFileRequiresReviewWithoutDegrading() throws {
        let setup = try makeSetup()

        let loaded = setup.store.load(forWorkspaceRoot: setup.root)

        XCTAssertFalse(loaded.degraded)
        XCTAssertTrue(loaded.records.isEmpty)
        XCTAssertEqual(loaded.status(for: makeHook()), .reviewRequired)
    }

    func testExactDefinitionTrustRoundTripsAndChangedDefinitionRequiresReview() throws {
        let setup = try makeSetup()
        let hook = makeHook(hash: String(repeating: "a", count: 64))
        let changedHook = makeHook(hash: String(repeating: "b", count: 64))

        try setup.store.setDecision(.trusted, for: hook, workspaceRoot: setup.root)
        let loaded = setup.store.load(forWorkspaceRoot: setup.root)

        XCTAssertEqual(loaded.status(for: hook), .trusted)
        XCTAssertEqual(loaded.status(for: changedHook), .reviewRequired)
    }

    func testDisabledDecisionAndWorkspaceIsolation() throws {
        let setup = try makeSetup()
        let otherRoot = setup.base.appendingPathComponent("other", isDirectory: true)
        try FileManager.default.createDirectory(at: otherRoot, withIntermediateDirectories: true)
        let hook = makeHook()

        try setup.store.setDecision(.disabled, for: hook, workspaceRoot: setup.root)

        XCTAssertEqual(setup.store.load(forWorkspaceRoot: setup.root).status(for: hook), .disabled)
        XCTAssertEqual(setup.store.load(forWorkspaceRoot: otherRoot).status(for: hook), .reviewRequired)
        XCTAssertNotEqual(
            setup.store.fileURL(forWorkspaceRoot: setup.root),
            setup.store.fileURL(forWorkspaceRoot: otherRoot)
        )
    }

    func testWorkspaceSpellingsShareTrustFile() throws {
        let setup = try makeSetup()
        let hook = makeHook()
        try setup.store.setDecision(.trusted, for: hook, workspaceRoot: setup.root)

        let respelled = setup.root.appendingPathComponent("sub/..")

        XCTAssertEqual(
            setup.store.fileURL(forWorkspaceRoot: respelled),
            setup.store.fileURL(forWorkspaceRoot: setup.root)
        )
        XCTAssertEqual(setup.store.load(forWorkspaceRoot: respelled).status(for: hook), .trusted)
    }

    func testCorruptAndUnsupportedVersionFilesFailClosedAndAreNotOverwritten() throws {
        for payload in [Data("{broken".utf8), Data(#"{"version":99,"records":[]}"#.utf8)] {
            let setup = try makeSetup()
            let fileURL = setup.store.fileURL(forWorkspaceRoot: setup.root)
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try payload.write(to: fileURL)

            let loaded = setup.store.load(forWorkspaceRoot: setup.root)

            XCTAssertTrue(loaded.degraded)
            XCTAssertEqual(loaded.status(for: makeHook()), .reviewRequired)
            XCTAssertThrowsError(
                try setup.store.setDecision(.trusted, for: makeHook(), workspaceRoot: setup.root)
            ) { error in
                XCTAssertEqual(error as? ProjectHookTrustStoreError, .degradedFile)
            }
            XCTAssertEqual(try Data(contentsOf: fileURL), payload)
        }
    }

    func testInvalidAndDuplicateRecordsAreNormalizedAndBounded() throws {
        let setup = try makeSetup()
        let start = Date(timeIntervalSince1970: 1_000)
        let validHash = String(repeating: "a", count: 64)
        let records = (0..<(ProjectHookTrustFileStore.maxRecords + 8)).map { index in
            ProjectHookTrustRecord(
                hookID: "hook-\(index)",
                definitionHash: validHash,
                decision: .trusted,
                updatedAt: start.addingTimeInterval(TimeInterval(index))
            )
        } + [
            ProjectHookTrustRecord(
                hookID: "hook-20",
                definitionHash: validHash,
                decision: .disabled,
                updatedAt: start.addingTimeInterval(10_000)
            ),
            ProjectHookTrustRecord(hookID: "invalid", definitionHash: "short", decision: .trusted)
        ]

        try setup.store.save(records, forWorkspaceRoot: setup.root)
        let loaded = setup.store.load(forWorkspaceRoot: setup.root)

        XCTAssertEqual(loaded.records.count, ProjectHookTrustFileStore.maxRecords)
        XCTAssertEqual(loaded.records.first { $0.hookID == "hook-20" }?.decision, .disabled)
        XCTAssertFalse(loaded.records.contains { $0.hookID == "invalid" })
    }

    private func makeSetup() throws -> (base: URL, root: URL, store: ProjectHookTrustFileStore) {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("ProjectHookTrustStoreTests-\(UUID().uuidString)", isDirectory: true)
        let root = base.appendingPathComponent("project", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: base) }
        return (
            base,
            root,
            ProjectHookTrustFileStore(directory: base.appendingPathComponent("trust", isDirectory: true))
        )
    }

    private func makeHook(hash: String = String(repeating: "a", count: 64)) -> ProjectPluginHook {
        ProjectPluginHook(
            id: "plugin_hook:demo.userpromptsubmit.0.0",
            pluginID: "plugin:demo",
            pluginName: "Demo",
            event: "UserPromptSubmit",
            handlerType: "command",
            command: "printf ready",
            relativePath: ".quillcode/plugins/demo/hooks/hooks.json#UserPromptSubmit/0/0",
            definitionHash: hash,
            supportStatus: .supported
        )
    }
}
