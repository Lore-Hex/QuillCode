import XCTest
import QuillCodeCore
@testable import QuillCodeApp

final class WorkspaceProjectEngineTests: XCTestCase {
    func testDefaultProjectNamesUseReadablePathComponents() {
        XCTAssertEqual(
            WorkspaceProjectEngine.defaultProjectName(for: URL(fileURLWithPath: "/tmp/QuillCode")),
            "QuillCode"
        )
        XCTAssertEqual(
            WorkspaceProjectEngine.defaultProjectName(for: URL(fileURLWithPath: "/")),
            "/"
        )

        let connection = ProjectConnection.ssh(path: "/srv/quillcode", host: "feather.local", user: "quill")

        XCTAssertEqual(
            WorkspaceProjectEngine.defaultSSHProjectName(for: connection),
            "feather.local · quillcode"
        )
    }

    func testUpsertLocalProjectCreatesThenUpdatesExistingProject() {
        let path = URL(fileURLWithPath: "/tmp/QuillCode")
        let firstMetadata = metadata(instructionTitle: "First", memoryTitle: "One")
        let secondMetadata = metadata(instructionTitle: "Second", memoryTitle: "Two")
        let firstDate = Date(timeIntervalSince1970: 10)
        let secondDate = Date(timeIntervalSince1970: 20)
        var projects: [ProjectRef] = []

        let created = WorkspaceProjectEngine.upsertLocalProject(
            path: path,
            name: nil,
            metadata: firstMetadata,
            projects: &projects,
            now: firstDate
        )
        let updated = WorkspaceProjectEngine.upsertLocalProject(
            path: path,
            name: "Renamed",
            metadata: secondMetadata,
            projects: &projects,
            now: secondDate
        )

        XCTAssertTrue(created.isNewProject)
        XCTAssertFalse(updated.isNewProject)
        XCTAssertEqual(created.projectID, updated.projectID)
        XCTAssertEqual(projects.count, 1)
        XCTAssertEqual(projects[0].name, "Renamed")
        XCTAssertEqual(projects[0].path, path.standardizedFileURL.path)
        XCTAssertEqual(projects[0].lastOpenedAt, secondDate)
        XCTAssertEqual(projects[0].instructions.map(\.title), ["Second"])
        XCTAssertEqual(projects[0].memories.map(\.title), ["Two"])
    }

    func testUpsertLocalProjectPreservesInstructionDiagnosticResolutions() {
        let path = URL(fileURLWithPath: "/tmp/QuillCode")
        var projects = [
            ProjectRef(
                name: "QuillCode",
                path: path.path,
                instructionDiagnosticResolutions: [
                    ProjectInstructionDiagnosticResolution(
                        diagnosticID: "instruction-conflict",
                        updatedAt: Date(timeIntervalSince1970: 10)
                    )
                ]
            )
        ]

        WorkspaceProjectEngine.upsertLocalProject(
            path: path,
            name: nil,
            metadata: metadata(instructionTitle: "Updated", memoryTitle: "Two"),
            projects: &projects,
            now: Date(timeIntervalSince1970: 20)
        )

        XCTAssertEqual(projects.count, 1)
        XCTAssertEqual(projects[0].instructions.map(\.title), ["Updated"])
        XCTAssertEqual(projects[0].dismissedInstructionDiagnosticIDs, ["instruction-conflict"])
    }

    func testApplyMetadataRecordsResolvedInstructionDiagnosticsWhenTheyDisappear() throws {
        let path = URL(fileURLWithPath: "/tmp/QuillCode")
        let conflictingInstructions = conflictingInstructionPair()
        let diagnosticID = try XCTUnwrap(
            ProjectInstructionDiagnosticsBuilder
                .diagnostics(for: conflictingInstructions)
                .first { $0.statusLabel == "conflict" }?
                .id
        )
        var projects = [
            ProjectRef(
                name: "QuillCode",
                path: path.path,
                instructions: conflictingInstructions
            )
        ]
        let resolvedAt = Date(timeIntervalSince1970: 50)

        XCTAssertTrue(WorkspaceProjectEngine.applyMetadata(
            metadata(instructions: nonConflictingInstructions(), memoryTitle: "Updated"),
            to: projects[0].id,
            projects: &projects,
            includeLocalExtensions: true,
            now: resolvedAt
        ))

        XCTAssertEqual(projects[0].resolvedInstructionDiagnosticIDs, [diagnosticID])
        XCTAssertEqual(projects[0].dismissedInstructionDiagnosticIDs, [])
        XCTAssertEqual(projects[0].instructionDiagnosticResolutions.first?.disposition, .resolved)
        XCTAssertEqual(projects[0].instructionDiagnosticResolutions.first?.updatedAt, resolvedAt)

        XCTAssertTrue(WorkspaceProjectEngine.applyMetadata(
            metadata(instructions: conflictingInstructions, memoryTitle: "Updated"),
            to: projects[0].id,
            projects: &projects,
            includeLocalExtensions: true,
            now: Date(timeIntervalSince1970: 60)
        ))
        let visibleItems = WorkspaceActivitySourceSurfaceBuilder.items(
            instructions: projects[0].instructions,
            memories: [],
            dismissedInstructionDiagnosticIDs: projects[0].dismissedInstructionDiagnosticIDs
        )
        XCTAssertTrue(visibleItems.contains { $0.id == diagnosticID })
    }

