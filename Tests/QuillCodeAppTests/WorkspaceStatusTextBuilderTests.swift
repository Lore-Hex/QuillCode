import XCTest
import QuillCodeCore
@testable import QuillCodeApp

final class WorkspaceStatusTextBuilderTests: XCTestCase {
    func testStatusTextUsesSharedLabels() {
        let instruction = ProjectInstruction(
            path: "AGENTS.md",
            title: "Agent Rules",
            content: "Use Swift.",
            byteCount: 10
        )
        let memory = MemoryNote(
            id: "memory-1",
            scope: .project,
            title: "Preference",
            content: "Prefer small PRs.",
            relativePath: ".quillcode/memories/preference.md",
            byteCount: 17
        )
        let context = WorkspaceStatusContext(
            projectName: "QuillCode",
            threadTitle: "Status thread",
            instructions: [instruction],
            memories: [memory],
            mode: .review,
            model: TrustedRouterDefaults.synthModel,
            agentStatus: "Running"
        )

        XCTAssertEqual(WorkspaceStatusTextBuilder.statusText(for: context), """
        Project: QuillCode
        Thread: Status thread
        Instructions: 1 instruction file loaded
        Memories: 1 memory
        Mode: Review
        Model: \(TrustedRouterDefaults.synthModel)
        Agent: Running
        """)
    }

    func testInstructionAndMemoryLabelsHandleEmptyPluralAndTruncatedStates() {
        XCTAssertEqual(WorkspaceStatusTextBuilder.instructionLabel(for: []), "No project instructions")
        XCTAssertEqual(WorkspaceStatusTextBuilder.memoryLabel(for: []), "No memories")

        let instructions = [
            ProjectInstruction(path: "AGENTS.md", title: "Agent Rules", content: "", byteCount: 0),
            ProjectInstruction(path: ".quillcode/rules.md", title: "Rules", content: "", byteCount: 0, wasTruncated: true)
        ]
        let memories = [
            MemoryNote(id: "one", scope: .global, title: "One", content: "", relativePath: "one.md", byteCount: 0),
            MemoryNote(id: "two", scope: .project, title: "Two", content: "", relativePath: "two.md", byteCount: 0, wasTruncated: true)
        ]

        XCTAssertEqual(WorkspaceStatusTextBuilder.instructionLabel(for: instructions), "2 instruction files loaded, truncated")
        XCTAssertEqual(WorkspaceStatusTextBuilder.memoryLabel(for: memories), "2 memories, truncated")
    }

    func testModeLabelsAndTopBarSubtitles() {
        XCTAssertEqual(WorkspaceStatusTextBuilder.modeLabel(.readOnly), "Read-only")
        XCTAssertEqual(WorkspaceStatusTextBuilder.modeLabel(.review), "Review")
        XCTAssertEqual(WorkspaceStatusTextBuilder.modeLabel(.auto), "Auto")
        XCTAssertEqual(
            WorkspaceStatusTextBuilder.topBarSubtitle(projectName: "QuillCode", thread: nil),
            "QuillCode - Not started"
        )

        let thread = ChatThread(
            title: "Run tests",
            mode: .auto,
            model: TrustedRouterDefaults.fastModel
        )
        XCTAssertEqual(
            WorkspaceStatusTextBuilder.topBarSubtitle(projectName: "QuillCode", thread: thread),
            "QuillCode - Auto - \(TrustedRouterDefaults.fastModel)"
        )
    }
}
