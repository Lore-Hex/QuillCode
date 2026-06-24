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
        selectedProject?.localActions.first { $0.id == id }
    }

    func selectedLocalAction(matching query: String) -> LocalEnvironmentAction? {
        let normalizedQuery = Self.normalizedActionName(query)
        return selectedProject?.localActions.first { action in
            action.id.caseInsensitiveCompare(query) == .orderedSame
                || action.title.caseInsensitiveCompare(query) == .orderedSame
                || action.relativePath.caseInsensitiveCompare(query) == .orderedSame
                || Self.normalizedActionName(action.title) == normalizedQuery
                || Self.normalizedActionName(action.relativePath) == normalizedQuery
        }
    }

    static func normalizedActionName(_ value: String) -> String {
        value
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
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
