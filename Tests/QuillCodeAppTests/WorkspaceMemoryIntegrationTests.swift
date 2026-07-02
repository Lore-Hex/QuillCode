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
        XCTAssertEqual(memories.items.first?.canEdit, true)
        XCTAssertNotNil(memories.items.first?.editCommandID)
        XCTAssertEqual(memories.items.last?.canEdit, true)
        XCTAssertEqual(memories.items.last?.editCommandID, "memory-edit:project:.quillcode/memories/project.md")
        XCTAssertEqual(memories.items.first?.canDelete, true)
        XCTAssertNotNil(memories.items.first?.deleteCommandID)
        XCTAssertEqual(memories.items.last?.canDelete, true)
        XCTAssertEqual(memories.items.last?.deleteCommandID, "memory-delete:project:.quillcode/memories/project.md")
        XCTAssertEqual(model.surface().topBar.memoryLabel, "2 memories")
    }

    func testSurfaceIncludesMemorySummariesAndCommand() {
        let project = ProjectRef(
            name: "QuillCode",
            path: "/tmp/QuillCode",
            memories: [
                MemoryNote(
                    id: "project:.quillcode/memories/project.md",
                    scope: .project,
                    title: "Project",
                    content: "QuillCode should stay native Swift and document major decisions.",
                    relativePath: ".quillcode/memories/project.md",
                    byteCount: 63
                )
            ]
        )
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(
                projects: [project],
                selectedProjectID: project.id,
                globalMemories: [
                    MemoryNote(
                        id: "global:memories/preferences.md",
                        scope: .global,
                        title: "Preferences",
                        content: "Prefer focused tests and small reviewable commits.",
                        relativePath: "memories/preferences.md",
                        byteCount: 48
                    )
                ]
            ),
            memories: MemoriesState(isVisible: true)
        )

        let surface = model.surface()

        XCTAssertTrue(surface.memories.isVisible)
        XCTAssertEqual(surface.memories.globalCount, 1)
        XCTAssertEqual(surface.memories.projectCount, 1)
        XCTAssertEqual(surface.memories.items.map { $0.scope }, [MemoryScope.global, .project])
        XCTAssertEqual(surface.memories.items.first?.title, "Preferences")
        XCTAssertEqual(surface.topBar.memoryLabel, "2 memories")
        XCTAssertEqual(surface.commands.first { $0.id == "toggle-memories" }?.category, WorkspaceCommandPalette.memoriesCategory)
    }

    func testRemoteProjectMemoryExposesRemoteEditActionWhenProjectIsActive() {
        let project = ProjectRef(
            name: "Remote QuillCode",
            path: "/srv/QuillCode",
            connection: .ssh(path: "/srv/QuillCode", host: "example.com", user: "quill"),
            memories: [
                MemoryNote(
                    id: "project:.quillcode/memories/project.md",
                    scope: .project,
                    title: "Project",
                    content: "Remote memory should not be edited through local file APIs.",
                    relativePath: ".quillcode/memories/project.md",
                    byteCount: 60
                )
            ]
        )
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(projects: [project], selectedProjectID: project.id),
            memories: MemoriesState(isVisible: true)
        )

        let projectMemory = model.surface().memories.items.first

        XCTAssertEqual(projectMemory?.scope, .project)
        XCTAssertEqual(projectMemory?.canEdit, true)
        XCTAssertEqual(projectMemory?.editCommandID, "memory-edit:project:.quillcode/memories/project.md")
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
        XCTAssertEqual(model.surface().memories.items.first?.canEdit, true)
        XCTAssertEqual(model.surface().memories.items.first?.editCommandID, "memory-edit:\(memory.id)")
        XCTAssertEqual(model.surface().memories.items.first?.canDelete, true)
        XCTAssertEqual(model.surface().memories.items.first?.deleteCommandID, "memory-delete:\(memory.id)")

        let filename = memory.relativePath.replacingOccurrences(of: "memories/", with: "")
        let savedURL = globalMemories.appendingPathComponent(filename)
        XCTAssertEqual(try String(contentsOf: savedURL, encoding: .utf8), "Prefer small reviewable commits\n")
    }

    func testMemoryEditWorkspaceCommandPrefillsAndSlashUpdateRewritesGlobalMemory() async throws {
        let root = try makeQuillCodeTestDirectory()
        let globalMemories = try makeQuillCodeTestDirectory()
        try "Prefer concise progress updates.\n".write(
            to: globalMemories.appendingPathComponent("preferences.md"),
            atomically: true,
            encoding: .utf8
        )

        let model = QuillCodeWorkspaceModel(globalMemoryDirectory: globalMemories)
        _ = model.newChat()
        let memory = try XCTUnwrap(model.root.globalMemories.first)

        XCTAssertTrue(model.runWorkspaceCommand("memory-edit:\(memory.id)", workspaceRoot: root))
        XCTAssertEqual(model.composer.draft, "/remember-edit \(memory.id)\nPrefer concise progress updates.")

        model.setDraft("/remember-edit \(memory.id)\nPrefer small reviewable commits")
        await model.submitComposer(workspaceRoot: root)

        XCTAssertEqual(model.root.globalMemories.count, 1)
        let updated = try XCTUnwrap(model.root.globalMemories.first)
        XCTAssertEqual(updated.id, memory.id)
        XCTAssertEqual(updated.content, "Prefer small reviewable commits")
        XCTAssertEqual(model.selectedThread?.title, "Updated memory: \(updated.title)")
        XCTAssertEqual(model.selectedThread?.memories.map(\.content), ["Prefer small reviewable commits"])
        XCTAssertEqual(model.selectedThread?.events.last?.summary, "Updated memory: \(updated.title)")
        XCTAssertEqual(model.selectedThread?.events.last?.payloadJSON, updated.relativePath)
        XCTAssertTrue(model.selectedThread?.messages.last?.content.contains("Updated memory: \(updated.title)") == true)
        XCTAssertEqual(
            try String(contentsOf: globalMemories.appendingPathComponent("preferences.md"), encoding: .utf8),
            "Prefer small reviewable commits\n"
        )
    }

    func testMemoryEditWorkspaceCommandPrefillsAndSlashUpdateRewritesProjectMemory() async throws {
        let root = try makeQuillCodeTestDirectory()
        let globalMemories = try makeQuillCodeTestDirectory()
        let projectMemoryDirectory = root.appendingPathComponent(".quillcode/memories")
        try FileManager.default.createDirectory(at: projectMemoryDirectory, withIntermediateDirectories: true)
        try "Use SwiftUI.\n".write(
            to: projectMemoryDirectory.appendingPathComponent("project.md"),
            atomically: true,
            encoding: .utf8
        )

        let model = QuillCodeWorkspaceModel(globalMemoryDirectory: globalMemories)
        let projectID = model.addProject(path: root, name: "Project Memory Edit")
        _ = model.newChat(projectID: projectID)
        let memory = try XCTUnwrap(model.root.projects.first?.memories.first)

        XCTAssertTrue(model.runWorkspaceCommand("memory-edit:\(memory.id)", workspaceRoot: root))
        XCTAssertEqual(model.composer.draft, "/remember-edit \(memory.id)\nUse SwiftUI.")

        model.setDraft("/remember-edit \(memory.id)\nUse SwiftUI and keep UI state deterministic.")
        await model.submitComposer(workspaceRoot: root)

        let updated = try XCTUnwrap(model.root.projects.first?.memories.first)
        XCTAssertEqual(updated.id, memory.id)
        XCTAssertEqual(updated.content, "Use SwiftUI and keep UI state deterministic.")
        XCTAssertEqual(model.selectedThread?.title, "Updated memory: \(updated.title)")
        XCTAssertEqual(
            model.selectedThread?.memories.map(\.content),
            ["Use SwiftUI and keep UI state deterministic."]
        )
        XCTAssertEqual(model.selectedThread?.events.last?.summary, "Updated memory: \(updated.title)")
        XCTAssertEqual(model.selectedThread?.events.last?.payloadJSON, updated.relativePath)
        XCTAssertTrue(model.selectedThread?.messages.last?.content.contains("Updated memory: \(updated.title)") == true)
        XCTAssertEqual(
            try String(contentsOf: projectMemoryDirectory.appendingPathComponent("project.md"), encoding: .utf8),
            "Use SwiftUI and keep UI state deterministic.\n"
        )
        XCTAssertEqual(model.surface().topBar.memoryLabel, "1 memory")
        XCTAssertEqual(model.surface().memories.items.first?.editCommandID, "memory-edit:\(memory.id)")
    }

    func testMemoryEditWorkspaceCommandRewritesRemoteProjectMemoryThroughSSH() async throws {
        let localRoot = try makeTempDirectory()
        let remoteRoot = try makeTempDirectory()
        let projectMemoryDirectory = remoteRoot.appendingPathComponent(".quillcode/memories")
        try FileManager.default.createDirectory(at: projectMemoryDirectory, withIntermediateDirectories: true)
        try "Use SwiftUI.\n".write(
            to: projectMemoryDirectory.appendingPathComponent("project.md"),
            atomically: true,
            encoding: .utf8
        )

        let argumentsFile = localRoot.appendingPathComponent("ssh-memory-edit-args.txt")
        let fakeSSH = try makeExecutingFakeSSH(in: localRoot, argumentsFile: argumentsFile)
        let connection = ProjectConnection.ssh(path: remoteRoot.path, host: "feather.local", user: "quill")
        let project = ProjectRef(name: "Feather", path: connection.path, connection: connection)
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(projects: [project], selectedProjectID: project.id),
            sshRemoteShellExecutor: SSHRemoteShellExecutor(
                sshExecutable: fakeSSH.path,
                connectTimeoutSeconds: 4
            )
        )
        _ = model.newChat(projectID: project.id)
        XCTAssertTrue(model.refreshProjectContext(project.id), model.lastError ?? "")
        let memory = try XCTUnwrap(model.root.projects.first?.memories.first)

        XCTAssertTrue(model.runWorkspaceCommand("memory-edit:\(memory.id)", workspaceRoot: localRoot))
        XCTAssertEqual(model.composer.draft, "/remember-edit \(memory.id)\nUse SwiftUI.")

        model.setDraft("/remember-edit \(memory.id)\nUse SwiftUI and keep remote memory editable.")
        await model.submitComposer(workspaceRoot: localRoot)

        let updated = try XCTUnwrap(model.root.projects.first?.memories.first)
        XCTAssertEqual(updated.id, memory.id)
        XCTAssertEqual(updated.content, "Use SwiftUI and keep remote memory editable.")
        XCTAssertEqual(model.selectedThread?.title, "Updated memory: \(updated.title)")
        XCTAssertEqual(
            model.selectedThread?.memories.map(\.content),
            ["Use SwiftUI and keep remote memory editable."]
        )
        XCTAssertEqual(model.selectedThread?.events.last?.summary, "Updated memory: \(updated.title)")
        XCTAssertEqual(model.selectedThread?.events.last?.payloadJSON, updated.relativePath)
        XCTAssertEqual(
            try String(contentsOf: projectMemoryDirectory.appendingPathComponent("project.md"), encoding: .utf8),
            "Use SwiftUI and keep remote memory editable.\n"
        )
        XCTAssertEqual(model.surface().memories.items.first?.editCommandID, "memory-edit:\(memory.id)")
        let arguments = try String(contentsOf: argumentsFile, encoding: .utf8)
        XCTAssertTrue(arguments.contains("cd '\(remoteRoot.path)' &&"), arguments)
        XCTAssertTrue(arguments.contains("QUILLCODE_CONTEXT_"), arguments)
    }

    func testMemoryDeleteWorkspaceCommandRemovesRemoteProjectMemoryThroughSSH() throws {
        let localRoot = try makeTempDirectory()
        let remoteRoot = try makeTempDirectory()
        let projectMemoryDirectory = remoteRoot.appendingPathComponent(".quillcode/memories")
        try FileManager.default.createDirectory(at: projectMemoryDirectory, withIntermediateDirectories: true)
        let memoryURL = projectMemoryDirectory.appendingPathComponent("project.md")
        try "Use SwiftUI.\n".write(to: memoryURL, atomically: true, encoding: .utf8)

        let argumentsFile = localRoot.appendingPathComponent("ssh-memory-delete-args.txt")
        let fakeSSH = try makeExecutingFakeSSH(in: localRoot, argumentsFile: argumentsFile)
        let connection = ProjectConnection.ssh(path: remoteRoot.path, host: "feather.local", user: "quill")
        let project = ProjectRef(name: "Feather", path: connection.path, connection: connection)
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(projects: [project], selectedProjectID: project.id),
            sshRemoteShellExecutor: SSHRemoteShellExecutor(
                sshExecutable: fakeSSH.path,
                connectTimeoutSeconds: 4
            )
        )
        _ = model.newChat(projectID: project.id)
        XCTAssertTrue(model.refreshProjectContext(project.id), model.lastError ?? "")
        let memory = try XCTUnwrap(model.root.projects.first?.memories.first)

        XCTAssertTrue(model.runWorkspaceCommand("memory-delete:\(memory.id)", workspaceRoot: localRoot))

        XCTAssertFalse(FileManager.default.fileExists(atPath: memoryURL.path))
        XCTAssertEqual(model.root.projects.first?.memories, [])
        XCTAssertEqual(model.selectedThread?.title, "Forgot memory: \(memory.title)")
        XCTAssertEqual(model.selectedThread?.memories, [])
        XCTAssertEqual(model.selectedThread?.events.last?.summary, "Forgot memory: \(memory.title)")
        XCTAssertEqual(model.selectedThread?.events.last?.payloadJSON, memory.relativePath)
        XCTAssertEqual(model.surface().memories.items, [])
        let arguments = try String(contentsOf: argumentsFile, encoding: .utf8)
        XCTAssertTrue(arguments.contains("cd '\(remoteRoot.path)' &&"), arguments)
        XCTAssertTrue(arguments.contains("QUILLCODE_CONTEXT_"), arguments)
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
                "content": "api_key=SYNTHETIC_TEST_SECRET_DO_NOT_USE"
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
        let queuedPayload = try XCTUnwrap(model.selectedThread?.events.first { $0.kind == .toolQueued }?.payloadJSON)
        XCTAssertTrue(queuedPayload.contains(ToolCall.redactedMemoryContentValue))
        XCTAssertFalse(queuedPayload.contains("SYNTHETIC_TEST_SECRET_DO_NOT_USE"))
        XCTAssertEqual(model.surface().memories.redactionReviewCount, 1)
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

    func testMemoryDeleteWorkspaceCommandRemovesProjectMemoryAndRefreshesThreadSurface() throws {
        let root = try makeQuillCodeTestDirectory()
        let globalMemories = try makeQuillCodeTestDirectory()
        let projectMemoryDirectory = root.appendingPathComponent(".quillcode/memories")
        try FileManager.default.createDirectory(at: projectMemoryDirectory, withIntermediateDirectories: true)
        try "This project uses SwiftUI.\n".write(
            to: projectMemoryDirectory.appendingPathComponent("project.md"),
            atomically: true,
            encoding: .utf8
        )

        let model = QuillCodeWorkspaceModel(globalMemoryDirectory: globalMemories)
        let projectID = model.addProject(path: root, name: "Project Memory Delete")
        model.selectProject(projectID)
        _ = model.newChat(projectID: projectID)
        let projectMemory = try XCTUnwrap(model.root.projects.first?.memories.first)

        XCTAssertTrue(model.runWorkspaceCommand("memory-delete:\(projectMemory.id)", workspaceRoot: root))

        XCTAssertFalse(FileManager.default.fileExists(
            atPath: projectMemoryDirectory.appendingPathComponent("project.md").path
        ))
        XCTAssertEqual(model.root.projects.first?.memories, [])
        XCTAssertEqual(model.selectedThread?.memories, [])
        XCTAssertEqual(model.selectedThread?.events.last?.summary, "Forgot memory: Project")
        XCTAssertEqual(model.selectedThread?.events.last?.payloadJSON, ".quillcode/memories/project.md")
        XCTAssertEqual(model.surface().topBar.memoryLabel, "No memories")
        XCTAssertEqual(model.surface().memories.items, [])
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

        model.setDraft("/remember api_key=SYNTHETIC_TEST_SECRET_DO_NOT_USE")
        await model.submitComposer(workspaceRoot: root)

        XCTAssertEqual(model.root.globalMemories, [])
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: globalMemories.path)
                .filter { $0.hasSuffix(".md") },
            []
        )
        XCTAssertEqual(model.selectedThread?.title, "Memory not saved")
        XCTAssertFalse(model.selectedThread?.messages.first?.content.contains("SYNTHETIC_TEST_SECRET_DO_NOT_USE") == true)
        XCTAssertTrue(model.selectedThread?.messages.first?.content.contains(ToolCall.redactedMemoryContentValue) == true)
        XCTAssertTrue(model.selectedThread?.messages.last?.content.contains("credential") == true)
        XCTAssertEqual(model.surface().memories.redactionReviewCount, 1)
        XCTAssertEqual(model.surface().memories.redactionReviews.first?.title, "Memory redaction blocked")
        XCTAssertFalse(
            model.surface().memories.redactionReviews.first?.redactedInput
                .contains("SYNTHETIC_TEST_SECRET_DO_NOT_USE") == true
        )
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