    func testUpsertSSHProjectValidatesCreatesAndUpdatesByConnection() {
        var projects: [ProjectRef] = []
        let firstDate = Date(timeIntervalSince1970: 10)
        let secondDate = Date(timeIntervalSince1970: 20)

        guard case .failure(let error) = WorkspaceProjectEngine.upsertSSHProject(
            address: "not-a-remote",
            name: nil,
            projects: &projects
        ) else {
            return XCTFail("Expected invalid SSH address to fail")
        }
        XCTAssertEqual(error, .invalidSSHAddress)
        XCTAssertEqual(error.message, WorkspaceProjectEngine.invalidSSHAddressMessage)

        let created = resultValue(WorkspaceProjectEngine.upsertSSHProject(
            address: "quill@feather.local:/srv/quillcode",
            name: nil,
            projects: &projects,
            now: firstDate
        ))
        let updated = resultValue(WorkspaceProjectEngine.upsertSSHProject(
            address: "quill@feather.local:/srv/quillcode",
            name: "Feather",
            projects: &projects,
            now: secondDate
        ))

        XCTAssertTrue(created?.isNewProject == true)
        XCTAssertFalse(updated?.isNewProject == true)
        XCTAssertEqual(created?.projectID, updated?.projectID)
        XCTAssertEqual(projects.count, 1)
        XCTAssertEqual(projects[0].name, "Feather")
        XCTAssertEqual(projects[0].path, "/srv/quillcode")
        XCTAssertEqual(projects[0].connection.host, "feather.local")
        XCTAssertEqual(projects[0].connection.user, "quill")
        XCTAssertEqual(projects[0].lastOpenedAt, secondDate)
    }

    func testSelectionAfterSelectingProjectUsesNewestUnarchivedThread() {
        let project = ProjectRef(name: "One", path: "/tmp/one")
        let otherProject = ProjectRef(name: "Two", path: "/tmp/two")
        let older = ChatThread(
            title: "Older",
            projectID: project.id,
            updatedAt: Date(timeIntervalSince1970: 1)
        )
        let newer = ChatThread(
            title: "Newer",
            projectID: project.id,
            updatedAt: Date(timeIntervalSince1970: 2)
        )
        let archived = ChatThread(
            title: "Archived",
            projectID: project.id,
            isArchived: true,
            updatedAt: Date(timeIntervalSince1970: 3)
        )
        let other = ChatThread(
            title: "Other",
            projectID: otherProject.id,
            updatedAt: Date(timeIntervalSince1970: 4)
        )

        let selection = WorkspaceProjectEngine.selectionAfterSelectingProject(
            project.id,
            projects: [project, otherProject],
            threads: [older, newer, archived, other]
        )

        XCTAssertEqual(selection, WorkspaceProjectSelection(projectID: project.id, threadID: newer.id))
        XCTAssertNil(WorkspaceProjectEngine.selectionAfterSelectingProject(
            UUID(),
            projects: [project],
            threads: [older]
        ))
    }

    func testSelectionAfterRemovingThreadsPrefersSameProjectThenFallsBackToNewestThread() {
        let project = ProjectRef(name: "One", path: "/tmp/one")
        let otherProject = ProjectRef(name: "Two", path: "/tmp/two")
        let removed = ChatThread(
            title: "Removed",
            projectID: project.id,
            updatedAt: Date(timeIntervalSince1970: 5)
        )
        let preferred = ChatThread(
            title: "Preferred",
            projectID: project.id,
            updatedAt: Date(timeIntervalSince1970: 3)
        )
        let newestOther = ChatThread(
            title: "Newest other",
            projectID: otherProject.id,
            updatedAt: Date(timeIntervalSince1970: 4)
        )

        let sameProjectSelection = WorkspaceProjectEngine.selectionAfterRemovingThreads(
            [removed.id],
            preferredProjectID: project.id,
            projects: [project, otherProject],
            threads: [removed, preferred, newestOther]
        )
        let fallbackSelection = WorkspaceProjectEngine.selectionAfterRemovingThreads(
            [removed.id, preferred.id],
            preferredProjectID: project.id,
            projects: [project, otherProject],
            threads: [removed, preferred, newestOther]
        )

        XCTAssertEqual(
            sameProjectSelection,
            WorkspaceProjectSelection(projectID: project.id, threadID: preferred.id)
        )
        XCTAssertEqual(
            fallbackSelection,
            WorkspaceProjectSelection(projectID: otherProject.id, threadID: newestOther.id)
        )
    }

