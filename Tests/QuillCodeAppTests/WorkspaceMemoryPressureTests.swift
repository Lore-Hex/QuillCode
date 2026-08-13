import XCTest
import QuillCodeCore
import QuillCodePersistence
import QuillCodeTools
@testable import QuillCodeApp

@MainActor
final class WorkspaceMemoryPressureTests: XCTestCase {
    func testWarningReleasesInactivePayloadsAndSurfacesWithoutDroppingActiveContext() throws {
        let directory = try makeQuillCodeTestDirectory()
        let store = JSONThreadStore(directory: directory)
        let firstProject = ProjectRef(name: "First", path: "/tmp/quill-cowork-memory-first")
        let selectedProject = ProjectRef(name: "Selected", path: "/tmp/quill-cowork-memory-selected")
        var threads: [ChatThread] = []
        for index in 0..<8 {
            let thread = ChatThread(
                title: "Chat \(index)",
                messages: [ChatMessage(
                    role: .user,
                    content: "payload \(index) " + String(repeating: "x", count: 4_096)
                )],
                updatedAt: Date(timeIntervalSince1970: TimeInterval(index))
            )
            try store.save(thread)
            threads.append(thread)
        }

        let runningID = threads[0].id
        let persistenceFailedID = threads[1].id
        let selectedID = threads[7].id
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(
                projects: [firstProject, selectedProject],
                selectedProjectID: selectedProject.id,
                threads: threads,
                selectedThreadID: selectedID
            ),
            agentRuns: WorkspaceAgentRunRegistry(statusesByThreadID: [runningID: "Running"]),
            threadStore: store
        )
        model.threadPersistenceIssueTracker.recordFailure(for: persistenceFailedID)
        model.fileMentionIndex = WorkspaceFileIndex(entries: [
            WorkspaceFileIndexEntry(path: "Sources/App.swift", name: "App.swift", directory: "Sources")
        ])
        model.worktreeEnvironmentSurfacesByProjectID = [
            firstProject.id: WorkspaceWorktreeEnvironmentSurface(),
            selectedProject.id: WorkspaceWorktreeEnvironmentSurface()
        ]

        let result = model.releaseReconstructibleMemory(for: .warning)

        XCTAssertEqual(result.releasedThreadPayloadCount, 5)
        XCTAssertEqual(result.releasedFileMentionEntryCount, 0)
        XCTAssertEqual(result.releasedInactiveProjectSurfaceCount, 1)
        XCTAssertFalse(result.shouldReleaseLanguageServices)
        XCTAssertEqual(model.fileMentionIndex.entries.map(\.path), ["Sources/App.swift"])
        XCTAssertEqual(Set(model.worktreeEnvironmentSurfacesByProjectID.keys), Set([selectedProject.id]))
        XCTAssertTrue(try payloadIsLoaded(runningID, in: model))
        XCTAssertTrue(try payloadIsLoaded(persistenceFailedID, in: model))
        XCTAssertTrue(try payloadIsLoaded(selectedID, in: model))
        XCTAssertEqual(model.root.threads.filter { $0.payloadResidency.isLoaded }.count, 3)
    }

    func testCriticalReleasesFileIndexAndAllowsIdleLanguageServiceShutdown() throws {
        let selected = ChatThread(
            title: "Selected",
            messages: [ChatMessage(role: .user, content: "Keep me")]
        )
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(threads: [selected], selectedThreadID: selected.id)
        )
        model.fileMentionIndex = WorkspaceFileIndex(entries: [
            WorkspaceFileIndexEntry(path: "README.md", name: "README.md", directory: ""),
            WorkspaceFileIndexEntry(path: "Sources", name: "Sources", directory: "", kind: .directory)
        ])

        let result = model.releaseReconstructibleMemory(for: .critical)

        XCTAssertEqual(result.releasedFileMentionEntryCount, 2)
        XCTAssertTrue(result.shouldReleaseLanguageServices)
        XCTAssertTrue(model.fileMentionIndex.isEmpty)
        XCTAssertEqual(model.selectedThread?.messages.map(\.content), ["Keep me"])
    }

    private func payloadIsLoaded(_ id: UUID, in model: QuillCodeWorkspaceModel) throws -> Bool {
        try XCTUnwrap(model.root.threads.first { $0.id == id }).payloadResidency.isLoaded
    }
}
