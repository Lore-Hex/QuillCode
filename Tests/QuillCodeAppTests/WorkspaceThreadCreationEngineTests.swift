import XCTest
import QuillCodeCore
@testable import QuillCodeApp

final class WorkspaceThreadCreationEngineTests: XCTestCase {
    func testNewThreadUsesContext() {
        let projectID = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
        let instructions = [
            ProjectInstruction(path: "AGENTS.md", title: "Project AGENTS.md", content: "Use Swift.", byteCount: 10)
        ]
        let memories = [
            MemoryNote(
                id: "memory-1",
                scope: .project,
                title: "Preference",
                content: "Use focused tests.",
                relativePath: "memory.md",
                byteCount: 18
            )
        ]

        let thread = WorkspaceThreadCreationEngine.newThread(context: WorkspaceThreadCreationContext(
            projectID: projectID,
            mode: .review,
            model: "trustedrouter/fast",
            instructions: instructions,
            memories: memories
        ))

        XCTAssertEqual(thread.title, "New chat")
        XCTAssertEqual(thread.projectID, projectID)
        XCTAssertEqual(thread.mode, .review)
        XCTAssertEqual(thread.model, "trustedrouter/fast")
        XCTAssertEqual(thread.instructions, instructions)
        XCTAssertEqual(thread.memories, memories)
        XCTAssertTrue(thread.messages.isEmpty)
        XCTAssertTrue(thread.events.isEmpty)
    }

    func testForkThreadStartsAtLatestVisibleUserTurn() {
        let projectID = UUID(uuidString: "00000000-0000-0000-0000-000000000102")!
        let source = ChatThread(
            title: "Investigate issue",
            projectID: projectID,
            mode: .readOnly,
            model: "/prometheus",
            messages: [
                .init(role: .user, content: "old question"),
                .init(role: .assistant, content: "old answer"),
                .init(role: .user, content: "latest question"),
                .init(role: .tool, content: #"{"hidden":true}"#),
                .init(role: .assistant, content: "latest answer")
            ],
            goal: ThreadGoal(objective: "Resolve the issue")
        )

        let fork = WorkspaceThreadCreationEngine.forkThread(from: source, projectID: projectID)

        XCTAssertEqual(fork.title, "Fork: Investigate issue")
        XCTAssertEqual(fork.projectID, projectID)
        XCTAssertEqual(fork.mode, .readOnly)
        XCTAssertEqual(fork.model, TrustedRouterDefaults.prometheusModel)
        XCTAssertEqual(fork.messages.map(\.content), ["latest question", "latest answer"])
        XCTAssertFalse(fork.messages.contains { $0.role == .tool })
        XCTAssertEqual(fork.events.first?.summary, "Forked from Investigate issue")
        XCTAssertEqual(fork.events.first?.payloadJSON, source.id.uuidString)
        XCTAssertEqual(fork.goal, source.goal)
    }

    func testForkThreadCanSeedSummarizedContext() {
        let source = ChatThread(
            title: "Investigate issue",
            mode: .review,
            model: "trustedrouter/fast",
            messages: [
                .init(role: .user, content: "old question"),
                .init(role: .assistant, content: "old answer"),
                .init(role: .user, content: "latest question"),
                .init(role: .assistant, content: "latest answer")
            ]
        )

        let fork = WorkspaceThreadCreationEngine.forkThread(
            from: source,
            projectID: nil,
            strategy: .summarizedContext
        )

        XCTAssertEqual(fork.title, "Fork summary: Investigate issue")
        XCTAssertTrue(fork.messages.first?.content.contains("Context forked from \"Investigate issue\" with a summary.") == true)
        XCTAssertEqual(Array(fork.messages.map(\.content).suffix(2)), ["latest question", "latest answer"])
        XCTAssertEqual(fork.events.first?.summary, "Forked with summary from Investigate issue")
    }

    func testForkThreadCanSeedFullVisibleContext() {
        let source = ChatThread(
            title: "Investigate issue",
            messages: [
                .init(role: .user, content: "old question"),
                .init(role: .tool, content: #"{"hidden":true}"#),
                .init(role: .assistant, content: "old answer"),
                .init(role: .user, content: "latest question"),
                .init(role: .assistant, content: "latest answer")
            ]
        )

        let fork = WorkspaceThreadCreationEngine.forkThread(
            from: source,
            projectID: nil,
            strategy: .fullContext
        )

        XCTAssertEqual(fork.title, "Fork full: Investigate issue")
        XCTAssertEqual(fork.messages.map(\.content), [
            "old question",
            "old answer",
            "latest question",
            "latest answer"
        ])
        XCTAssertEqual(fork.events.first?.summary, "Forked with full visible context from Investigate issue")
    }

    func testCompactThreadAddsSummaryAndPreservesSourceContext() {
        let source = ChatThread(
            title: "Large thread",
            mode: .review,
            model: "z-ai/glm-5.2",
            messages: [
                .init(role: .user, content: "older task"),
                .init(role: .assistant, content: "older answer"),
                .init(role: .user, content: "latest task"),
                .init(role: .assistant, content: "latest answer")
            ],
            goal: ThreadGoal(objective: "Finish the large task"),
            instructions: [
                ProjectInstruction(path: "AGENTS.md", title: "AGENTS", content: "Rules", byteCount: 5)
            ]
        )

        let compacted = WorkspaceThreadCreationEngine.compactThread(from: source, projectID: nil)

        XCTAssertEqual(compacted.title, "Compact: Large thread")
        XCTAssertNil(compacted.projectID)
        XCTAssertEqual(compacted.mode, .review)
        XCTAssertEqual(compacted.model, "z-ai/glm-5.2")
        XCTAssertEqual(compacted.instructions, source.instructions)
        XCTAssertEqual(compacted.goal, source.goal)
        XCTAssertTrue(compacted.messages.first?.content.contains("Context compacted from \"Large thread\"") == true)
        XCTAssertEqual(Array(compacted.messages.map(\.content).suffix(2)), ["latest task", "latest answer"])
        XCTAssertEqual(compacted.events.first?.summary, "Compacted context from Large thread")
    }

    func testDuplicateThreadCopiesConversationAndClearsPinnedArchivedState() {
        let projectID = UUID(uuidString: "00000000-0000-0000-0000-000000000103")!
        var source = ChatThread(
            title: "Implement feature",
            projectID: projectID,
            mode: .review,
            model: "provider/model",
            messages: [
                .init(role: .user, content: "run whoami"),
                .init(role: .assistant, content: "quill")
            ],
            events: [
                .init(kind: .notice, summary: "Original event")
            ],
            goal: ThreadGoal(objective: "Implement the feature")
        )
        source.isPinned = true
        source.isArchived = true

        let duplicate = WorkspaceThreadCreationEngine.duplicateThread(source, projectID: projectID)

        XCTAssertNotEqual(duplicate.id, source.id)
        XCTAssertEqual(duplicate.title, "Copy: Implement feature")
        XCTAssertEqual(duplicate.projectID, projectID)
        XCTAssertEqual(duplicate.mode, .review)
        XCTAssertEqual(duplicate.model, "provider/model")
        XCTAssertEqual(duplicate.messages, source.messages)
        XCTAssertEqual(duplicate.goal, source.goal)
        XCTAssertFalse(duplicate.isPinned)
        XCTAssertFalse(duplicate.isArchived)
        XCTAssertEqual(duplicate.events.last?.summary, "Duplicated from Implement feature")
        XCTAssertEqual(duplicate.events.last?.payloadJSON, source.id.uuidString)
    }
}
