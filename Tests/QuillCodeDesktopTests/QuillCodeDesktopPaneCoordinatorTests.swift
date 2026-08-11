import XCTest
@testable import QuillCodeApp
@testable import quill_code_desktop

@MainActor
final class QuillCodeDesktopPaneCoordinatorTests: XCTestCase {
    func testPaneTogglesReprojectOnlyTheirOwnedSurface() {
        for pane in Pane.allCases {
            assertNarrowProjection(for: pane)
        }
    }

    private func assertNarrowProjection(
        for pane: Pane,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let model = QuillCodeWorkspaceModel()
        if pane == .extensions {
            model.showExtensions(focusedOn: .skill)
        }
        var surface = model.surface()
        surface.lastError = "pane projection sentinel"
        surface.changedFilePaths.insert("sentinel/unrelated.txt")
        let baseline = surface
        let coordinator = QuillCodeDesktopPaneCoordinator()

        switch pane {
        case .extensions:
            coordinator.toggleExtensions(on: model, surface: &surface)
        case .memories:
            coordinator.toggleMemories(on: model, surface: &surface)
        case .activity:
            coordinator.toggleActivity(on: model, surface: &surface)
        case .automations:
            coordinator.toggleAutomations(on: model, surface: &surface)
        }

        let authoritative = model.surface()
        var expected = baseline
        switch pane {
        case .extensions:
            expected.extensions = authoritative.extensions
        case .memories:
            expected.memories = authoritative.memories
        case .activity:
            expected.activity = authoritative.activity
        case .automations:
            expected.automations = authoritative.automations
        }

        XCTAssertEqual(surface, expected, "\(pane) changed an unrelated workspace surface", file: file, line: line)
    }
}

private enum Pane: String, CaseIterable {
    case extensions
    case memories
    case activity
    case automations
}
