import XCTest
import QuillCodeCore
@testable import QuillCodeApp

final class QuillCodeProjectListSurfaceTests: XCTestCase {
    func testProjectListSurfaceSummarizesCountAndReorderHint() {
        let first = ProjectItemSurface(project: ProjectRef(name: "QuillCode", path: "/repo"), selectedProjectID: nil)
        let second = ProjectItemSurface(project: ProjectRef(name: "Tools", path: "/tools"), selectedProjectID: nil)

        let empty = ProjectListSurface(items: [], selectedProjectID: nil)
        let single = ProjectListSurface(items: [first], selectedProjectID: nil)
        let multiple = ProjectListSurface(items: [first, second], selectedProjectID: nil)

        XCTAssertEqual(empty.countLabel, "No projects")
        XCTAssertEqual(empty.compactCountLabel, "No projects")
        XCTAssertEqual(empty.connectionSummaryLabel, "No project connections")
        XCTAssertEqual(empty.accessibilitySummary, "Projects, no projects")
        XCTAssertEqual(single.countLabel, "1 project")
        XCTAssertEqual(single.compactCountLabel, "1 project")
        XCTAssertEqual(single.connectionSummaryLabel, "1 local")
        XCTAssertEqual(single.accessibilitySummary, "Projects, 1 project, 1 local. Drag project rows to reorder them.")
        XCTAssertEqual(multiple.countLabel, "2 projects")
        XCTAssertEqual(multiple.compactCountLabel, "2 projects")
        XCTAssertEqual(multiple.connectionSummaryLabel, "2 local")
        XCTAssertEqual(multiple.accessibilitySummary, "Projects, 2 projects, 2 local. Drag project rows to reorder them.")
    }

    func testProjectListSurfaceSummarizesRemoteProjectsAndCurrentSelection() {
        let local = ProjectRef(name: "QuillCode", path: "/repo")
        let remoteID = UUID()
        let remoteConnection = ProjectConnection.ssh(
            path: "/srv/quill",
            host: "feather.local",
            user: "quill",
            port: 22
        )
        let remote = ProjectRef(id: remoteID, name: "Feather", path: remoteConnection.path, connection: remoteConnection)
        let surface = ProjectListSurface(
            items: [
                ProjectItemSurface(project: local, selectedProjectID: remoteID),
                ProjectItemSurface(project: remote, selectedProjectID: remoteID)
            ],
            selectedProjectID: remoteID
        )

        XCTAssertEqual(surface.countLabel, "2 projects")
        XCTAssertEqual(surface.remoteCountLabel, "1 remote")
        XCTAssertEqual(surface.localCountLabel, "1 local")
        XCTAssertEqual(surface.connectionSummaryLabel, "1 local · 1 remote")
        XCTAssertEqual(surface.compactCountLabel, "2 projects · 1 remote")
        XCTAssertEqual(surface.currentProjectLabel, "Current project: Feather")
        XCTAssertEqual(
            surface.accessibilitySummary,
            "Projects, 2 projects, 1 local · 1 remote. Current project: Feather. Drag project rows to reorder them."
        )
    }

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
        XCTAssertEqual(item.selectionLabel, "Current")
        XCTAssertEqual(item.accessibilityLabel, "Current project, Feather, SSH Remote, ssh://quill@feather.local:22/srv/quill")
        XCTAssertEqual(item.actions.map(\.kind), [.newChat, .refreshContext, .moveToTop, .moveUp, .moveDown, .moveToBottom, .rename, .remove])
        XCTAssertEqual(
            item.actions.map(\.kind.title),
            ["New chat", "Refresh context", "Move to top", "Move up", "Move down", "Move to bottom", "Rename", "Remove from list"]
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
            canMoveDown: false,
            canMoveToBottom: false
        )

        XCTAssertEqual(item.actions.first { $0.kind == .moveToTop }?.isEnabled, false)
        XCTAssertEqual(item.actions.first { $0.kind == .moveToTop }?.disabledReason, "Already at the top")
        XCTAssertEqual(item.actions.first { $0.kind == .moveUp }?.isEnabled, false)
        XCTAssertEqual(item.actions.first { $0.kind == .moveUp }?.disabledReason, "Already at the top")
        XCTAssertEqual(item.actions.first { $0.kind == .moveDown }?.isEnabled, false)
        XCTAssertEqual(item.actions.first { $0.kind == .moveDown }?.disabledReason, "Already at the bottom")
        XCTAssertEqual(item.actions.first { $0.kind == .moveToBottom }?.isEnabled, false)
        XCTAssertEqual(item.actions.first { $0.kind == .moveToBottom }?.disabledReason, "Already at the bottom")
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
        XCTAssertNil(item.selectionLabel)
        XCTAssertEqual(item.accessibilityLabel, "Project, QuillCode, Local, /Users/quill/QuillCode")
        XCTAssertEqual(item.actions.map(\.kind), [.newChat, .refreshContext, .moveToTop, .moveUp, .moveDown, .moveToBottom, .rename, .remove])
        XCTAssertTrue(item.actions.allSatisfy(\.isEnabled))
    }
}
