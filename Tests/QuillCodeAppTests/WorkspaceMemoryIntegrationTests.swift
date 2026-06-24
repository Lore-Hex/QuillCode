import XCTest
import QuillCodeAgent
import QuillCodeCore
import QuillCodeTools
@testable import QuillCodeApp

@MainActor
final class WorkspaceMemoryIntegrationTests: XCTestCase {
    func testMemoryNotesLoadGlobalAndProjectIntoThreadAndSurface() async throws {
        let root = try makeQuillCodeTestDirectory()
        let globalMemories = try makeQuillCodeTestDirectory()
        try "Prefer concise progress updates.\n".write(
            to: globalMemories.appendingPathComponent("preferences.md"),
            atomically: true,
            encoding: .utf8
        )
        let projectMemoryDirectory = root.appendingPathComponent(".quillcode/memories")
        try FileManager.default.createDirectory(at: projectMemoryDirectory, withIntermediateDirectories: true)
        try "This project uses SwiftUI.\n".write(
            to: projectMemoryDirectory.appendingPathComponent("project.md"),
            atomically: true,
            encoding: .utf8
        )

        let model = QuillCodeWorkspaceModel(globalMemoryDirectory: globalMemories)
        let projectID = model.addProject(path: root, name: "Memory Project")
        let threadID = model.newChat(projectID: projectID)

        XCTAssertEqual(model.root.globalMemories.map(\.relativePath), ["memories/preferences.md"])
        XCTAssertEqual(model.root.projects.first?.memories.map(\.relativePath), [".quillcode/memories/project.md"])
        XCTAssertEqual(model.root.threads.first { $0.id == threadID }?.memories.map(\.title), ["Preferences", "Project"])

        XCTAssertTrue(model.runWorkspaceCommand("toggle-memories", workspaceRoot: root))
        let memories = model.surface().memories
        XCTAssertTrue(memories.isVisible)
        XCTAssertEqual(memories.globalCount, 1)
        XCTAssertEqual(memories.projectCount, 1)
        XCTAssertEqual(memories.items.map { $0.scope }, [MemoryScope.global, .project])
        XCTAssertEqual(memories.items.first?.canDelete, true)
        XCTAssertNotNil(memories.items.first?.deleteCommandID)
        XCTAssertEqual(memories.items.last?.canDelete, false)
        XCTAssertNil(memories.items.last?.deleteCommandID)
        XCTAssertEqual(model.surface().topBar.memoryLabel, "2 memories")
    }

    func testSlashRememberWritesGlobalMemoryAndRefreshesThreadSurface() async throws {
        let root = try makeQuillCodeTestDirectory()
        let globalMemories = try makeQuillCodeTestDirectory()
        let model = QuillCodeWorkspaceModel(globalMemoryDirectory: globalMemories)
        let projectID = model.addProject(path: root, name: "Memory Write Project")
        model.selectProject(projectID)

        model.setDraft("/remember Prefer small reviewable commits")
        await model.submitComposer(workspaceRoot: root)

        XCTAssertEqual(model.root.globalMemories.count, 1)
        let memory = try XCTUnwrap(model.root.globalMemories.first)
        XCTAssertEqual(memory.content, "Prefer small reviewable commits")
        XCTAssertTrue(memory.relativePath.hasPrefix("memories/manual-"))
        XCTAssertTrue(memory.relativePath.hasSuffix("-prefer-small-reviewable-commits.md"))
        XCTAssertEqual(model.selectedThread?.title, "Memory: \(memory.title)")
        XCTAssertEqual(model.selectedThread?.memories.map(\.content), ["Prefer small reviewable commits"])
        XCTAssertEqual(model.selectedThread?.events.last?.summary, "Saved memory: \(memory.title)")
        XCTAssertEqual(model.selectedThread?.events.last?.payloadJSON, memory.relativePath)
        XCTAssertEqual(model.selectedThread?.messages.last?.role, .assistant)
        XCTAssertTrue(model.selectedThread?.messages.last?.content.contains("Saved memory: \(memory.title)") == true)
        XCTAssertEqual(model.surface().topBar.memoryLabel, "1 memory")
        XCTAssertEqual(model.surface().memories.items.first?.canDelete, true)
        XCTAssertEqual(model.surface().memories.items.first?.deleteCommandID, "memory-delete:\(memory.id)")

        let filename = memory.relativePath.replacingOccurrences(of: "memories/", with: "")
        let savedURL = globalMemories.appendingPathComponent(filename)
        XCTAssertEqual(try String(contentsOf: savedURL, encoding: .utf8), "Prefer small reviewable commits\n")
    }

