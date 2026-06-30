import Foundation

/// Detects the project signals `ProjectInitScaffolder` needs by probing a workspace root's
/// marker files. This is the only impure piece of `/init`; the markdown generation itself is
/// pure. Bounded and deterministic (sorted, de-duped) so the scaffold stays golden-testable.
public enum ProjectInitScanner {
    private static let markerLanguages: [(marker: String, language: ProjectInitScaffolder.Language)] = [
        ("Package.swift", .swift),
        ("package.json", .node),
        ("pyproject.toml", .python),
        ("requirements.txt", .python),
        ("setup.py", .python),
        ("Cargo.toml", .rust),
        ("go.mod", .go)
    ]

    public static func scan(root: URL) -> ProjectInitScaffolder.Signals {
        let fileManager = FileManager.default
        func exists(_ name: String) -> Bool {
            fileManager.fileExists(atPath: root.appendingPathComponent(name).path)
        }

        var languages: [ProjectInitScaffolder.Language] = []
        for (marker, language) in markerLanguages where exists(marker) && !languages.contains(language) {
            languages.append(language)
        }

        return ProjectInitScaffolder.Signals(
            languages: languages,
            hasMakefile: exists("Makefile"),
            topLevelDirectories: topLevelDirectories(root: root, fileManager: fileManager)
        )
    }

    private static func topLevelDirectories(root: URL, fileManager: FileManager) -> [String] {
        let skipped: Set<String> = [".build", ".git", ".swiftpm", "node_modules", "DerivedData", "build", ".quillcode"]
        guard let entries = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        let directories = entries.compactMap { url -> String? in
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { return nil }
            let name = url.lastPathComponent
            return skipped.contains(name) ? nil : name
        }
        return Array(directories.sorted().prefix(12))
    }
}
