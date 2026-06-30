import XCTest

/// Locks the `@`-mention DIRECTORY contract across the three surfaces. The harness derives
/// directory entries a second time (from `mockFiles` ancestors) instead of from a real FS
/// walk, so a future edit that drops the trailing slash on one surface — or stops emitting
/// directories from the index — would silently break parity. These source-substring gates
/// trip first.
final class ParityFileMentionDirectoryGateTests: QuillCodeParityTestCase {
    func testIndexerEmitsDirectoriesUnderASeparateCap() throws {
        let indexer = try Self.toolsSourceText(named: "WorkspaceFileIndexer.swift")
        XCTAssertTrue(
            indexer.contains("case directory"),
            "WorkspaceFileIndexEntry must carry a directory kind so mentions can offer folders."
        )
        XCTAssertTrue(
            indexer.contains("kind: .directory"),
            "The indexer must actually emit directory entries (it historically dropped them)."
        )
        XCTAssertTrue(
            indexer.contains("defaultMaxDirectories"),
            "Directories must ride a separate cap so a directory-heavy tree never starves the file budget."
        )
    }

    func testSwiftCatalogAppendsATrailingSlashForDirectories() throws {
        let catalog = try Self.appSourceText(named: "FileMentionCatalog.swift")
        XCTAssertTrue(
            catalog.contains("entry.kind == .directory ? \"/ \" : \" \""),
            "A directory mention must insert `@path/ ` (slash then space) so the agent reads the directory."
        )
    }

    func testHarnessSynthesizesDirectoriesAndMirrorsTheTrailingSlash() throws {
        let harness = try String(
            contentsOf: Self.packageRoot().appendingPathComponent("E2E/harness/index.html"),
            encoding: .utf8
        )
        XCTAssertTrue(
            harness.contains("entryFor(dirPath, 'directory')"),
            "The harness must synthesize directory entries from file ancestors to mirror the Swift FS walk."
        )
        XCTAssertTrue(
            harness.contains("item.entry.kind === 'directory' ? '/ ' : ' '"),
            "The harness must mirror the Swift trailing-slash directory insert text exactly."
        )
        XCTAssertTrue(
            harness.contains("data-kind="),
            "The harness must expose the entry kind in the DOM so the panel renders the folder affordance."
        )
    }
}