    func testRenameProjectTrimsNameAndRejectsUnknownOrBlankNames() {
        let project = ProjectRef(name: "Old", path: "/tmp/old", lastOpenedAt: Date(timeIntervalSince1970: 1))
        let renamedAt = Date(timeIntervalSince1970: 99)
        var projects = [project]

        XCTAssertFalse(WorkspaceProjectEngine.renameProject(UUID(), to: "New", projects: &projects, now: renamedAt))
        XCTAssertFalse(WorkspaceProjectEngine.renameProject(project.id, to: "   ", projects: &projects, now: renamedAt))
        XCTAssertTrue(WorkspaceProjectEngine.renameProject(project.id, to: "  New Name  ", projects: &projects, now: renamedAt))
        XCTAssertEqual(projects[0].name, "New Name")
        XCTAssertEqual(projects[0].lastOpenedAt, renamedAt)
    }

    func testRemoveProjectClearsThreadOwnershipAndSanitizesSelection() {
        let removedProject = ProjectRef(name: "Remove", path: "/tmp/remove")
        let keptProject = ProjectRef(name: "Keep", path: "/tmp/keep")
        let affectedThread = ChatThread(title: "Affected", projectID: removedProject.id)
        let keptThread = ChatThread(title: "Kept", projectID: keptProject.id)
        var projects = [removedProject, keptProject]
        var threads = [affectedThread, keptThread]

        let result = WorkspaceProjectEngine.removeProject(
            removedProject.id,
            projects: &projects,
            threads: &threads,
            selectedProjectID: removedProject.id
        )

        XCTAssertEqual(result?.selectedProjectID, nil)
        XCTAssertEqual(result?.changedThreadIDs, [affectedThread.id])
        XCTAssertEqual(projects.map(\.id), [keptProject.id])
        XCTAssertNil(threads.first { $0.id == affectedThread.id }?.projectID)
        XCTAssertEqual(threads.first { $0.id == keptThread.id }?.projectID, keptProject.id)
    }

    func testTouchAndMetadataApplicationAreScopedToKnownProjects() {
        let project = ProjectRef(name: "QuillCode", path: "/tmp/QuillCode")
        let firstDate = project.lastOpenedAt
        let nextDate = Date(timeIntervalSince1970: 42)
        let metadata = metadata(instructionTitle: "Updated", memoryTitle: "Remembered")
        var projects = [project]

        XCTAssertFalse(WorkspaceProjectEngine.touchProject(UUID(), projects: &projects, now: nextDate))
        XCTAssertTrue(WorkspaceProjectEngine.touchProject(project.id, projects: &projects, now: nextDate))
        XCTAssertNotEqual(projects[0].lastOpenedAt, firstDate)
        XCTAssertEqual(projects[0].lastOpenedAt, nextDate)

        XCTAssertFalse(WorkspaceProjectEngine.applyMetadata(
            metadata,
            to: UUID(),
            projects: &projects,
            includeLocalExtensions: true
        ))
        XCTAssertTrue(WorkspaceProjectEngine.applyMetadata(
            metadata,
            to: project.id,
            projects: &projects,
            includeLocalExtensions: true
        ))
        XCTAssertEqual(projects[0].instructions.map(\.title), ["Updated"])
        XCTAssertEqual(projects[0].localActions.map(\.title), ["Run bootstrap"])
        XCTAssertEqual(projects[0].extensionManifests.map(\.name), ["Demo MCP"])
        XCTAssertEqual(projects[0].memories.map(\.title), ["Remembered"])

        XCTAssertTrue(WorkspaceProjectEngine.applyMetadata(
            metadata,
            to: project.id,
            projects: &projects,
            includeLocalExtensions: false
        ))
        XCTAssertEqual(projects[0].instructions.map(\.title), ["Updated"])
        XCTAssertTrue(projects[0].localActions.isEmpty)
        XCTAssertTrue(projects[0].extensionManifests.isEmpty)
        XCTAssertEqual(projects[0].memories.map(\.title), ["Remembered"])
    }

