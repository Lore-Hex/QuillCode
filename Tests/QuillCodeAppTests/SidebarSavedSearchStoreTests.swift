import XCTest
@testable import QuillCodeApp

final class SidebarSavedSearchStoreTests: XCTestCase {
    func testLoadNormalizesInvalidDuplicateAndWhitespaceRecords() throws {
        let directory = try makeQuillCodeTestDirectory()
        let fileURL = directory.appendingPathComponent("sidebar-saved-searches.json")
        let id = try XCTUnwrap(UUID(uuidString: "55555555-5555-5555-5555-555555555555"))
        let records = [
            SidebarSavedSearch(id: id, title: "  Failures  ", query: " failed error "),
            SidebarSavedSearch(id: id, title: "Duplicate", query: "duplicate"),
            SidebarSavedSearch(title: "", query: "hidden"),
            SidebarSavedSearch(title: "Blank", query: " ")
        ]
        let data = try JSONEncoder().encode(records)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: fileURL)

        XCTAssertEqual(
            try JSONSidebarSavedSearchStore(fileURL: fileURL).load(),
            [SidebarSavedSearch(id: id, title: "Failures", query: "failed error")]
        )
    }

    func testSaveCreatesDirectoryAndWritesStableJSON() throws {
        let directory = try makeQuillCodeTestDirectory()
        let fileURL = directory
            .appendingPathComponent("nested")
            .appendingPathComponent("sidebar-saved-searches.json")
        let store = JSONSidebarSavedSearchStore(fileURL: fileURL)
        let savedSearch = SidebarSavedSearch(title: "OpenClaw", query: "openclaw")

        try store.save([SidebarSavedSearch(title: "", query: "hidden"), savedSearch])

        XCTAssertEqual(try store.load(), [savedSearch])
    }
}
