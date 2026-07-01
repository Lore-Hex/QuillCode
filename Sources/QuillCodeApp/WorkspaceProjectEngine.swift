import Foundation
import QuillCodeCore

struct WorkspaceProjectMetadata: Equatable, Sendable {
    var instructions: [ProjectInstruction]
    var localActions: [LocalEnvironmentAction]
    var extensionManifests: [ProjectExtensionManifest]
    var memories: [MemoryNote]

    static let empty = WorkspaceProjectMetadata(
        instructions: [],
        localActions: [],
        extensionManifests: [],
        memories: []
    )
}

struct WorkspaceProjectUpsertResult: Equatable, Sendable {
    var projectID: UUID
    var isNewProject: Bool
}

struct WorkspaceProjectSelection: Equatable, Sendable {
    var projectID: UUID?
    var threadID: UUID?
}

struct WorkspaceProjectRemovalResult: Equatable, Sendable {
    var selectedProjectID: UUID?
    var changedThreadIDs: [UUID]
}

enum WorkspaceProjectError: Error, Equatable, Sendable {
    case invalidSSHAddress

    var message: String {
        switch self {
        case .invalidSSHAddress:
            return WorkspaceProjectEngine.invalidSSHAddressMessage
        }
    }
}

enum WorkspaceProjectEngine {
    static let invalidSSHAddressMessage = "Use SSH format user@host:/path or ssh://user@host/path."

    @discardableResult
    static func upsertLocalProject(
        path: URL,
        name: String?,
        metadata: WorkspaceProjectMetadata,
        projects: inout [ProjectRef],
        now: Date = Date()
    ) -> WorkspaceProjectUpsertResult {
        let standardized = path.standardizedFileURL
        let projectName = name ?? defaultProjectName(for: standardized)

        if let index = projects.firstIndex(where: { $0.path == standardized.path && !$0.isRemote }) {
            projects[index].name = projectName
            applyInstructionMetadata(metadata.instructions, to: &projects[index], now: now)
            projects[index].localActions = metadata.localActions
            projects[index].extensionManifests = metadata.extensionManifests
            projects[index].memories = metadata.memories
            projects[index].lastOpenedAt = now
            return WorkspaceProjectUpsertResult(projectID: projects[index].id, isNewProject: false)
        }

        let project = ProjectRef(
            name: projectName,
            path: standardized.path,
            lastOpenedAt: now,
            instructions: metadata.instructions,
            localActions: metadata.localActions,
            extensionManifests: metadata.extensionManifests,
            memories: metadata.memories
        )
        projects.insert(project, at: 0)
        return WorkspaceProjectUpsertResult(projectID: project.id, isNewProject: true)
    }

    @discardableResult
    static func upsertSSHProject(
        address: String,
        name: String?,
        projects: inout [ProjectRef],
        now: Date = Date()
    ) -> Result<WorkspaceProjectUpsertResult, WorkspaceProjectError> {
        guard let connection = ProjectConnection.parseSSH(address) else {
            return .failure(.invalidSSHAddress)
        }

        let projectName = name ?? defaultSSHProjectName(for: connection)
        if let index = projects.firstIndex(where: { $0.connection == connection }) {
            projects[index].name = projectName
            projects[index].lastOpenedAt = now
            return .success(WorkspaceProjectUpsertResult(projectID: projects[index].id, isNewProject: false))
        }

        let project = ProjectRef(
            name: projectName,
            path: connection.path,
            connection: connection,
            lastOpenedAt: now
        )
        projects.insert(project, at: 0)
        return .success(WorkspaceProjectUpsertResult(projectID: project.id, isNewProject: true))
    }

