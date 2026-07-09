import XCTest
import QuillCodeCore
@testable import QuillCodeApp

final class WorkspaceSidebarRowActionPlannerTests: XCTestCase {
    func testThreadRenameUsesSidebarItemTitle() {
        let thread = ChatThread(title: "Polish UI")
        let planner = makePlanner(thread: thread)

        XCTAssertEqual(
            planner.action(for: SidebarItemActionSurface(kind: .rename, threadID: thread.id)),
            .renameThread(threadID: thread.id, title: "Polish UI")
        )
    }

    func testThreadRenameReturnsNilWhenThreadIsMissingFromSurface() {
        let planner = makePlanner()

        XCTAssertNil(planner.action(for: SidebarItemActionSurface(kind: .rename, threadID: UUID())))
    }

    func testThreadMutationsDoNotNeedSidebarLookup() {
        let threadID = UUID()
        let expectations: [(SidebarItemActionKind, WorkspaceThreadRowMutation)] = [
            (.duplicate, .duplicate(threadID)),
            (.pin, .togglePin(threadID)),
            (.unpin, .togglePin(threadID)),
            (.archive, .archive(threadID)),
            (.unarchive, .unarchive(threadID)),
            (.delete, .delete(threadID))
        ]

        for (kind, mutation) in expectations {
            let action = SidebarItemActionSurface(kind: kind, threadID: threadID)
            XCTAssertEqual(WorkspaceSidebarRowActionPlanner.threadMutation(for: action), mutation)
            XCTAssertEqual(makePlanner().action(for: action), .mutateThread(mutation))
        }
    }

    func testProjectRenameUsesProjectItemName() {
        let project = ProjectRef(name: "QuillCode", path: "/repo")
        let planner = makePlanner(project: project)

        XCTAssertEqual(
            planner.action(for: ProjectItemActionSurface(kind: .rename, projectID: project.id)),
            .renameProject(projectID: project.id, name: "QuillCode")
        )
    }

    func testProjectRenameReturnsNilWhenProjectIsMissingFromSurface() {
        let planner = makePlanner()

        XCTAssertNil(planner.action(for: ProjectItemActionSurface(kind: .rename, projectID: UUID())))
    }

    func testProjectMutationsDoNotNeedProjectLookup() {
        let projectID = UUID()
        let expectations: [(ProjectItemActionKind, WorkspaceProjectRowMutation)] = [
            (.newChat, .newChat(projectID)),
            (.refreshContext, .refreshContext(projectID)),
            (.moveToTop, .moveToTop(projectID)),
            (.moveUp, .moveUp(projectID)),
            (.moveDown, .moveDown(projectID)),
            (.remove, .remove(projectID))
        ]

        for (kind, mutation) in expectations {
            let action = ProjectItemActionSurface(kind: kind, projectID: projectID)
            XCTAssertEqual(WorkspaceSidebarRowActionPlanner.projectMutation(for: action), mutation)
            XCTAssertEqual(makePlanner().action(for: action), .mutateProject(mutation))
        }
    }

    @MainActor
    func testExecutorAppliesThreadMutationsThroughWorkspaceModel() {
        let thread = ChatThread(title: "Original")
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(threads: [thread], selectedThreadID: thread.id))

        XCTAssertTrue(WorkspaceSidebarRowMutationExecutor.execute(.duplicate(thread.id), model: model))
        XCTAssertEqual(model.root.threads.count, 2)

        XCTAssertEqual(model.selectedThread?.title, "Copy: Original")
    }

    @MainActor
    func testExecutorAppliesProjectMutationsThroughWorkspaceModel() {
        let olderProject = ProjectRef(
            name: "QuillCode",
            path: "/repo",
            lastOpenedAt: Date(timeIntervalSince1970: 10)
        )
        let newerProject = ProjectRef(
            name: "Other",
            path: "/other",
            lastOpenedAt: Date(timeIntervalSince1970: 20)
        )
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            projects: [olderProject, newerProject],
            selectedProjectID: olderProject.id
        ))

        XCTAssertTrue(WorkspaceSidebarRowMutationExecutor.execute(.newChat(olderProject.id), model: model))
        XCTAssertEqual(model.root.selectedProjectID, olderProject.id)
        XCTAssertEqual(model.root.threads.first?.projectID, olderProject.id)

        XCTAssertTrue(WorkspaceSidebarRowMutationExecutor.execute(.moveToTop(olderProject.id), model: model))
        XCTAssertEqual(model.surface().projects.items.map(\.id), [olderProject.id, newerProject.id])

        XCTAssertTrue(WorkspaceSidebarRowMutationExecutor.execute(.moveDown(olderProject.id), model: model))
        XCTAssertEqual(model.surface().projects.items.map(\.id), [newerProject.id, olderProject.id])

        XCTAssertTrue(WorkspaceSidebarRowMutationExecutor.execute(.moveUp(olderProject.id), model: model))
        XCTAssertEqual(model.surface().projects.items.map(\.id), [olderProject.id, newerProject.id])

        XCTAssertTrue(WorkspaceSidebarRowMutationExecutor.execute(.remove(olderProject.id), model: model))
        XCTAssertEqual(model.root.projects.map(\.id), [newerProject.id])
        XCTAssertNil(model.root.threads.first?.projectID)
    }

    private func makePlanner(
        thread: ChatThread? = nil,
        project: ProjectRef? = nil
    ) -> WorkspaceSidebarRowActionPlanner {
        let sidebarItems = thread.map { [SidebarItemSurface(item: SidebarItem(thread: $0), selectedThreadID: $0.id)] } ?? []
        let projectItems = project.map { [ProjectItemSurface(project: $0, selectedProjectID: $0.id)] } ?? []
        return WorkspaceSidebarRowActionPlanner(
            sidebar: SidebarSurface(items: sidebarItems, selectedThreadID: thread?.id),
            projects: ProjectListSurface(items: projectItems, selectedProjectID: project?.id)
        )
    }
}
