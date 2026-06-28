import XCTest
import QuillCodeCore
import QuillCodePersistence
@testable import QuillCodeApp

@MainActor
final class WorkspaceThreadLifecycleIntegrationTests: XCTestCase {
    func testNewChatSelectsThreadAndRefreshesTopBar() {
        let project = ProjectRef(name: "QuillCode", path: "/tmp/QuillCode")
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(projects: [project]))

        let id = model.newChat(projectID: project.id)

        XCTAssertEqual(model.root.selectedThreadID, id)
        XCTAssertEqual(model.root.topBar.projectName, "QuillCode")
        XCTAssertEqual(model.root.topBar.threadTitle, "New chat")
        XCTAssertEqual(model.root.topBar.model, TrustedRouterDefaults.defaultModel)
        XCTAssertEqual(model.root.topBar.mode, .auto)
    }

    func testNewChatIgnoresUnknownProjectID() {
        let model = QuillCodeWorkspaceModel()

        let threadID = model.newChat(projectID: UUID())

        XCTAssertEqual(model.root.selectedThreadID, threadID)
        XCTAssertNil(model.root.selectedProjectID)
        XCTAssertNil(model.selectedThread?.projectID)
        XCTAssertNil(model.root.topBar.projectName)
    }

    func testForkFromLastCreatesBoundedThreadFromLatestUserTurn() throws {
        let project = ProjectRef(name: "QuillCode", path: "/tmp/QuillCode")
        let instructions = [
            ProjectInstruction(
                path: "AGENTS.md",
                title: "Project AGENTS.md",
                content: "Prefer focused tests.",
                byteCount: 21
            )
        ]
        let source = ChatThread(
            title: "Long thread",
            projectID: project.id,
            mode: .review,
            model: "z-ai/glm-5.2",
            messages: [
                .init(role: .user, content: "old question"),
                .init(role: .assistant, content: "old answer"),
                .init(role: .user, content: "latest question"),
                .init(role: .tool, content: #"{"result":"hidden continuation feedback"}"#),
                .init(role: .assistant, content: "latest answer")
            ],
            instructions: instructions
        )
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            projects: [project],
            selectedProjectID: project.id,
            threads: [source],
            selectedThreadID: source.id
        ))

        let forkID = try XCTUnwrap(model.forkFromLast())
        let fork = try XCTUnwrap(model.root.threads.first { $0.id == forkID })

        XCTAssertEqual(fork.title, "Fork: Long thread")
        XCTAssertEqual(fork.projectID, project.id)
        XCTAssertEqual(fork.mode, .review)
        XCTAssertEqual(fork.model, "z-ai/glm-5.2")
        XCTAssertEqual(fork.instructions, instructions)
        XCTAssertEqual(fork.messages.map(\.content), ["latest question", "latest answer"])
        XCTAssertFalse(fork.messages.contains { $0.role == .tool })
        XCTAssertEqual(fork.events.first?.kind, .notice)
        XCTAssertEqual(fork.events.first?.payloadJSON, source.id.uuidString)
        XCTAssertEqual(model.root.selectedThreadID, forkID)
        XCTAssertEqual(model.root.selectedProjectID, project.id)
    }

    func testWorkspaceCommandForkFromLastSelectsFork() throws {
        let source = ChatThread(title: "Active", messages: [
            .init(role: .user, content: "run whoami"),
            .init(role: .assistant, content: "Output:\nquill")
        ])
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            threads: [source],
            selectedThreadID: source.id
        ))

        XCTAssertTrue(model.runWorkspaceCommand("fork-from-last", workspaceRoot: try makeTempDirectory()))

        XCTAssertEqual(model.selectedThread?.title, "Fork: Active")
        XCTAssertEqual(model.selectedThread?.messages.map(\.content), ["run whoami", "Output:\nquill"])
    }

    func testWorkspaceCommandForkWithSummarySelectsSummarizedFork() throws {
        let source = ChatThread(title: "Active", messages: [
            .init(role: .user, content: "old task"),
            .init(role: .assistant, content: "old answer"),
            .init(role: .user, content: "latest task"),
            .init(role: .assistant, content: "latest answer")
        ])
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            threads: [source],
            selectedThreadID: source.id
        ))

        XCTAssertTrue(model.runWorkspaceCommand("fork-with-summary", workspaceRoot: try makeTempDirectory()))

        XCTAssertEqual(model.selectedThread?.title, "Fork summary: Active")
        XCTAssertTrue(model.selectedThread?.messages.first?.content.contains("Context forked from \"Active\" with a summary.") == true)
        XCTAssertEqual(Array(model.selectedThread?.messages.map(\.content).suffix(2) ?? []), ["latest task", "latest answer"])
    }

    func testWorkspaceCommandForkFullContextSelectsFullVisibleFork() throws {
        let source = ChatThread(title: "Active", messages: [
            .init(role: .user, content: "old task"),
            .init(role: .tool, content: #"{"hidden":true}"#),
            .init(role: .assistant, content: "old answer"),
            .init(role: .user, content: "latest task"),
            .init(role: .assistant, content: "latest answer")
        ])
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            threads: [source],
            selectedThreadID: source.id
        ))

        XCTAssertTrue(model.runWorkspaceCommand("fork-full-context", workspaceRoot: try makeTempDirectory()))

        XCTAssertEqual(model.selectedThread?.title, "Fork full: Active")
        XCTAssertEqual(model.selectedThread?.messages.map(\.content), [
            "old task",
            "old answer",
            "latest task",
            "latest answer"
        ])
    }

    func testWorkspaceCommandCompactContextCreatesBoundedThread() throws {
        let project = ProjectRef(name: "QuillCode", path: "/tmp/QuillCode")
        let instructions = [
            ProjectInstruction(
                path: "AGENTS.md",
                title: "Project AGENTS.md",
                content: "Use Swift.",
                byteCount: 10
            )
        ]
        let source = ChatThread(
            title: "Long context",
            projectID: project.id,
            mode: .review,
            model: "z-ai/glm-5.2",
            messages: [
                .init(role: .user, content: "old question one"),
                .init(role: .assistant, content: "old answer one"),
                .init(role: .user, content: "old question two"),
                .init(role: .assistant, content: "old answer two"),
                .init(role: .user, content: "latest request"),
                .init(role: .tool, content: #"{"result":"hidden continuation feedback"}"#),
                .init(role: .assistant, content: "latest answer")
            ],
            instructions: instructions
        )
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            projects: [project],
            selectedProjectID: project.id,
            threads: [source],
            selectedThreadID: source.id
        ))

        XCTAssertTrue(model.runWorkspaceCommand("compact-context", workspaceRoot: try makeTempDirectory()))
        let compacted = try XCTUnwrap(model.selectedThread)

        XCTAssertEqual(compacted.title, "Compact: Long context")
        XCTAssertEqual(compacted.projectID, project.id)
        XCTAssertEqual(compacted.mode, .review)
        XCTAssertEqual(compacted.model, "z-ai/glm-5.2")
        XCTAssertEqual(compacted.instructions, instructions)
        XCTAssertEqual(compacted.messages.count, 3)
        XCTAssertTrue(compacted.messages[0].content.contains("Context compacted from \"Long context\""))
        XCTAssertTrue(compacted.messages[0].content.contains("summarized 4 earlier messages"))
        XCTAssertEqual(compacted.messages[1].content, "latest request")
        XCTAssertEqual(compacted.messages[2].content, "latest answer")
        XCTAssertFalse(compacted.messages.contains { $0.role == .tool })
        XCTAssertFalse(compacted.messages[0].content.contains("hidden continuation feedback"))
        XCTAssertEqual(compacted.events.first?.kind, .notice)
        XCTAssertEqual(compacted.events.first?.payloadJSON, source.id.uuidString)
    }

    func testModelBackedCompactContextUsesConfiguredSummaryAndKeepsLatestTurn() async throws {
        let source = ChatThread(
            title: "Long live context",
            messages: [
                .init(role: .user, content: "old architecture question"),
                .init(role: .assistant, content: "old architecture answer"),
                .init(role: .user, content: "latest request"),
                .init(role: .tool, content: #"{"hidden":"tool feedback"}"#),
                .init(role: .assistant, content: "latest answer")
            ]
        )
        let generator = FixedContextSummaryGenerator(summary: "Preserve the model-backed architecture decision.")
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(threads: [source], selectedThreadID: source.id),
            contextSummaryGenerator: generator
        )

        let compactCandidate = await model.compactContextWithConfiguredSummary(sourceID: source.id)
        let compactID = try XCTUnwrap(compactCandidate)
        let compacted = try XCTUnwrap(model.root.threads.first { $0.id == compactID })

        XCTAssertEqual(compacted.title, "Compact: Long live context")
        XCTAssertTrue(compacted.messages[0].content.contains("Model summary:"))
        XCTAssertTrue(compacted.messages[0].content.contains("model-backed architecture decision"))
        XCTAssertEqual(Array(compacted.messages.map(\.content).suffix(2)), ["latest request", "latest answer"])
        XCTAssertFalse(compacted.messages[0].content.contains("tool feedback"))
        XCTAssertTrue(model.root.threads.first { $0.id == source.id }?.events.contains {
            $0.summary == "Model context summary ready"
        } == true)
        XCTAssertEqual(compacted.events.last?.summary, "Used model context summary")
        XCTAssertTrue(compacted.events.last?.payloadJSON?.contains(#""source" : "model""#) == true)
        XCTAssertEqual(model.root.selectedThreadID, compactID)
    }

    func testModelBackedForkWithSummaryUsesConfiguredSummary() async throws {
        let source = ChatThread(
            title: "Fork source",
            messages: [
                .init(role: .user, content: "old task"),
                .init(role: .assistant, content: "old result"),
                .init(role: .user, content: "latest task"),
                .init(role: .assistant, content: "latest result")
            ]
        )
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(threads: [source], selectedThreadID: source.id),
            contextSummaryGenerator: FixedContextSummaryGenerator(summary: "Keep the shipped tests and next work.")
        )

        let forkCandidate = await model.forkThreadWithConfiguredSummary(
            sourceID: source.id,
            strategy: .summarizedContext
        )
        let forkID = try XCTUnwrap(forkCandidate)
        let fork = try XCTUnwrap(model.root.threads.first { $0.id == forkID })

        XCTAssertEqual(fork.title, "Fork summary: Fork source")
        XCTAssertTrue(fork.messages[0].content.contains("Model summary:"))
        XCTAssertTrue(fork.messages[0].content.contains("shipped tests"))
        XCTAssertEqual(Array(fork.messages.map(\.content).suffix(2)), ["latest task", "latest result"])
        XCTAssertTrue(model.root.threads.first { $0.id == source.id }?.events.contains {
            $0.summary == "Model fork summary ready"
        } == true)
        XCTAssertEqual(fork.events.last?.summary, "Used model fork summary")
    }

    func testModelBackedCompactContextRecordsFallbackWhenSummaryFails() async throws {
        let source = ChatThread(
            title: "Fallback source",
            messages: [
                .init(role: .user, content: "old task"),
                .init(role: .assistant, content: "old result"),
                .init(role: .user, content: "latest task"),
                .init(role: .assistant, content: "latest result")
            ]
        )
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(threads: [source], selectedThreadID: source.id),
            contextSummaryGenerator: FailingContextSummaryGenerator()
        )

        let compactCandidate = await model.compactContextWithConfiguredSummary(sourceID: source.id)
        let compactID = try XCTUnwrap(compactCandidate)
        let compacted = try XCTUnwrap(model.root.threads.first { $0.id == compactID })
        let sourceAfter = try XCTUnwrap(model.root.threads.first { $0.id == source.id })

        XCTAssertTrue(compacted.messages[0].content.contains("Context compacted from \"Fallback source\"."))
        XCTAssertFalse(compacted.messages[0].content.contains("Model summary:"))
        XCTAssertEqual(Array(compacted.messages.map(\.content).suffix(2)), ["latest task", "latest result"])
        XCTAssertTrue(sourceAfter.events.contains {
            $0.summary == "Model context summary unavailable; used deterministic fallback"
        })
        XCTAssertEqual(compacted.events.last?.summary, "Used deterministic context summary fallback")
        XCTAssertTrue(compacted.events.last?.payloadJSON?.contains(#""source" : "deterministic_fallback""#) == true)
        XCTAssertTrue(compacted.events.last?.payloadJSON?.contains("secret") == false)
    }

    func testSelectingProjectSelectsNewestThreadForThatProject() {
        let firstProject = ProjectRef(name: "One", path: "/tmp/one")
        let secondProject = ProjectRef(name: "Two", path: "/tmp/two")
        let older = ChatThread(
            title: "Older",
            projectID: firstProject.id,
            updatedAt: Date(timeIntervalSince1970: 1)
        )
        let newer = ChatThread(
            title: "Newer",
            projectID: firstProject.id,
            updatedAt: Date(timeIntervalSince1970: 2)
        )
        let other = ChatThread(title: "Other", projectID: secondProject.id)
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            projects: [firstProject, secondProject],
            threads: [older, newer, other]
        ))

        model.selectProject(firstProject.id)

        XCTAssertEqual(model.root.selectedProjectID, firstProject.id)
        XCTAssertEqual(model.root.selectedThreadID, newer.id)
        XCTAssertEqual(model.root.topBar.threadTitle, "Newer")
        XCTAssertEqual(model.root.topBar.projectName, "One")
        XCTAssertEqual(model.selectedThread?.title, "Newer")
    }

    func testPinnedThreadsSortBeforeRecentThreads() {
        let older = ChatThread(
            title: "Older",
            updatedAt: Date(timeIntervalSince1970: 1)
        )
        var newer = ChatThread(
            title: "Newer",
            updatedAt: Date(timeIntervalSince1970: 2)
        )
        newer.isPinned = true
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(threads: [older, newer]))

        XCTAssertEqual(model.root.sidebarItems.map(\.title), ["Newer", "Older"])
    }

    func testArchiveSelectedThreadRemovesItFromSidebar() {
        let first = ChatThread(title: "First")
        let second = ChatThread(title: "Second")
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            threads: [first, second],
            selectedThreadID: first.id
        ))

        model.archiveSelectedThread()

        XCTAssertEqual(model.root.sidebarItems.map(\.title), ["Second"])
        XCTAssertEqual(model.root.selectedThreadID, second.id)
    }

    func testPinAndArchiveThreadByIDPersistChanges() throws {
        let root = try makeTempDirectory()
        let threadStore = JSONThreadStore(directory: root)
        let first = ChatThread(title: "First")
        let second = ChatThread(title: "Second")
        try threadStore.save(first)
        try threadStore.save(second)
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(
                threads: [first, second],
                selectedThreadID: first.id
            ),
            threadStore: threadStore
        )

        model.togglePinThread(second.id)
        model.archiveThread(first.id)

        XCTAssertEqual(model.root.sidebarItems.map(\.title), ["Second"])
        XCTAssertEqual(model.root.selectedThreadID, second.id)
        XCTAssertTrue(try threadStore.load(second.id).isPinned)
        XCTAssertTrue(try threadStore.load(first.id).isArchived)
    }

    func testRenameDuplicateUnarchiveAndDeleteThreadLifecycle() throws {
        let root = try makeTempDirectory()
        let threadStore = JSONThreadStore(directory: root)
        var archived = ChatThread(title: "Archived", messages: [
            .init(role: .user, content: "old task")
        ])
        archived.isArchived = true
        let active = ChatThread(title: "Active", messages: [
            .init(role: .user, content: "run whoami"),
            .init(role: .assistant, content: "quill")
        ])
        try threadStore.save(archived)
        try threadStore.save(active)
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(
                threads: [archived, active],
                selectedThreadID: active.id
            ),
            threadStore: threadStore
        )

        XCTAssertTrue(model.renameThread(active.id, to: "Renamed Active"))
        XCTAssertEqual(model.selectedThread?.title, "Renamed Active")
        XCTAssertEqual(try threadStore.load(active.id).title, "Renamed Active")

        let duplicateID = try XCTUnwrap(model.duplicateThread(active.id))
        let duplicate = try threadStore.load(duplicateID)
        XCTAssertEqual(duplicate.title, "Copy: Renamed Active")
        XCTAssertEqual(duplicate.messages.map(\.content), ["run whoami", "quill"])
        XCTAssertEqual(duplicate.events.last?.summary, "Duplicated from Renamed Active")
        XCTAssertEqual(model.root.selectedThreadID, duplicateID)

        XCTAssertTrue(model.unarchiveThread(archived.id))
        XCTAssertEqual(model.root.selectedThreadID, archived.id)
        XCTAssertFalse(try threadStore.load(archived.id).isArchived)
        XCTAssertEqual(model.root.sidebarItems.map(\.title), ["Archived", "Copy: Renamed Active", "Renamed Active"])

        XCTAssertTrue(model.deleteThread(archived.id))
        XCTAssertThrowsError(try threadStore.load(archived.id))
        XCTAssertFalse(model.root.threads.contains { $0.id == archived.id })
        XCTAssertEqual(model.root.selectedThreadID, duplicateID)
    }
}

private struct FixedContextSummaryGenerator: WorkspaceContextSummaryGenerating {
    var isModelBacked: Bool { true }
    var summary: String

    func summary(for request: WorkspaceContextSummaryRequest) async throws -> String {
        summary
    }
}

private struct FailingContextSummaryGenerator: WorkspaceContextSummaryGenerating {
    var isModelBacked: Bool { true }

    func summary(for request: WorkspaceContextSummaryRequest) async throws -> String {
        throw NSError(
            domain: "Summary",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "failure with sk-tr-v1-secret"]
        )
    }
}
