import Foundation
import QuillCodeCore

/// Where a resolved skill came from. `user` roots shadow `builtin` roots of the same name, so the
/// caller orders `SkillResolver.roots` user-first and the resolver returns the first match.
public enum SkillRootKind: String, Sendable, Hashable {
    /// A project (or otherwise user-owned) skills directory — e.g. `<workspace>/.quillcode/skills`.
    case user
    /// A shared/global skills directory — e.g. `~/.quillcode/skills`.
    case builtin
}

/// One skills directory to search, and what kind it is. Ordering in `SkillResolver.roots` is the
/// precedence: earlier roots win, so a user root placed before a builtin root shadows it.
public struct SkillRoot: Sendable, Hashable {
    public var kind: SkillRootKind
    public var url: URL

    public init(kind: SkillRootKind, url: URL) {
        self.kind = kind
        self.url = url
    }
}

/// A skill successfully resolved on disk: its canonical directory, the `SKILL.md` inside it, and
/// which root it came from.
public struct ResolvedSkill: Sendable, Hashable {
    /// The canonical (symlink-resolved) name — the skill's directory basename.
    public var name: String
    public var kind: SkillRootKind
    /// Absolute path to the skill's base directory.
    public var baseDirectory: URL
    /// Absolute path to `SKILL.md` inside the base directory.
    public var skillFile: URL

    public init(name: String, kind: SkillRootKind, baseDirectory: URL, skillFile: URL) {
        self.name = name
        self.kind = kind
        self.baseDirectory = baseDirectory
        self.skillFile = skillFile
    }
}

/// Why a skill name could not be resolved. Carries enough context for an actionable tool error.
public enum SkillResolutionError: Error, Sendable, Equatable {
    /// The name was empty, or contained a path separator / `..` / other unsafe component. The name is
    /// model-controlled, so this is the gate that keeps resolution inside the known skill roots.
    case invalidName(String)
    /// No skill directory with a readable `SKILL.md` matched, across every configured root. Carries
    /// the sorted list of available skill names so the caller can offer "did you mean" suggestions.
    case notFound(requested: String, available: [String])
}

/// Resolves a model-controlled skill *name* to an on-disk skill with user-shadows-builtin precedence.
///
/// The name is untrusted, so this is deliberately strict: a skill name is a single path component
/// (`^[A-Za-z0-9._-]+$`, no `/`, no `\`, not `.`/`..`), it is joined onto each known root, and the
/// resolved directory must still live *inside* that root (a symlink pointing out is rejected via
/// `WorkspaceBoundary`). There is no way for a name to escape the configured roots — absolute paths,
/// `../`, and separator injection are all refused before any filesystem access that could leave a root.
public struct SkillResolver: Sendable {
    /// Search roots in precedence order — earlier wins. A user root before a builtin root shadows it.
    public var roots: [SkillRoot]
    /// The manifest file every skill directory must contain.
    public static let manifestFileName = "SKILL.md"

    public init(roots: [SkillRoot]) {
        self.roots = roots
    }

    /// The default roots for a workspace: the project `.quillcode/skills` (user, wins) then
    /// `~/.quillcode/skills` (builtin/global, shadowed). Missing directories are harmless — they
    /// simply contribute no skills.
    public static func defaultRoots(
        workspaceRoot: URL,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [SkillRoot] {
        [
            SkillRoot(
                kind: .user,
                url: workspaceRoot
                    .appendingPathComponent(".quillcode", isDirectory: true)
                    .appendingPathComponent("skills", isDirectory: true)
            ),
            SkillRoot(
                kind: .builtin,
                url: homeDirectory
                    .appendingPathComponent(".quillcode", isDirectory: true)
                    .appendingPathComponent("skills", isDirectory: true)
            )
        ]
    }

    public static func `default`(
        workspaceRoot: URL,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> SkillResolver {
        SkillResolver(roots: defaultRoots(workspaceRoot: workspaceRoot, homeDirectory: homeDirectory))
    }

    /// Resolves `name` to the first root (in precedence order) that holds a skill directory with a
    /// readable `SKILL.md`. Throws `SkillResolutionError` on an unsafe name or a miss.
    public func resolve(name rawName: String) throws -> ResolvedSkill {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isSafeSkillName(name) else {
            throw SkillResolutionError.invalidName(rawName)
        }

        for root in roots {
            let rootURL = root.url.standardizedFileURL
            let candidate = rootURL.appendingPathComponent(name, isDirectory: true).standardizedFileURL
            // The joined directory must still live inside its root — a symlink named like a skill that
            // points outside the root is not a skill of this root.
            guard WorkspaceBoundary.isWithin(candidate, root: rootURL) else {
                continue
            }
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory),
                  isDirectory.boolValue
            else {
                continue
            }
            let manifest = candidate.appendingPathComponent(Self.manifestFileName, isDirectory: false)
            var manifestIsDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: manifest.path, isDirectory: &manifestIsDirectory),
                  !manifestIsDirectory.boolValue,
                  // The manifest itself must resolve inside the root too (defends against a symlinked
                  // SKILL.md pointing at an arbitrary file on disk).
                  WorkspaceBoundary.isWithin(manifest, root: rootURL)
            else {
                continue
            }
            return ResolvedSkill(
                name: name,
                kind: root.kind,
                baseDirectory: candidate,
                skillFile: manifest
            )
        }

        throw SkillResolutionError.notFound(requested: name, available: availableSkillNames())
    }

    /// Every skill name available across all roots, de-duplicated (a name present in several roots is
    /// listed once) and sorted. Used for "did you mean" suggestions and empty-state messaging.
    public func availableSkillNames() -> [String] {
        var names: Set<String> = []
        for root in roots {
            let rootURL = root.url.standardizedFileURL
            let entries = (try? FileManager.default.contentsOfDirectory(
                at: rootURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )) ?? []
            for entry in entries {
                let dir = entry.standardizedFileURL
                guard WorkspaceBoundary.isWithin(dir, root: rootURL) else { continue }
                var isDirectory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDirectory),
                      isDirectory.boolValue
                else {
                    continue
                }
                let manifest = dir.appendingPathComponent(Self.manifestFileName, isDirectory: false)
                if FileManager.default.fileExists(atPath: manifest.path) {
                    names.insert(dir.lastPathComponent)
                }
            }
        }
        return names.sorted()
    }

    /// A skill name is exactly one safe path component: non-empty, not `.`/`..`, no path separators,
    /// no NUL, and only ASCII letters/digits and `._-`. This is the choke point that keeps a
    /// model-controlled name from ever naming a path outside a root.
    public static func isSafeSkillName(_ name: String) -> Bool {
        guard !name.isEmpty, name.count <= 128 else { return false }
        guard name != ".", name != ".." else { return false }
        guard !name.contains("/"), !name.contains("\\"), !name.contains("\0") else { return false }
        return name.allSatisfy { character in
            character.isASCII &&
                (character.isLetter || character.isNumber || character == "." || character == "-" || character == "_")
        }
    }
}