    func testMoveProjectRewritesRecencyRanksForAdjacentOrdering() {
        let top = ProjectRef(name: "Top", path: "/tmp/top", lastOpenedAt: Date(timeIntervalSince1970: 30))
        let middle = ProjectRef(name: "Middle", path: "/tmp/middle", lastOpenedAt: Date(timeIntervalSince1970: 20))
        let bottom = ProjectRef(name: "Bottom", path: "/tmp/bottom", lastOpenedAt: Date(timeIntervalSince1970: 10))
        let movedAt = Date(timeIntervalSince1970: 100)
        var projects = [bottom, top, middle]

        XCTAssertTrue(WorkspaceProjectEngine.moveProject(
            middle.id,
            direction: .up,
            projects: &projects,
            now: movedAt
        ))
        XCTAssertEqual(sortedProjectNames(projects), ["Middle", "Top", "Bottom"])

        XCTAssertTrue(WorkspaceProjectEngine.moveProject(
            middle.id,
            direction: .down,
            projects: &projects,
            now: movedAt.addingTimeInterval(10)
        ))
        XCTAssertEqual(sortedProjectNames(projects), ["Top", "Middle", "Bottom"])
    }

    func testMoveProjectRejectsUnknownAndBoundaryMoves() {
        let top = ProjectRef(name: "Top", path: "/tmp/top", lastOpenedAt: Date(timeIntervalSince1970: 30))
        let bottom = ProjectRef(name: "Bottom", path: "/tmp/bottom", lastOpenedAt: Date(timeIntervalSince1970: 10))
        var projects = [top, bottom]

        XCTAssertFalse(WorkspaceProjectEngine.moveProject(UUID(), direction: .up, projects: &projects))
        XCTAssertFalse(WorkspaceProjectEngine.moveProject(top.id, direction: .up, projects: &projects))
        XCTAssertFalse(WorkspaceProjectEngine.moveProject(bottom.id, direction: .down, projects: &projects))
        XCTAssertEqual(sortedProjectNames(projects), ["Top", "Bottom"])
    }

    private func resultValue(
        _ result: Result<WorkspaceProjectUpsertResult, WorkspaceProjectError>,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> WorkspaceProjectUpsertResult? {
        switch result {
        case .success(let value):
            return value
        case .failure(let error):
            XCTFail("Expected success, got \(error.message)", file: file, line: line)
            return nil
        }
    }

    private func metadata(
        instructionTitle: String,
        memoryTitle: String
    ) -> WorkspaceProjectMetadata {
        metadata(
            instructions: [
                ProjectInstruction(
                    path: "AGENTS.md",
                    title: instructionTitle,
                    content: "Prefer focused tests.",
                    byteCount: 21
                )
            ],
            memoryTitle: memoryTitle
        )
    }

    private func metadata(
        instructions: [ProjectInstruction],
        memoryTitle: String
    ) -> WorkspaceProjectMetadata {
        WorkspaceProjectMetadata(
            instructions: instructions,
            localActions: [
                LocalEnvironmentAction(
                    id: "bootstrap",
                    title: "Run bootstrap",
                    relativePath: ".quillcode/actions/bootstrap.sh",
                    command: "./.quillcode/actions/bootstrap.sh"
                )
            ],
            runHooks: [],
            extensionManifests: [
                ProjectExtensionManifest(
                    id: "demo-mcp",
                    kind: .mcpServer,
                    name: "Demo MCP",
                    relativePath: ".quillcode/mcp/demo.json"
                )
            ],
            memories: [
                MemoryNote(
                    id: "memory",
                    scope: .project,
                    title: memoryTitle,
                    content: "Use small PRs.",
                    relativePath: ".quillcode/memories/team.md",
                    byteCount: 14
                )
            ]
        )
    }

    private func sortedProjectNames(_ projects: [ProjectRef]) -> [String] {
        projects.sorted { $0.lastOpenedAt > $1.lastOpenedAt }.map(\.name)
    }

    private func conflictingInstructionPair() -> [ProjectInstruction] {
        let rootContent = "Always run tests before finishing."
        let featureContent = "Do not run tests for feature changes."
        return [
            ProjectInstruction(
                path: "AGENTS.md",
                title: "Root instructions",
                content: rootContent,
                byteCount: rootContent.utf8.count
            ),
            ProjectInstruction(
                path: "Sources/Feature/AGENTS.md",
                title: "Feature instructions",
                content: featureContent,
                byteCount: featureContent.utf8.count
            )
        ]
    }

    private func nonConflictingInstructions() -> [ProjectInstruction] {
        let rootContent = "Always run tests before finishing."
        let featureContent = "Always run focused tests before finishing."
        return [
            ProjectInstruction(
                path: "AGENTS.md",
                title: "Root instructions",
                content: rootContent,
                byteCount: rootContent.utf8.count
            ),
            ProjectInstruction(
                path: "Sources/Feature/AGENTS.md",
                title: "Feature instructions",
                content: featureContent,
                byteCount: featureContent.utf8.count
            )
        ]
    }
}
