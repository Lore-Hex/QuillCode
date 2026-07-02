import Foundation
import QuillCodeCore

/// Executes `host.skill.load`: resolve a skill name (user shadows builtin), read its `SKILL.md`, and
/// return a `<skill_content>` block carrying the skill's base directory (absolute), a listing of the
/// files inside it, and the `SKILL.md` body. The model then references those files by absolute path
/// with the ordinary file tools.
///
/// This tool LOADS skill content into context — it does not execute any skill code. It is `risk: .read`.
public struct SkillLoadToolExecutor: Sendable {
    public var resolver: SkillResolver
    /// Byte ceiling on the injected `SKILL.md` body (ShellOutputCapper precedent).
    public var manifestMaxBytes: Int
    /// Line ceiling on the injected `SKILL.md` body.
    public var manifestMaxLines: Int
    /// Cap on how many files are listed under the skill directory, to keep the block bounded.
    public var maxListedFiles: Int

    public init(
        resolver: SkillResolver,
        manifestMaxBytes: Int = SkillLoadToolExecutor.defaultManifestMaxBytes,
        manifestMaxLines: Int = SkillLoadToolExecutor.defaultManifestMaxLines,
        maxListedFiles: Int = SkillLoadToolExecutor.defaultMaxListedFiles
    ) {
        self.resolver = resolver
        self.manifestMaxBytes = max(1024, manifestMaxBytes)
        self.manifestMaxLines = max(1, manifestMaxLines)
        self.maxListedFiles = max(1, maxListedFiles)
    }

    public static let defaultManifestMaxBytes = 48_000
    public static let defaultManifestMaxLines = 2_000
    public static let defaultMaxListedFiles = 200

