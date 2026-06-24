import Foundation
import QuillCodeCore

struct WorkspaceActiveContextSources: Sendable, Hashable {
    var instructions: [ProjectInstruction]
    var memories: [MemoryNote]
}

struct WorkspaceContextResolver: Sendable {
    var projects: [ProjectRef]
    var globalMemories: [MemoryNote]
    var selectedProject: ProjectRef?

    func instructions(for projectID: UUID?) -> [ProjectInstruction] {
        project(id: projectID)?.instructions ?? []
    }

    func memoryNotes(for projectID: UUID?) -> [MemoryNote] {
        globalMemories + (project(id: projectID)?.memories ?? [])
    }

    func activeSources(for thread: ChatThread?) -> WorkspaceActiveContextSources {
        WorkspaceActiveContextSources(
            instructions: activeInstructions(for: thread),
            memories: activeMemories(for: thread)
        )
    }

    func selectedLocalAction(withID id: String) -> LocalEnvironmentAction? {
        LocalEnvironmentActionMatcher.action(withID: id, in: selectedProject?.localActions ?? [])
    }

    func selectedLocalAction(matching query: String) -> LocalEnvironmentAction? {
        LocalEnvironmentActionMatcher.action(matching: query, in: selectedProject?.localActions ?? [])
    }

    static func normalizedActionName(_ value: String) -> String {
        LocalEnvironmentActionMatcher.normalizedActionName(value)
    }

    private func project(id: UUID?) -> ProjectRef? {
        guard let id else { return nil }
        return projects.first { $0.id == id }
    }

    private func activeInstructions(for thread: ChatThread?) -> [ProjectInstruction] {
        if let thread, !thread.instructions.isEmpty {
            return thread.instructions
        }
        return selectedProject?.instructions ?? []
    }

    private func activeMemories(for thread: ChatThread?) -> [MemoryNote] {
        if let thread, !thread.memories.isEmpty {
            return thread.memories
        }
        return globalMemories + (selectedProject?.memories ?? [])
    }
}
