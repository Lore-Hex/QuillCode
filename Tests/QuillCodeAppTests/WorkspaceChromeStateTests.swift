import XCTest
@testable import QuillCodeApp

final class WorkspaceChromeStateTests: XCTestCase {
    func testLegacyChromeStateDefaultsNewFields() throws {
        let data = Data(#"{"isSidebarVisible":false}"#.utf8)

        let state = try JSONDecoder().decode(WorkspaceChromeState.self, from: data)
        let surface = try JSONDecoder().decode(WorkspaceChromeSurface.self, from: data)

        XCTAssertFalse(state.isSidebarVisible)
        XCTAssertTrue(state.isReviewVisible)
        XCTAssertEqual(state.reviewPresentation, .automatic)
        XCTAssertEqual(state.textScale, .standard)
        XCTAssertFalse(surface.isSidebarVisible)
        XCTAssertTrue(surface.isReviewVisible)
        XCTAssertEqual(surface.textScale, .standard)
    }

    func testReviewPresentationResolvesAutomaticVisibleAndHiddenPolicies() {
        XCTAssertFalse(WorkspaceReviewPresentation.automatic.resolves(hasContent: false))
        XCTAssertTrue(WorkspaceReviewPresentation.automatic.resolves(hasContent: true))
        XCTAssertTrue(WorkspaceReviewPresentation.visible.resolves(hasContent: false))
        XCTAssertFalse(WorkspaceReviewPresentation.hidden.resolves(hasContent: true))
    }

    func testLegacyHiddenReviewStateDecodesAsExplicitlyHidden() throws {
        let data = Data(#"{"isReviewVisible":false}"#.utf8)

        let state = try JSONDecoder().decode(WorkspaceChromeState.self, from: data)

        XCTAssertEqual(state.reviewPresentation, .hidden)
        XCTAssertFalse(state.isReviewVisible)
    }

    func testChromeSurfaceResolvesAutomaticReviewAgainstContent() {
        let state = WorkspaceChromeState(reviewPresentation: .automatic)

        XCTAssertFalse(WorkspaceChromeSurface(state: state, reviewHasContent: false).isReviewVisible)
        XCTAssertTrue(WorkspaceChromeSurface(state: state, reviewHasContent: true).isReviewVisible)
    }

    func testReviewPresentationRoundTripsThroughChromeStatePersistence() throws {
        let state = WorkspaceChromeState(
            isSidebarVisible: false,
            reviewPresentation: .visible,
            textScale: .large
        )

        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(WorkspaceChromeState.self, from: data)

        XCTAssertEqual(decoded, state)
    }

    func testTextScaleClampsAtSupportedBounds() {
        XCTAssertEqual(WorkspaceTextScale.small.decreased(), .small)
        XCTAssertEqual(WorkspaceTextScale.standard.increased(), .large)
        XCTAssertEqual(WorkspaceTextScale.extraLarge.increased(), .extraLarge)
    }
}
