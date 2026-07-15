import Foundation
import QuillCodeCore

/// Where a resolved skill came from. Root order is the deterministic precedence for QuillCode's
/// name-only `host.skill.load` tool; the catalog itself retains duplicate names for rich clients.
public enum SkillRootKind: String, Sendable, Hashable {
    case repo
    case user
    case admin
    case system
    /// Compatibility for callers that supplied QuillCode's former global-root label.
    case builtin

    public var protocolScope: String {
        switch self {
        case .repo: "repo"
        case .user: "user"
        case .admin: "admin"
        case .system, .builtin: "system"
        }
    }

    public var followsDirectorySymlinks: Bool {
        switch self {
        case .repo, .user, .admin: true
        case .system, .builtin: false
        }
    }
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

public struct SkillRootLocations: Sendable, Hashable {
    public var quillCodeHome: URL
    public var codexHome: URL?
    public var userHome: URL?
    public var adminSkillRoots: [URL]

    public init(
        quillCodeHome: URL,
        codexHome: URL? = nil,
        userHome: URL? = nil,
        adminSkillRoots: [URL] = []
    ) {
        self.quillCodeHome = quillCodeHome
        self.codexHome = codexHome
        self.userHome = userHome
        self.adminSkillRoots = adminSkillRoots
    }