    func testAgentRememberToolWritesGlobalMemoryAndRefreshesThreadSurface() async throws {
        let root = try makeQuillCodeTestDirectory()
        let globalMemories = try makeQuillCodeTestDirectory()
        let model = QuillCodeWorkspaceModel(globalMemoryDirectory: globalMemories)
        let projectID = model.addProject(path: root, name: "Agent Memory Project")
        model.selectProject(projectID)

        model.setDraft("remember that I prefer small reviewable commits")
        await model.submitComposer(workspaceRoot: root)

        XCTAssertEqual(model.root.globalMemories.count, 1)
        let memory = try XCTUnwrap(model.root.globalMemories.first)
        XCTAssertEqual(memory.content, "I prefer small reviewable commits")
        XCTAssertEqual(model.selectedThread?.memories.map(\.content), ["I prefer small reviewable commits"])
        XCTAssertEqual(model.currentToolCards.last?.title, ToolDefinition.memoryRemember.name)
        XCTAssertEqual(model.currentToolCards.last?.status, .done)
        XCTAssertEqual(model.selectedThread?.messages.last?.role, .assistant)
        XCTAssertTrue(model.selectedThread?.messages.last?.content.contains("Saved memory: \(memory.title)") == true)
        XCTAssertEqual(model.surface().topBar.memoryLabel, "1 memory")

        let filename = memory.relativePath.replacingOccurrences(of: "memories/", with: "")
        let savedURL = globalMemories.appendingPathComponent(filename)
        XCTAssertEqual(try String(contentsOf: savedURL, encoding: .utf8), "I prefer small reviewable commits\n")
    }

