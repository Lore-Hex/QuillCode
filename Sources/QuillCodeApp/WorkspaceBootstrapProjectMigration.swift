import Foundation
import QuillCodeCore

enum WorkspaceBootstrapProjectMigration {
    private static let completionMarkerName = ".unused-legacy-root-project-migration-v1"

    static func completionMarkerURL(in stateDirectory: URL) -> URL {
        stateDirectory.appendingPathComponent(completionMarkerName, isDirectory: false)
    }

    static func isComplete(in stateDirectory: URL) -> Bool {
        FileManager.default.fileExists(atPath: completionMarkerURL(in: stateDirectory).path)
    }

    static func markComplete(in stateDirectory: URL) throws {
        try Data("complete\n".utf8).write(
            to: completionMarkerURL(in: stateDirectory),
            options: .atomic
        )
    }

    static func removingUnusedLegacyRootProject(
        from projects: [ProjectRef],
        threads: [ChatThread],
        hasThreadLoadIssues: Bool
    ) -> [ProjectRef] {
        guard !hasThreadLoadIssues,
              threads.isEmpty,
              projects.count == 1,
              let project = projects.first,
              isUnusedLegacyRootProject(project)
        else {
            return projects
        }
        return []
    }

    private static func isUnusedLegacyRootProject(_ project: ProjectRef) -> Bool {
        project.name == "/"
            && project.path == "/"
            && !project.isRemote
            && project.connection.path == "/"
            && project.instructions.isEmpty
            && project.instructionDiagnosticResolutions.isEmpty
            && project.localActions.isEmpty
            && project.runHooks.isEmpty
            && project.pluginHooks.isEmpty
            && project.memories.isEmpty
    }
}