    public static func live(
        quillCodeHome: URL,
        userHome: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> SkillRootLocations {
        SkillRootLocations(
            quillCodeHome: quillCodeHome,
            codexHome: userHome.appendingPathComponent(".codex", isDirectory: true),
            userHome: userHome,
            adminSkillRoots: [
                URL(fileURLWithPath: "/etc/quillcode/skills", isDirectory: true),
                URL(fileURLWithPath: "/etc/codex/skills", isDirectory: true)
            ]
        )
    }

    public static func isolated(quillCodeHome: URL) -> SkillRootLocations {
        SkillRootLocations(quillCodeHome: quillCodeHome)
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
    /// A matching skill directory exists, but its manifest could not be parsed or validated.
    case invalidManifest(requested: String, message: String)
    /// No skill directory with a readable `SKILL.md` matched, across every configured root. Carries
    /// the sorted list of available skill names so the caller can offer "did you mean" suggestions.
    case notFound(requested: String, available: [String])
}

/// Resolves a model-controlled skill *name* to the first matching catalog entry.
///
/// The name is untrusted, so this is deliberately strict: a skill name is a single path component
/// (`^[A-Za-z0-9._-]+$`, no `/`, no `\`, not `.`/`..`). Discovery may follow user-authored directory
/// symlinks in repo, user, and admin roots, matching Codex; callers can select only discovered names,
/// never an arbitrary path.
public struct SkillResolver: Sendable {
    /// Search roots in precedence order — earlier wins. A user root before a builtin root shadows it.
    public var roots: [SkillRoot]
    public var configuration: SkillConfiguration
    /// The manifest file every skill directory must contain.
    public static let manifestFileName = "SKILL.md"

    public init(
        roots: [SkillRoot],
        configuration: SkillConfiguration = SkillConfiguration()
    ) {
        self.roots = roots
        self.configuration = configuration
    }

    /// Codex-compatible roots plus QuillCode's legacy project/user roots. Missing directories are
    /// harmless. Repo roots are ordered nearest-first for deterministic name-only resolution.
    public static func defaultRoots(
        workspaceRoot: URL,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [SkillRoot] {
        roots(
            workspaceRoot: workspaceRoot,
            locations: .live(
                quillCodeHome: homeDirectory.appendingPathComponent(".quillcode", isDirectory: true),
                userHome: homeDirectory
            )
        )
    }

    public static func roots(
        workspaceRoot: URL,
        locations: SkillRootLocations,
        extraRoots: [URL] = []
    ) -> [SkillRoot] {
        let cwd = workspaceRoot.standardizedFileURL
        let repositoryRoot = nearestRepositoryRoot(from: cwd)
        var roots: [SkillRoot] = []

        for directory in directories(from: cwd, through: repositoryRoot) {
            roots.append(SkillRoot(
                kind: .repo,
                url: directory
                    .appendingPathComponent(".agents", isDirectory: true)
                    .appendingPathComponent("skills", isDirectory: true)
            ))
        }
        for directory in deduplicatedURLs([cwd, repositoryRoot]) {
            roots.append(SkillRoot(
                kind: .repo,
                url: directory
                    .appendingPathComponent(".quillcode", isDirectory: true)
                    .appendingPathComponent("skills", isDirectory: true)
            ))
            roots.append(SkillRoot(
                kind: .repo,
                url: directory
                    .appendingPathComponent(".codex", isDirectory: true)
                    .appendingPathComponent("skills", isDirectory: true)
            ))
        }

        roots.append(contentsOf: extraRoots.map { SkillRoot(kind: .user, url: $0) })
        if let userHome = locations.userHome {
            roots.append(SkillRoot(
                kind: .user,
                url: userHome
                    .appendingPathComponent(".agents", isDirectory: true)
                    .appendingPathComponent("skills", isDirectory: true)
            ))
        }
        roots.append(SkillRoot(
            kind: .user,
            url: locations.quillCodeHome.appendingPathComponent("skills", isDirectory: true)
        ))
        roots.append(SkillRoot(
            kind: .system,
            url: locations.quillCodeHome
                .appendingPathComponent("skills", isDirectory: true)
                .appendingPathComponent(".system", isDirectory: true)
        ))
        if let codexHome = locations.codexHome {
            roots.append(SkillRoot(
                kind: .user,
                url: codexHome.appendingPathComponent("skills", isDirectory: true)
            ))
            roots.append(SkillRoot(
                kind: .system,
                url: codexHome
                    .appendingPathComponent("skills", isDirectory: true)
                    .appendingPathComponent(".system", isDirectory: true)
            ))
        }
        roots.append(contentsOf: locations.adminSkillRoots.map { SkillRoot(kind: .admin, url: $0) })
        return deduplicatedRoots(roots)
    }

    public static func `default`(
        workspaceRoot: URL,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        configuration: SkillConfiguration = SkillConfiguration()
    ) -> SkillResolver {
        SkillResolver(
            roots: defaultRoots(workspaceRoot: workspaceRoot, homeDirectory: homeDirectory),
            configuration: configuration
        )
    }

    public func catalogSnapshot() -> SkillCatalogSnapshot {
        SkillCatalog(roots: roots).load()
    }

    /// Resolves `name` to the first root (in precedence order) that holds a skill directory with a
    /// readable `SKILL.md`. Throws `SkillResolutionError` on an unsafe name or a miss.
    public func resolve(name rawName: String) throws -> ResolvedSkill {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isSafeSkillName(name) else {
            throw SkillResolutionError.invalidName(rawName)
        }

        let snapshot = catalogSnapshot()
        if let skill = snapshot.skills.first(where: { $0.name == name && isEnabled($0) }) {
            return ResolvedSkill(
                name: skill.name,
                kind: skill.scope,
                baseDirectory: skill.path.deletingLastPathComponent(),
                skillFile: skill.path
            )
        }

        if let catalogError = snapshot.errors.first(where: {
            $0.path.deletingLastPathComponent().lastPathComponent == name
        }) {
            throw SkillResolutionError.invalidManifest(
                requested: name,
                message: catalogError.message
            )
        }

        let available = Array(Set(snapshot.skills.filter(isEnabled).map(\.name))).sorted()
        throw SkillResolutionError.notFound(requested: name, available: available)
    }

    /// Every skill name available across all roots, de-duplicated (a name present in several roots is
    /// listed once) and sorted. Used for "did you mean" suggestions and empty-state messaging.
    public func availableSkillNames() -> [String] {
        Array(Set(catalogSnapshot().skills.filter(isEnabled).map(\.name))).sorted()
    }

    public func isEnabled(_ skill: SkillCatalogMetadata) -> Bool {
        configuration.isEnabled(name: skill.name, manifestPath: skill.path)
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
    private static func nearestRepositoryRoot(from directory: URL) -> URL {
        var candidate = directory.standardizedFileURL
        while true {
            if FileManager.default.fileExists(
                atPath: candidate.appendingPathComponent(".git", isDirectory: false).path
            ) {
                return candidate
            }
            let parent = parentDirectory(of: candidate)
            guard parent.path != candidate.path else { return directory.standardizedFileURL }
            candidate = parent
        }
    }

    private static func directories(from directory: URL, through root: URL) -> [URL] {
        var directories: [URL] = []
        var candidate = directory.standardizedFileURL
        let root = root.standardizedFileURL
        while true {
            directories.append(candidate)
            guard candidate.path != root.path else { break }
            let parent = parentDirectory(of: candidate)
            guard parent.path != candidate.path else { break }
            candidate = parent
        }
        return directories
    }

    /// Foundation can represent the parent of `/` as `/..`; deriving parents from the normalized
    /// path keeps ancestor walks finite on every platform.
    private static func parentDirectory(of directory: URL) -> URL {
        let path = directory.standardizedFileURL.path
        let parentPath = NSString(string: path).deletingLastPathComponent
        return URL(
            fileURLWithPath: parentPath.isEmpty ? "/" : parentPath,
            isDirectory: true
        ).standardizedFileURL
    }

    private static func deduplicatedURLs(_ values: [URL]) -> [URL] {
        var seen = Set<String>()
        return values.filter { seen.insert($0.standardizedFileURL.path).inserted }
    }

    private static func deduplicatedRoots(_ values: [SkillRoot]) -> [SkillRoot] {
        var seen = Set<String>()
        return values.filter { seen.insert($0.url.standardizedFileURL.path).inserted }
    }
}
