import XCTest
@testable import QuillCodeApp

final class WorkspaceChromeStateTests: XCTestCase {
    func testLegacyChromeStateDefaultsNewFields() throws {
        let data = Data(#"{"isSidebarVisible":false}"#.utf8)

        let state = try JSONDecoder().decode(WorkspaceChromeState.self, from: data)
        let surface = try JSONDecoder().decode(WorkspaceChromeSurface.self, from: data)

        XCTAssertFalse(state.isSidebarVisible)
        XCTAssertTrue(state.isReviewVisible)
        XCTAssertEqual(state.textScale, .standard)
        XCTAssertFalse(surface.isSidebarVisible)
        XCTAssertTrue(surface.isReviewVisible)
        XCTAssertEqual(surface.textScale, .standard)
    }

    func testTextScaleClampsAtSupportedBounds() {
        XCTAssertEqual(WorkspaceTextScale.small.decreased(), .small)
        XCTAssertEqual(WorkspaceTextScale.standard.increased(), .large)
        XCTAssertEqual(WorkspaceTextScale.extraLarge.increased(), .extraLarge)
    }
}
