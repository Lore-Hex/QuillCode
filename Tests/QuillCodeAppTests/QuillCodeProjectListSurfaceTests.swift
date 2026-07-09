import XCTest
import QuillCodeCore
@testable import QuillCodeApp

final class QuillCodeProjectListSurfaceTests: XCTestCase {
    func testProjectItemSurfaceBuildsRemoteStateAndDefaultActions() {
        let projectID = UUID()
        let connection = ProjectConnection.ssh(
            path: "/srv/quill",
            host: "feather.local",
            user: "quill",
            port: 22
        )
        let project = ProjectRef(id: projectID, name: "Feather", path: connection.path, connection: connection)
        let item = ProjectItemSurface(project: project, selectedProjectID: projectID)

        XCTAssertEqual(item.id, projectID)
        XCTAssertEqual(item.name, "Feather")
        XCTAssertEqual(item.path, "ssh://quill@feather.local:22/srv/quill")
        XCTAssertEqual(item.connectionKindLabel, "SSH Remote")
        XCTAssertTrue(item.isRemote)
        XCTAssertTrue(item.isSelected)
        XCTAssertEqual(item.actions.map(\.kind), [.newChat, .refreshContext, .moveToTop, .moveUp, .moveDown, .rename, .remove])
        XCTAssertEqual(
            item.actions.map(\.kind.title),
            ["New chat", "Refresh context", "Move to top", "Move up", "Move down", "Rename", "Remove from list"]
        )
        XCTAssertEqual(item.actions.first?.id, "\(projectID.uuidString)-newChat")
    }

    func testProjectItemSurfaceDisablesUnavailableMoveActions() {
        let project = ProjectRef(name: "QuillCode", path: "/repo")

        let item = ProjectItemSurface(
            project: project,
            selectedProjectID: nil,
            canMoveToTop: false,
            canMoveUp: false,
            canMoveDown: false
        )

        XCTAssertEqual(item.actions.first { $0.kind == .moveToTop }?.isEnabled, false)
        XCTAssertEqual(item.actions.first { $0.kind == .moveToTop }?.disabledReason, "Already at the top")
        XCTAssertEqual(item.actions.first { $0.kind == .moveUp }?.isEnabled, false)
        XCTAssertEqual(item.actions.first { $0.kind == .moveUp }?.disabledReason, "Already at the top")
        XCTAssertEqual(item.actions.first { $0.kind == .moveDown }?.isEnabled, false)
        XCTAssertEqual(item.actions.first { $0.kind == .moveDown }?.disabledReason, "Already at the bottom")
    }

    func testProjectItemSurfaceDecodesOlderPayloadWithoutRemoteMetadataOrActions() throws {
        let projectID = UUID()
        let json = """
        {
          "id": "\(projectID.uuidString)",
          "name": "QuillCode",
          "path": "/Users/quill/QuillCode",
          "isSelected": false
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let item = try JSONDecoder().decode(ProjectItemSurface.self, from: data)

        XCTAssertEqual(item.connectionKindLabel, "Local")
        XCTAssertFalse(item.isRemote)
        XCTAssertEqual(item.actions.map(\.kind), [.newChat, .refreshContext, .moveToTop, .moveUp, .moveDown, .rename, .remove])
        XCTAssertTrue(item.actions.allSatisfy(\.isEnabled))
    }
}
