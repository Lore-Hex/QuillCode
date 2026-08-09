import XCTest
import QuillCodeCore
import QuillCodePersistence
@testable import QuillCodeApp

final class WorkspaceRegistryPersistenceTests: XCTestCase {
    func testFailedRegistriesRequireTheirOwnSuccessfulSnapshots() throws {
        let root = try makeQuillCodeTestDirectory()
        let privateDirectoryName = "private-customer-registry"
        let blockingFile = root.appendingPathComponent(privateDirectoryName)
        try Data("not-a-directory".utf8).write(to: blockingFile)
        let registryDirectory = blockingFile.appendingPathComponent("state")
        let projectStore = JSONProjectStore(
            fileURL: registryDirectory.appendingPathComponent("projects.json")
        )
        let automationStore = JSONAutomationStore(
            fileURL: registryDirectory.appendingPathComponent("automations.json")
        )
        let savedSearchStore = JSONSidebarSavedSearchStore(
            fileURL: registryDirectory.appendingPathComponent("saved-searches.json")
        )
        let tracker = WorkspaceRegistryPersistenceIssueTracker()
        let persistence = WorkspaceRegistryPersistence(
            projectStore: projectStore,
            automationStore: automationStore,
            sidebarSavedSearchStore: savedSearchStore,
            issueTracker: tracker
        )
        let projects = [ProjectRef(name: "Confidential project", path: root.path)]
        let automations = [QuillAutomation(
            title: "Confidential monitor",
            detail: "Private instructions",
            kind: .monitor,
            scheduleKind: .event,
            scheduleDescription: "Event"
        )]
        let savedSearches = [SidebarSavedSearch(title: "Confidential search", query: "secret")]

        persistence.saveProjects(projects)
        persistence.saveAutomations(automations)
        persistence.saveSidebarSavedSearches(savedSearches)

        let issue = try XCTUnwrap(tracker.runtimeIssue)
        XCTAssertEqual(tracker.failedKindCount, 3)
        XCTAssertEqual(issue.title, "Some workspace changes are not saved")
        XCTAssertEqual(
            issue.diagnostics.first { $0.label == "Affected data" }?.value,
            "Projects, Automations, Saved searches"
        )
        let visibleText = ([issue.title, issue.message] + issue.diagnostics.flatMap {
            [$0.label, $0.value]
        }).joined(separator: " ")
        XCTAssertFalse(visibleText.contains(privateDirectoryName))
        XCTAssertFalse(visibleText.contains(projects[0].name))
        XCTAssertFalse(visibleText.contains(automations[0].title))
        XCTAssertFalse(visibleText.contains(savedSearches[0].title))

        try FileManager.default.removeItem(at: blockingFile)
        persistence.saveProjects(projects)

        XCTAssertEqual(tracker.failedKindCount, 2)
        XCTAssertEqual(tracker.runtimeIssue?.title, "Some workspace changes are not saved")
        XCTAssertEqual(try projectStore.load().map(\.name), [projects[0].name])

        persistence.saveAutomations(automations)

        XCTAssertEqual(tracker.failedKindCount, 1)
        XCTAssertEqual(tracker.runtimeIssue?.title, "A workspace change is not saved")
        XCTAssertEqual(try automationStore.load().map(\.title), [automations[0].title])

        persistence.saveSidebarSavedSearches(savedSearches)

        XCTAssertEqual(tracker.failedKindCount, 0)
        XCTAssertNil(tracker.runtimeIssue)
        XCTAssertEqual(try savedSearchStore.load(), savedSearches)
    }

    func testThrowingProjectSaveRecordsFailureBeforeRethrowing() throws {
        let root = try makeQuillCodeTestDirectory()
        let blockingFile = root.appendingPathComponent("blocked")
        try Data().write(to: blockingFile)
        let tracker = WorkspaceRegistryPersistenceIssueTracker()
        let persistence = WorkspaceRegistryPersistence(
            projectStore: JSONProjectStore(
                fileURL: blockingFile.appendingPathComponent("projects.json")
            ),
            automationStore: nil,
            sidebarSavedSearchStore: nil,
            issueTracker: tracker
        )

        XCTAssertThrowsError(try persistence.saveProjectsOrThrow([
            ProjectRef(name: "Important", path: root.path)
        ]))
        XCTAssertEqual(tracker.failedKindCount, 1)
        XCTAssertEqual(tracker.runtimeIssue?.title, "A workspace change is not saved")
    }

    func testMissingStoresAreNoopsForStartupRecoveryMode() throws {
        let tracker = WorkspaceRegistryPersistenceIssueTracker()
        let persistence = WorkspaceRegistryPersistence(
            projectStore: nil,
            automationStore: nil,
            sidebarSavedSearchStore: nil,
            issueTracker: tracker
        )

        persistence.saveProjects([])
        try persistence.saveProjectsOrThrow([])
        persistence.saveAutomations([])
        persistence.saveSidebarSavedSearches([])

        XCTAssertEqual(tracker.failedKindCount, 0)
        XCTAssertNil(tracker.runtimeIssue)
    }
}
