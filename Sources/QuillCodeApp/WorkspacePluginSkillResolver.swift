import Foundation
import QuillCodeCore
import QuillCodeTools

enum WorkspacePluginSkillResolver {
    static func make(
        workspaceRoot: URL,
        manifests: [ProjectExtensionManifest],
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> SkillResolver {
        let defaults = SkillResolver.defaultRoots(
            workspaceRoot: workspaceRoot,
            homeDirectory: homeDirectory
        )
        let pluginRoots = roots(
            workspaceRoot: workspaceRoot,
            manifests: manifests
        )
        guard let first = defaults.first else {
            return SkillResolver(roots: pluginRoots)
        }
        return SkillResolver(roots: [first] + pluginRoots + defaults.dropFirst())
    }

    private static func roots(
        workspaceRoot: URL,
        manifests: [ProjectExtensionManifest]
    ) -> [SkillRoot] {
        let root = workspaceRoot.standardizedFileURL.resolvingSymlinksInPath()
        var seen = Set<String>()
        return manifests
            .filter { $0.kind == .plugin && $0.isEnabled }
            .flatMap { $0.skillDirectoryRelativePaths ?? [] }
            .compactMap { relativePath in
                guard let directory = resolveDirectory(relativePath, inside: root),
                      seen.insert(directory.path).inserted
                else { return nil }
                return SkillRoot(kind: .user, url: directory)
            }
    }

    private static func resolveDirectory(_ relativePath: String, inside root: URL) -> URL? {
        let components = relativePath
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "/", omittingEmptySubsequences: false)
            .map(String.init)
        guard !components.isEmpty,
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." })
        else { return nil }

        let candidate = components.reduce(root) { url, component in
            url.appendingPathComponent(component, isDirectory: true)
        }.standardizedFileURL.resolvingSymlinksInPath()
        let values = try? candidate.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard WorkspaceBoundary.isWithin(candidate, root: root),
              values?.isDirectory == true,
              values?.isSymbolicLink != true
        else { return nil }
        return candidate
    }
}