    /// Convenience for the default project + home roots.
    public static func `default`(
        workspaceRoot: URL,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> SkillLoadToolExecutor {
        SkillLoadToolExecutor(resolver: .default(workspaceRoot: workspaceRoot, homeDirectory: homeDirectory))
    }

    public func load(name: String) -> ToolResult {
        let skill: ResolvedSkill
        do {
            skill = try resolver.resolve(name: name)
        } catch let error as SkillResolutionError {
            return ToolResult(ok: false, error: Self.message(for: error))
        } catch {
            return ToolResult(ok: false, error: String(describing: error))
        }

        // Read the manifest. A directory-with-SKILL.md that is unreadable (permissions) or invalid
        // UTF-8 is an actionable failure, not a crash.
        guard let data = try? Data(contentsOf: skill.skillFile) else {
            return ToolResult(ok: false, error: """
            Found skill `\(skill.name)` at \(skill.baseDirectory.path) but could not read its \
            \(SkillResolver.manifestFileName). Check the file's permissions.
            """)
        }
        guard let rawBody = String(data: data, encoding: .utf8) else {
            return ToolResult(ok: false, error: """
            Skill `\(skill.name)`'s \(SkillResolver.manifestFileName) at \(skill.skillFile.path) is not \
            valid UTF-8 text and cannot be loaded.
            """)
        }

        // Keep the HEAD of SKILL.md — its title, purpose, and leading instructions are what matter;
        // WebFetchMarkdownCapper is the head-keeping capper (ShellOutputCapper keeps the tail).
        let capped = WebFetchMarkdownCapper.cap(rawBody, maxLines: manifestMaxLines, maxBytes: manifestMaxBytes)
        let listing = fileListing(for: skill.baseDirectory)

        let content = Self.renderSkillContent(
            skill: skill,
            manifestBody: capped.text,
            manifestTruncated: capped.truncated,
            files: listing.files,
            fileCountTruncated: listing.truncated,
            totalFileCount: listing.total
        )

        let sourceLabel = skill.kind == .user ? "user" : "builtin"
        let summary = "Loaded \(sourceLabel) skill `\(skill.name)` from \(skill.baseDirectory.path)."
        return ToolResult(ok: true, stdout: summary + "\n\n" + content)
    }

    // MARK: - File listing

    private struct FileListing {
        var files: [String]
        var total: Int
        var truncated: Bool
    }

    /// Files under the skill's base directory, as paths relative to that directory, sorted, capped.
    /// A deterministic recursive walk (skipping hidden entries) so the model sees exactly what it can
    /// then read by absolute path. Symlinks are listed by name but not followed.
    private func fileListing(for baseDirectory: URL) -> FileListing {
        let fileManager = FileManager.default
        var relativePaths: [String] = []
        var total = 0
        let basePath = baseDirectory.standardizedFileURL.path
        let prefix = basePath.hasSuffix("/") ? basePath : basePath + "/"

        guard let enumerator = fileManager.enumerator(
            at: baseDirectory,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
            options: [.skipsHiddenFiles],
            errorHandler: { _, _ in true }
        ) else {
            return FileListing(files: [], total: 0, truncated: false)
        }

        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey])
            guard values?.isRegularFile == true else { continue }
            total += 1
            guard relativePaths.count < maxListedFiles else { continue }
            let path = fileURL.standardizedFileURL.path
            let relative = path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : fileURL.lastPathComponent
            relativePaths.append(relative)
        }

        relativePaths.sort()
        return FileListing(files: relativePaths, total: total, truncated: total > relativePaths.count)
    }

    // MARK: - Rendering

    /// Builds the `<skill_content>` block: base dir (absolute) + file listing + the `SKILL.md` body.
    static func renderSkillContent(
        skill: ResolvedSkill,
        manifestBody: String,
        manifestTruncated: Bool,
        files: [String],
        fileCountTruncated: Bool,
        totalFileCount: Int
    ) -> String {
        var lines: [String] = []
        lines.append("<skill_content name=\"\(skill.name)\" source=\"\(skill.kind.rawValue)\">")
        lines.append("Base directory (absolute): \(skill.baseDirectory.path)")
        lines.append("Reference any file below by its absolute path, e.g. \(skill.baseDirectory.path)/<relative-path>.")
        lines.append("")
        if files.isEmpty {
            lines.append("Files: (none besides \(SkillResolver.manifestFileName))")
        } else {
            let shown = files.count
            let header = fileCountTruncated
                ? "Files (\(shown) of \(totalFileCount), relative to the base directory):"
                : "Files (\(totalFileCount), relative to the base directory):"
            lines.append(header)
            for file in files {
                lines.append("- \(file)")
            }
            if fileCountTruncated {
                lines.append("- … \(totalFileCount - shown) more (list \(skill.baseDirectory.path) for the rest)")
            }
        }
        lines.append("")
        lines.append("--- \(SkillResolver.manifestFileName) ---")
        lines.append(manifestBody)
        if manifestTruncated {
            lines.append("")
            lines.append("[\(SkillResolver.manifestFileName) truncated — read \(skill.skillFile.path) directly for the full text]")
        }
        lines.append("</skill_content>")
        return lines.joined(separator: "\n")
    }

    // MARK: - Errors

    static func message(for error: SkillResolutionError) -> String {
        switch error {
        case .invalidName(let name):
            return """
            `\(name)` is not a valid skill name. Pass a bare skill name (letters, digits, `.`, `-`, `_`) \
            such as `code-review` — not a path, and no `/` or `..`.
            """
        case .notFound(let requested, let available):
            if available.isEmpty {
                return """
                No skill named `\(requested)` is available, and no skills are installed. Add a skill under \
                .quillcode/skills/<name>/\(SkillResolver.manifestFileName).
                """
            }
            let suggestions = FilePathSuggester.suggest(missing: requested, candidates: available, limit: 3)
            let suggestionText: String
            if suggestions.isEmpty {
                suggestionText = ""
            } else {
                let quoted = suggestions.map { "`\($0)`" }.joined(separator: ", ")
                suggestionText = " Did you mean \(quoted)?"
            }
            let listed = available.prefix(20).map { "`\($0)`" }.joined(separator: ", ")
            let more = available.count > 20 ? ", … (\(available.count - 20) more)" : ""
            return "No skill named `\(requested)`.\(suggestionText) Available skills: \(listed)\(more)."
        }
    }
}
