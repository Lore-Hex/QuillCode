import XCTest
import QuillCodeCore
import QuillCodePersistence
@testable import QuillCodeApp

@MainActor
final class WorkspaceBootstrapProjectMigrationTests: XCTestCase {
    func testBootstrapRemovesAndPersistsUnusedLegacyFilesystemRootProject() throws {
        let home = try makeQuillCodeTestDirectory()
        let paths = QuillCodePaths(home: home)
        try paths.ensure()
        let store = JSONProjectStore(fileURL: paths.projectsFile)
        try store.save([ProjectRef(name: "/", path: "/")])

        let model = try QuillCodeWorkspaceBootstrap(paths: paths).makeModel()

        XCTAssertTrue(model.root.projects.isEmpty)
        XCTAssertTrue(try store.load().isEmpty)
        XCTAssertTrue(WorkspaceBootstrapProjectMigration.isComplete(in: paths.home))
    }

    func testCompletedMigrationPreservesAProjectThatLaterTargetsFilesystemRoot() throws {
        let home = try makeQuillCodeTestDirectory()
        let paths = QuillCodePaths(home: home)
        try paths.ensure()
        let store = JSONProjectStore(fileURL: paths.projectsFile)

        _ = try QuillCodeWorkspaceBootstrap(paths: paths).makeModel()
        let intentionalRootProject = ProjectRef(name: "/", path: "/")
        try store.save([intentionalRootProject])

        let relaunchedModel = try QuillCodeWorkspaceBootstrap(paths: paths).makeModel()

        XCTAssertEqual(relaunchedModel.root.projects.map(\.id), [intentionalRootProject.id])
        XCTAssertEqual(relaunchedModel.root.projects.first?.path, "/")
        XCTAssertEqual(try store.load().map(\.id), [intentionalRootProject.id])
    }

    func testMigrationPreservesRootProjectWithAChat() {
        let project = ProjectRef(name: "/", path: "/")
        let thread = ChatThread(title: "Existing work", projectID: project.id)

        let projects = WorkspaceBootstrapProjectMigration.removingUnusedLegacyRootProject(
            from: [project],
            threads: [thread],
            hasThreadLoadIssues: false
        )

        XCTAssertEqual(projects, [project])
    }

    func testMigrationPreservesRootProjectWhenThreadRecoveryIsIncomplete() {
        let project = ProjectRef(name: "/", path: "/")

        let projects = WorkspaceBootstrapProjectMigration.removingUnusedLegacyRootProject(
            from: [project],
            threads: [],
            hasThreadLoadIssues: true
        )

        XCTAssertEqual(projects, [project])
    }

    func testMigrationPreservesExplicitlyNamedRootProject() {
        let project = ProjectRef(name: "Entire system", path: "/")

        let projects = WorkspaceBootstrapProjectMigration.removingUnusedLegacyRootProject(
            from: [project],
            threads: [],
            hasThreadLoadIssues: false
        )

        XCTAssertEqual(projects, [project])
    }
}
