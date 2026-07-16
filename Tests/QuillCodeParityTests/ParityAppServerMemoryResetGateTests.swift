import XCTest

final class ParityAppServerMemoryResetGateTests: QuillCodeParityTestCase {
    func testMemoryResetStaysWiredThroughPersistenceRuntimeTestsSmokeAndDocs() throws {
        let root = Self.packageRoot()
        let resetter = try text(root, "Sources/QuillCodePersistence/MemoryDirectoryResetter.swift")
        let adapter = try text(root, "Sources/QuillCodeCLI/AppServerMemoryReset.swift")
        let session = try text(root, "Sources/QuillCodeCLI/AppServerSession.swift")
        let persistenceTests = try text(
            root,
            "Tests/QuillCodePersistenceTests/MemoryDirectoryResetterTests.swift"
        )
        let protocolTests = try text(
            root,
            "Tests/QuillCodeCLITests/AppServerMemoryResetTests.swift"
        )
        let smoke = try text(root, "scripts/app-server-smoke.sh")
        let parity = try Self.docsText(named: "CODEX_PARITY_MATRIX.md")
        let decisions = try Self.docsText(named: "DECISIONS.md")
        let research = try Self.docsText(named: "CODEX_RESEARCH.md")

        Self.assertSource(resetter, containsAll: [
            "MemoryDirectoryResetter",
            "isSymbolicLinkKey",
            "PrivateDirectory.ensureExists"
        ])
        Self.assertSource(adapter, containsAll: [
            "func resetMemory",
            "paths.memoriesDirectory"
        ])
        Self.assertSource(session, contains: "case \"memory/reset\"")
        Self.assertSource(persistenceTests, containsAll: [
            "testClearRemovesNestedAndHiddenContentWhilePreservingRoot",
            "testClearRemovesChildSymlinkWithoutFollowingIt",
            "testClearCreatesMissingPrivateDirectoryAndIsIdempotent",
            "testClearRejectsSymlinkAndRegularFileRoots"
        ])
        Self.assertSource(protocolTests, containsAll: [
            "testResetClearsOnlyGlobalMemoryAndAcceptsOmittedParams",
            "testResetRejectsSymlinkRootWithoutDeletingItsTarget"
        ])
        Self.assertSource(smoke, containsAll: [
            "memory/reset",
            "global_memory_root",
            "project_memory"
        ])
        Self.assertSource(parity, contains: "App-server global memory reset")
        Self.assertSource(
            decisions,
            contains: "Global memory reset preserves project-owned memory"
        )
        Self.assertSource(research, containsAll: ["memory/reset", "app-managed memory"])
    }

    private func text(_ root: URL, _ path: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }
}
