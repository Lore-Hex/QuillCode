import XCTest
import QuillCodeCore
@testable import QuillCodeApp

final class WorkspaceThreadContextPreparerTests: XCTestCase {
    func testEffectiveProjectIDPrefersThreadProject() {
        let fallbackProjectID = UUID()
        let threadProjectID = UUID()
        let thread = ChatThread(title: "Agent", projectID: threadProjectID)

        XCTAssertEqual(
            WorkspaceThreadContextPreparer.effectiveProjectID(
                thread: thread,
                fallbackProjectID: fallbackProjectID
            ),
            threadProjectID
        )
    }

    func testEffectiveProjectIDFallsBackToSelectedProject() {
        let fallbackProjectID = UUID()
        let thread = ChatThread(title: "Agent")

        XCTAssertEqual(
            WorkspaceThreadContextPreparer.effectiveProjectID(
                thread: thread,
                fallbackProjectID: fallbackProjectID
            ),
            fallbackProjectID
        )
    }

    func testSyncThreadContextUsesEffectiveProjectSnapshot() {
        let fallbackProjectID = UUID()
        let threadProjectID = UUID()
        let projects = [
            Self.project(id: fallbackProjectID, instructionTitle: "Fallback instruction", memoryTitle: "Fallback memory"),
            Self.project(id: threadProjectID, instructionTitle: "Thread instruction", memoryTitle: "Thread memory")
        ]
        let globalMemories = [
            Self.memory(id: "global", scope: .global, title: "Global memory")
        ]
        var thread = ChatThread(title: "Agent", projectID: threadProjectID)

        let prepared = WorkspaceThreadContextPreparer.syncThreadContext(
            &thread,
            fallbackProjectID: fallbackProjectID,
            projects: projects,
            globalMemories: globalMemories
        )

        XCTAssertEqual(prepared.threadID, thread.id)
        XCTAssertEqual(prepared.projectID, threadProjectID)
        XCTAssertEqual(thread.instructions.map(\.title), ["Thread instruction"])
        XCTAssertEqual(thread.memories.map(\.title), ["Global memory", "Thread memory"])
    }

    private static func project(id: UUID, instructionTitle: String, memoryTitle: String) -> ProjectRef {
        ProjectRef(
            id: id,
            name: instructionTitle,
            path: "/tmp/\(id.uuidString)",
            instructions: [
                ProjectInstruction(
                    path: "\(instructionTitle).md",
                    title: instructionTitle,
                    content: instructionTitle,
                    byteCount: instructionTitle.utf8.count
                )
            ],
            memories: [
                memory(id: memoryTitle, scope: .project, title: memoryTitle)
            ]
        )
    }

    private static func memory(id: String, scope: MemoryScope, title: String) -> MemoryNote {
        MemoryNote(
            id: id,
            scope: scope,
            title: title,
            content: title,
            relativePath: "\(scope.rawValue)/\(id).md",
            byteCount: title.utf8.count
        )
    }
}