    @discardableResult
    static func renameProject(
        _ id: UUID,
        to name: String,
        projects: inout [ProjectRef],
        now: Date = Date()
    ) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let index = projects.firstIndex(where: { $0.id == id })
        else {
            return false
        }
        projects[index].name = trimmed
        projects[index].lastOpenedAt = now
        return true
    }

    @discardableResult
    static func removeProject(
        _ id: UUID,
        projects: inout [ProjectRef],
        threads: inout [ChatThread],
        selectedProjectID: UUID?
    ) -> WorkspaceProjectRemovalResult? {
        guard let index = projects.firstIndex(where: { $0.id == id }) else {
            return nil
        }

        projects.remove(at: index)
        var changedThreadIDs: [UUID] = []
        for threadIndex in threads.indices where threads[threadIndex].projectID == id {
            threads[threadIndex].projectID = nil
            changedThreadIDs.append(threads[threadIndex].id)
        }

        let nextSelection = selectedProjectID == id ? nil : knownProjectID(selectedProjectID, projects: projects)
        return WorkspaceProjectRemovalResult(
            selectedProjectID: nextSelection,
            changedThreadIDs: changedThreadIDs
        )
    }

    static func selectionAfterSelectingProject(
        _ id: UUID?,
        projects: [ProjectRef],
        threads: [ChatThread]
    ) -> WorkspaceProjectSelection? {
        guard id == nil || knownProjectID(id, projects: projects) != nil else {
            return nil
        }
        return WorkspaceProjectSelection(
            projectID: id,
            threadID: newestThreadID(projectID: id, excluding: [], threads: threads)
        )
    }

    static func selectionAfterRemovingThreads(
        _ ids: [UUID],
        preferredProjectID: UUID?,
        projects: [ProjectRef],
        threads: [ChatThread]
    ) -> WorkspaceProjectSelection {
        let removedIDs = Set(ids)
        let preferredProjectID = knownProjectID(preferredProjectID, projects: projects)
        let preferred = newestThread(
            projectID: preferredProjectID,
            excluding: removedIDs,
            threads: threads
        )
        let fallback = preferred ?? newestThread(excluding: removedIDs, threads: threads)
        let selectedProjectID = knownProjectID(fallback?.projectID ?? preferredProjectID, projects: projects)
        return WorkspaceProjectSelection(projectID: selectedProjectID, threadID: fallback?.id)
    }

    @discardableResult
    static func touchProject(_ id: UUID?, projects: inout [ProjectRef], now: Date = Date()) -> Bool {
        guard let id, let index = projects.firstIndex(where: { $0.id == id }) else {
            return false
        }
        projects[index].lastOpenedAt = now
        return true
    }

    @discardableResult
    static func applyMetadata(
        _ metadata: WorkspaceProjectMetadata,
        to id: UUID?,
        projects: inout [ProjectRef],
        includeLocalExtensions: Bool,
        now: Date = Date()
    ) -> Bool {
        guard let id, let index = projects.firstIndex(where: { $0.id == id }) else {
            return false
        }
        applyInstructionMetadata(metadata.instructions, to: &projects[index], now: now)
        projects[index].memories = metadata.memories
        if includeLocalExtensions {
            projects[index].localActions = metadata.localActions
            projects[index].extensionManifests = metadata.extensionManifests
        } else {
            projects[index].localActions = []
            projects[index].extensionManifests = []
        }
        return true
    }

    private static func applyInstructionMetadata(
        _ instructions: [ProjectInstruction],
        to project: inout ProjectRef,
        now: Date
    ) {
        let previousDiagnosticIDs = instructionDiagnosticIDs(for: project.instructions)
        let currentDiagnosticIDs = instructionDiagnosticIDs(for: instructions)
        project.instructions = instructions
        for diagnosticID in previousDiagnosticIDs.subtracting(currentDiagnosticIDs).sorted() {
            project.resolveInstructionDiagnostic(id: diagnosticID, at: now)
        }
    }

    private static func instructionDiagnosticIDs(for instructions: [ProjectInstruction]) -> Set<String> {
        Set(ProjectInstructionDiagnosticsBuilder.diagnostics(for: instructions).map(\.id))
    }

    static func knownProjectID(_ id: UUID?, projects: [ProjectRef]) -> UUID? {
        guard let id, projects.contains(where: { $0.id == id }) else {
            return nil
        }
        return id
    }

    static func defaultProjectName(for url: URL) -> String {
        let lastPathComponent = url.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        return lastPathComponent.isEmpty ? url.path : lastPathComponent
    }

    static func defaultSSHProjectName(for connection: ProjectConnection) -> String {
        let pathName = URL(fileURLWithPath: connection.path).lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let host = connection.host?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let host, !host.isEmpty, !pathName.isEmpty {
            return "\(host) · \(pathName)"
        }
        if let host, !host.isEmpty {
            return host
        }
        return connection.displayLabel
    }

    private static func newestThreadID(
        projectID: UUID?,
        excluding removedIDs: Set<UUID>,
        threads: [ChatThread]
    ) -> UUID? {
        newestThread(projectID: projectID, excluding: removedIDs, threads: threads)?.id
    }

    private static func newestThread(
        projectID: UUID?,
        excluding removedIDs: Set<UUID>,
        threads: [ChatThread]
    ) -> ChatThread? {
        threads
            .lazy
            .filter { !$0.isArchived && !removedIDs.contains($0.id) && $0.projectID == projectID }
            .max { $0.updatedAt < $1.updatedAt }
    }

    private static func newestThread(
        excluding removedIDs: Set<UUID>,
        threads: [ChatThread]
    ) -> ChatThread? {
        threads
            .lazy
            .filter { !$0.isArchived && !removedIDs.contains($0.id) }
            .max { $0.updatedAt < $1.updatedAt }
    }
}
