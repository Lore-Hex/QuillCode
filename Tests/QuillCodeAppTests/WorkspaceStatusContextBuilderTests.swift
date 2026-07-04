import XCTest
import QuillCodeCore
@testable import QuillCodeApp

final class WorkspaceStatusContextBuilderTests: XCTestCase {
    func testStatusContextUsesSelectedProjectThreadAndTopBarState() {
        let instruction = ProjectInstruction(
            path: "AGENTS.md",
            title: "Agent Rules",
            content: "Use Swift.",
            byteCount: 10
        )
        let memory = MemoryNote(
            id: "thread-memory",
            scope: .project,
            title: "Thread Memory",
            content: "Thread-specific preference.",
            relativePath: ".quillcode/memories/thread.md",
            byteCount: 27
        )
        let fallbackMemory = MemoryNote(
            id: "fallback-memory",
            scope: .global,
            title: "Global Memory",
            content: "Fallback preference.",
            relativePath: ".quillcode/memories/global.md",
            byteCount: 20
        )
        let project = ProjectRef(
            name: "QuillCode",
            path: "/tmp/quillcode",
            instructions: [instruction]
        )
        let thread = ChatThread(
            title: "Status thread",
            mode: .auto,
            model: TrustedRouterDefaults.fastModel,
            memories: [memory]
        )
        let root = QuillCodeRootState(
            topBar: TopBarState(
                projectName: "Fallback Project",
                model: TrustedRouterDefaults.prometheusModel,
                mode: .review,
                agentStatus: "Running"
            )
        )

        let context = WorkspaceStatusContextBuilder.context(
            root: root,
            selectedProject: project,
            selectedThread: thread,
            fallbackThreadContext: WorkspaceThreadContextSnapshot(instructions: [], memories: [fallbackMemory])
        )

        XCTAssertEqual(context.projectName, "QuillCode")
        XCTAssertEqual(context.threadTitle, "Status thread")
        XCTAssertEqual(context.instructions, [instruction])
        XCTAssertEqual(context.memories, [memory])
        XCTAssertEqual(context.mode, .review)
        XCTAssertEqual(context.model, TrustedRouterDefaults.prometheusModel)
        XCTAssertEqual(context.agentStatus, "Running")
    }

    func testStatusContextFallsBackWithoutSelectedThread() {
        let fallbackMemory = MemoryNote(
            id: "fallback-memory",
            scope: .global,
            title: "Global Memory",
            content: "Fallback preference.",
            relativePath: ".quillcode/memories/global.md",
            byteCount: 20
        )
        let root = QuillCodeRootState(
            topBar: TopBarState(
                projectName: "Recent Project",
                model: TrustedRouterDefaults.fastModel,
                mode: .auto,
                agentStatus: "Idle"
            )
        )

        let context = WorkspaceStatusContextBuilder.context(
            root: root,
            selectedProject: nil,
            selectedThread: nil,
            fallbackThreadContext: WorkspaceThreadContextSnapshot(instructions: [], memories: [fallbackMemory])
        )

        XCTAssertEqual(context.projectName, "Recent Project")
        XCTAssertEqual(context.threadTitle, "No chat")
        XCTAssertEqual(context.instructions, [])
        XCTAssertEqual(context.memories, [fallbackMemory])
        XCTAssertEqual(context.mode, .auto)
        XCTAssertEqual(context.model, TrustedRouterDefaults.fastModel)
        XCTAssertEqual(context.agentStatus, "Idle")
    }
}