    func testAgentRememberToolRejectsCredentialLikeMemory() async throws {
        let root = try makeQuillCodeTestDirectory()
        let globalMemories = try makeQuillCodeTestDirectory()
        let call = ToolCall(
            name: ToolDefinition.memoryRemember.name,
            argumentsJSON: ToolArguments.json([
                "content": "api_key=sk-qc-v1-ob4rbJAb9WOqdNIhSsT8oumjqaLZUX8p2zLHr1WOGn8"
            ])
        )
        let model = QuillCodeWorkspaceModel(
            runner: AgentRunner(llm: FixedMemoryToolLLMClient(call: call)),
            globalMemoryDirectory: globalMemories
        )

        model.setDraft("remember this api key")
        await model.submitComposer(workspaceRoot: root)

        XCTAssertEqual(model.root.globalMemories, [])
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: globalMemories.path)
                .filter { $0.hasSuffix(".md") },
            []
        )
        XCTAssertEqual(model.currentToolCards.last?.title, ToolDefinition.memoryRemember.name)
        XCTAssertEqual(model.currentToolCards.last?.status, .failed)
        XCTAssertTrue(model.selectedThread?.messages.last?.content.contains("credential") == true)
        XCTAssertEqual(model.surface().topBar.memoryLabel, "No memories")
    }

    func testMemoryDeleteWorkspaceCommandRemovesGlobalMemoryAndRefreshesThreadSurface() throws {
        let root = try makeQuillCodeTestDirectory()
        let globalMemories = try makeQuillCodeTestDirectory()
        try "Prefer concise progress updates.\n".write(
            to: globalMemories.appendingPathComponent("preferences.md"),
            atomically: true,
            encoding: .utf8
        )
        let projectMemoryDirectory = root.appendingPathComponent(".quillcode/memories")
        try FileManager.default.createDirectory(at: projectMemoryDirectory, withIntermediateDirectories: true)
        try "This project uses SwiftUI.\n".write(
            to: projectMemoryDirectory.appendingPathComponent("project.md"),
            atomically: true,
            encoding: .utf8
        )

        let model = QuillCodeWorkspaceModel(globalMemoryDirectory: globalMemories)
        let projectID = model.addProject(path: root, name: "Memory Delete Project")
        model.selectProject(projectID)
        _ = model.newChat(projectID: projectID)

        let global = try XCTUnwrap(model.root.globalMemories.first)
        XCTAssertTrue(model.runWorkspaceCommand("memory-delete:\(global.id)", workspaceRoot: root))

        XCTAssertFalse(FileManager.default.fileExists(
            atPath: globalMemories.appendingPathComponent("preferences.md").path
        ))
        XCTAssertEqual(model.root.globalMemories, [])
        XCTAssertEqual(model.selectedThread?.memories.map(\.relativePath), [".quillcode/memories/project.md"])
        XCTAssertEqual(model.selectedThread?.events.last?.summary, "Forgot memory: Preferences")
        XCTAssertEqual(model.selectedThread?.events.last?.payloadJSON, "memories/preferences.md")
        XCTAssertEqual(model.selectedThread?.messages.last?.role, .assistant)
        XCTAssertTrue(model.selectedThread?.messages.last?.content.contains("Forgot memory: Preferences") == true)
        XCTAssertEqual(model.surface().topBar.memoryLabel, "1 memory")
        XCTAssertEqual(model.surface().memories.items.map(\.scope), [.project])
    }

    func testMemoryDeleteRejectsUnknownGlobalMemoryIDWithoutRemovingFiles() throws {
        let root = try makeQuillCodeTestDirectory()
        let globalMemories = try makeQuillCodeTestDirectory()
        try "Prefer concise progress updates.\n".write(
            to: globalMemories.appendingPathComponent("preferences.md"),
            atomically: true,
            encoding: .utf8
        )

        let model = QuillCodeWorkspaceModel(globalMemoryDirectory: globalMemories)
        _ = model.newChat()

        XCTAssertTrue(model.runWorkspaceCommand("memory-delete:missing-memory", workspaceRoot: root))

        XCTAssertTrue(FileManager.default.fileExists(
            atPath: globalMemories.appendingPathComponent("preferences.md").path
        ))
        XCTAssertEqual(model.root.globalMemories.map(\.relativePath), ["memories/preferences.md"])
        XCTAssertEqual(model.selectedThread?.title, "Memory not deleted")
        XCTAssertTrue(model.selectedThread?.messages.last?.content.contains("not found") == true)
    }

    func testSlashRememberRejectsCredentialLikeMemory() async throws {
        let root = try makeQuillCodeTestDirectory()
        let globalMemories = try makeQuillCodeTestDirectory()
        let model = QuillCodeWorkspaceModel(globalMemoryDirectory: globalMemories)

        model.setDraft("/remember api_key=sk-qc-v1-ob4rbJAb9WOqdNIhSsT8oumjqaLZUX8p2zLHr1WOGn8")
        await model.submitComposer(workspaceRoot: root)

        XCTAssertEqual(model.root.globalMemories, [])
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: globalMemories.path)
                .filter { $0.hasSuffix(".md") },
            []
        )
        XCTAssertEqual(model.selectedThread?.title, "Memory not saved")
        XCTAssertTrue(model.selectedThread?.messages.last?.content.contains("credential") == true)
        XCTAssertEqual(model.surface().topBar.memoryLabel, "No memories")
    }

    func testMemoryAddWorkspaceCommandPrefillsRememberSlash() throws {
        let model = QuillCodeWorkspaceModel()

        XCTAssertTrue(model.runWorkspaceCommand("memory-add", workspaceRoot: try makeQuillCodeTestDirectory()))

        XCTAssertEqual(model.composer.draft, "/remember ")
    }
}

private struct FixedMemoryToolLLMClient: LLMClient {
    var call: ToolCall

    func nextAction(thread: ChatThread, userMessage: String, tools: [ToolDefinition]) async throws -> AgentAction {
        .tool(call)
    }
}
