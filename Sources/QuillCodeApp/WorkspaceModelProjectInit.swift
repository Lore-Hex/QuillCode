import Foundation
import QuillCodeCore
import QuillCodeTools

@MainActor
public extension QuillCodeWorkspaceModel {
    /// `/init`: scaffolds a starter `AGENTS.md` for the selected local project by scanning it
    /// (build files, languages, test commands), writing the file via `host.file.write`, and
    /// reloading instructions so it becomes the active project context. It NEVER overwrites an
    /// existing `AGENTS.md` — `host.file.write` would silently replace it, destroying the
    /// user's hand-written instructions, so the existence guard below is mandatory.
    @discardableResult
    func runInitProject(_ projectID: UUID) -> Bool {
        guard let root = activeWorkspaceRoot else {
            appendNotice("Initializing AGENTS.md is only supported for the selected local project.")
            return false
        }
        // Never clobber OR conflict with existing instructions: refuse if an AGENTS.md (file,
        // symlink — even dangling — or case-variant) is present, or the project is already
        // instructed via .quillcode/rules and friends (which load alongside AGENTS.md).
        if let existing = existingInstructionPath(at: root) {
            appendNotice("This project already has instructions (\(existing)) — edit them directly instead of running /init.")
            return false
        }

        let projectName = selectedProject?.name ?? root.lastPathComponent
        let signals = ProjectInitScanner.scan(root: root)
        let scaffold = ProjectInitScaffolder.scaffold(name: projectName, signals: signals)

        let result = runToolCall(
            ToolCall(
                name: ToolDefinition.fileWrite.name,
                argumentsJSON: ToolArguments.json(["path": "AGENTS.md", "content": scaffold])
            ),
            workspaceRoot: root
        )
        guard result.ok else {
            appendNotice(result.error ?? "Could not create AGENTS.md.")
            return false
        }

        appendNotice("Created AGENTS.md from the project's build and test commands. Edit it to add project specifics.")
        _ = refreshProjectContext(projectID)
        return true
    }

    /// A human-readable path of an instruction source already present at `root`, or nil when
    /// the project has none — so `/init` never overwrites, shadows, or conflicts with one.
    private func existingInstructionPath(at root: URL) -> String? {
        let fileManager = FileManager.default
        let agents = root.appendingPathComponent("AGENTS.md")
        // A regular file/dir at AGENTS.md (fileExists follows a live symlink to its target).
        if fileManager.fileExists(atPath: agents.path) { return "AGENTS.md" }
        // A symlink at AGENTS.md, even dangling (attributesOfItem does not follow the link).
        if let type = try? fileManager.attributesOfItem(atPath: agents.path)[.type] as? FileAttributeType,
           type == .typeSymbolicLink {
            return "AGENTS.md"
        }
        // A case-variant (e.g. agents.md on a case-sensitive volume the literal load misses).
        if let entries = try? fileManager.contentsOfDirectory(atPath: root.path),
           let match = entries.first(where: { $0.caseInsensitiveCompare("AGENTS.md") == .orderedSame }) {
            return match
        }
        // Already instructed via .quillcode/rules.md, .quillcode/instructions.md, or nested files.
        return ProjectInstructionLoader.load(from: root).first?.path
    }
}
