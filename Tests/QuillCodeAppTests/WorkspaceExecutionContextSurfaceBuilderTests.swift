import XCTest
import QuillCodeCore
import QuillCodeTools
@testable import QuillCodeApp

final class WorkspaceExecutionContextSurfaceBuilderTests: XCTestCase {
    func testContextPrefersThreadProjectOverSelectedProject() throws {
        let selected = ProjectRef(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            name: "Selected",
            path: "/selected"
        )
        let threadProject = ProjectRef(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            name: "Thread",
            path: "/thread"
        )
        let builder = WorkspaceExecutionContextSurfaceBuilder(
            selectedProject: selected,
            projects: [selected, threadProject]
        )
        let thread = ChatThread(projectID: threadProject.id)

        let context = try XCTUnwrap(builder.context(for: thread))

        XCTAssertEqual(context.kind, .local)
        XCTAssertEqual(context.detail, "/thread")
    }

    func testContextFallsBackToSelectedProjectWhenThreadHasNoProject() throws {
        let selected = ProjectRef(name: "Selected", path: "/selected")
        let builder = WorkspaceExecutionContextSurfaceBuilder(
            selectedProject: selected,
            projects: [selected]
        )

        let context = try XCTUnwrap(builder.context(for: ChatThread()))

        XCTAssertEqual(context.kind, .local)
        XCTAssertEqual(context.detail, "/selected")
    }

    func testContextIsNilWithoutKnownProject() {
        let missingProjectID = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
        let builder = WorkspaceExecutionContextSurfaceBuilder(
            selectedProject: nil,
            projects: []
        )

        XCTAssertNil(builder.context(for: ChatThread(projectID: missingProjectID)))
    }

    func testEnrichesOnlyProjectExecutionToolCardsWithoutOverwritingExistingContext() {
        let project = ProjectRef(name: "Workspace", path: "/workspace")
        let existingContext = ExecutionContextSurface(
            kind: .sshRemote,
            label: "SSH Remote",
            detail: "existing.example"
        )
        let builder = WorkspaceExecutionContextSurfaceBuilder(
            selectedProject: project,
            projects: [project]
        )
        let cards = [
            ToolCardState(
                id: "shell",
                title: ToolDefinition.shellRun.name,
                subtitle: "Queued",
                status: .queued
            ),
            ToolCardState(
                id: "memory",
                title: ToolDefinition.memoryRemember.name,
                subtitle: "Completed",
                status: .done
            ),
            ToolCardState(
                id: "existing",
                title: ToolDefinition.gitStatus.name,
                subtitle: "Completed",
                status: .done,
                executionContext: existingContext
            )
        ]

        let enriched = builder.enrichToolCards(cards, for: ChatThread())

        XCTAssertEqual(enriched[0].executionContext?.kind, .local)
        XCTAssertEqual(enriched[0].executionContext?.detail, "/workspace")
        XCTAssertNil(enriched[1].executionContext)
        XCTAssertEqual(enriched[2].executionContext, existingContext)
    }

    func testEnrichesTimelineToolCards() {
        let project = ProjectRef(name: "Workspace", path: "/workspace")
        let builder = WorkspaceExecutionContextSurfaceBuilder(
            selectedProject: project,
            projects: [project]
        )
        let shellCard = ToolCardState(
            id: "shell",
            title: ToolDefinition.shellRun.name,
            subtitle: "Queued",
            status: .queued
        )
        let memoryCard = ToolCardState(
            id: "memory",
            title: ToolDefinition.memoryRemember.name,
            subtitle: "Completed",
            status: .done
        )

        let enriched = builder.enrichTimelineItems(
            [.toolCard(shellCard), .toolCard(memoryCard)],
            for: ChatThread()
        )

        XCTAssertEqual(enriched[0].toolCard?.executionContext?.detail, "/workspace")
        XCTAssertNil(enriched[1].toolCard?.executionContext)
    }

    func testProjectExecutionToolSetIncludesWorkspaceToolsAndExcludesNonWorkspaceTools() {
        XCTAssertTrue(WorkspaceExecutionContextSurfaceBuilder.isProjectExecutionTool(ToolDefinition.shellRun.name))
        XCTAssertTrue(WorkspaceExecutionContextSurfaceBuilder.isProjectExecutionTool(ToolDefinition.fileRead.name))
        XCTAssertTrue(WorkspaceExecutionContextSurfaceBuilder.isProjectExecutionTool(ToolDefinition.gitPullRequestMerge.name))
        XCTAssertTrue(WorkspaceExecutionContextSurfaceBuilder.isProjectExecutionTool(ToolDefinition.gitWorktreeCreate.name))
        XCTAssertTrue(WorkspaceExecutionContextSurfaceBuilder.isProjectExecutionTool(ToolDefinition.gitWorktreeOpen.name))

        XCTAssertFalse(WorkspaceExecutionContextSurfaceBuilder.isProjectExecutionTool("Safety Check"))
        XCTAssertFalse(WorkspaceExecutionContextSurfaceBuilder.isProjectExecutionTool(ToolDefinition.memoryRemember.name))
        XCTAssertFalse(WorkspaceExecutionContextSurfaceBuilder.isProjectExecutionTool(ToolDefinition.mcpCall.name))
    }
}
