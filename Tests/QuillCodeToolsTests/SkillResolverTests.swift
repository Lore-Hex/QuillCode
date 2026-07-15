import XCTest
import QuillCodeCore
@testable import QuillCodeTools

final class SkillResolverTests: XCTestCase {
    private var tempRoot: URL!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("skill-resolver-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempRoot {
            try? FileManager.default.removeItem(at: tempRoot)
        }
    }

    // MARK: - Fixture helpers

    private func makeSkill(
        in root: URL,
        name: String,
        manifest: String = "# Skill\n",
        extraFiles: [String: String] = [:]
    ) throws {
        let dir = root.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try skillManifest(name: name, body: manifest).write(
            to: dir.appendingPathComponent("SKILL.md"),
            atomically: true,
            encoding: .utf8
        )
        for (relative, contents) in extraFiles {
            let fileURL = dir.appendingPathComponent(relative)
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try contents.write(to: fileURL, atomically: true, encoding: .utf8)
        }
    }

    private func skillManifest(name: String, body: String) -> String {
        """
        ---
        name: \(name)
        description: Test instructions for \(name).
        ---

        \(body)
        """
    }

    private func resolver(user: URL? = nil, builtin: URL? = nil) -> SkillResolver {
        var roots: [SkillRoot] = []
        if let user { roots.append(SkillRoot(kind: .user, url: user)) }
        if let builtin { roots.append(SkillRoot(kind: .builtin, url: builtin)) }
        return SkillResolver(roots: roots)
    }

    // MARK: - Resolution

    func testResolvesBuiltinSkill() throws {
        let builtin = tempRoot.appendingPathComponent("builtin", isDirectory: true)
        try makeSkill(in: builtin, name: "code-review", manifest: "# Code Review\nDo the thing.\n")

        let resolved = try resolver(user: tempRoot.appendingPathComponent("user"), builtin: builtin)
            .resolve(name: "code-review")

        XCTAssertEqual(resolved.name, "code-review")
        XCTAssertEqual(resolved.kind, .builtin)
        XCTAssertEqual(
            resolved.baseDirectory.standardizedFileURL.path,
            builtin.appendingPathComponent("code-review").standardizedFileURL.path
        )
        XCTAssertEqual(resolved.skillFile.lastPathComponent, "SKILL.md")
    }

    func testUserSkillShadowsBuiltinOfSameName() throws {
        let user = tempRoot.appendingPathComponent("user", isDirectory: true)
        let builtin = tempRoot.appendingPathComponent("builtin", isDirectory: true)
        try makeSkill(in: user, name: "review", manifest: "# User review\n")
        try makeSkill(in: builtin, name: "review", manifest: "# Builtin review\n")

        let resolved = try resolver(user: user, builtin: builtin).resolve(name: "review")

        XCTAssertEqual(resolved.kind, .user, "user root wins because it is ordered first")
        XCTAssertEqual(
            resolved.baseDirectory.standardizedFileURL.path,
            user.appendingPathComponent("review").standardizedFileURL.path
        )
    }

    func testFallsThroughToBuiltinWhenUserMissing() throws {
        let user = tempRoot.appendingPathComponent("user", isDirectory: true)
        let builtin = tempRoot.appendingPathComponent("builtin", isDirectory: true)
        try FileManager.default.createDirectory(at: user, withIntermediateDirectories: true)
        try makeSkill(in: builtin, name: "only-builtin")

        let resolved = try resolver(user: user, builtin: builtin).resolve(name: "only-builtin")
        XCTAssertEqual(resolved.kind, .builtin)
    }

    func testDefaultRootsOutsideRepositoryTerminateAtWorkspace() throws {
        let workspace = tempRoot.appendingPathComponent("workspace", isDirectory: true)
        let home = tempRoot.appendingPathComponent("home", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)

        let roots = SkillResolver.defaultRoots(workspaceRoot: workspace, homeDirectory: home)

        XCTAssertEqual(roots.first?.kind, .repo)
        XCTAssertEqual(
            roots.first?.url.standardizedFileURL.path,
            workspace.appendingPathComponent(".agents/skills", isDirectory: true).standardizedFileURL.path
        )
    }

    // MARK: - Missing / invalid

    func testMissingSkillThrowsNotFoundWithAvailableList() throws {
        let user = tempRoot.appendingPathComponent("user", isDirectory: true)
        try makeSkill(in: user, name: "alpha")
        try makeSkill(in: user, name: "beta")

        XCTAssertThrowsError(try resolver(user: user).resolve(name: "gamma")) { error in
            guard case let SkillResolutionError.notFound(requested, available) = error else {
                return XCTFail("expected notFound, got \(error)")
            }
            XCTAssertEqual(requested, "gamma")
            XCTAssertEqual(available, ["alpha", "beta"])
        }
    }

    func testAvailableSkillNamesDeduplicatesAcrossRoots() throws {
        let user = tempRoot.appendingPathComponent("user", isDirectory: true)
        let builtin = tempRoot.appendingPathComponent("builtin", isDirectory: true)
        try makeSkill(in: user, name: "shared")
        try makeSkill(in: builtin, name: "shared")
        try makeSkill(in: builtin, name: "extra")

        XCTAssertEqual(resolver(user: user, builtin: builtin).availableSkillNames(), ["extra", "shared"])
    }

    func testDirectoryWithoutManifestIsNotASkill() throws {
        let user = tempRoot.appendingPathComponent("user", isDirectory: true)
        let dir = user.appendingPathComponent("no-manifest", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "not a manifest".write(
            to: dir.appendingPathComponent("README.md"),
            atomically: true,
            encoding: .utf8
        )

        XCTAssertThrowsError(try resolver(user: user).resolve(name: "no-manifest"))
        XCTAssertFalse(resolver(user: user).availableSkillNames().contains("no-manifest"))
    }

    // MARK: - Path-traversal / injection defense

    func testRejectsPathTraversalNames() {
        let user = tempRoot.appendingPathComponent("user", isDirectory: true)
        let resolver = resolver(user: user)
        for name in ["../secret", "..", ".", "a/b", "foo/../bar", "sub/skill", "a\\b", "with space"] {
            XCTAssertThrowsError(try resolver.resolve(name: name), "should reject \(name)") { error in
                guard case SkillResolutionError.invalidName = error else {
                    return XCTFail("expected invalidName for \(name), got \(error)")
                }
            }
        }
    }

    func testRejectsAbsolutePathName() {
        let resolver = resolver(user: tempRoot.appendingPathComponent("user"))
        XCTAssertThrowsError(try resolver.resolve(name: "/etc/passwd")) { error in
            guard case SkillResolutionError.invalidName = error else {
                return XCTFail("expected invalidName, got \(error)")
            }
        }
    }

    func testAbsoluteTraversalNameCannotEscapeRoot() throws {
        // Place a "secret" SKILL.md OUTSIDE the user root; a crafted name must never reach it.
        let outside = tempRoot.appendingPathComponent("outside", isDirectory: true)
        try makeSkill(in: outside, name: "loot", manifest: "# secret\n")
        let user = tempRoot.appendingPathComponent("user", isDirectory: true)
        try FileManager.default.createDirectory(at: user, withIntermediateDirectories: true)

        // Even URL-ish traversal attempts are rejected at the name gate before any filesystem walk.
        XCTAssertThrowsError(try resolver(user: user).resolve(name: "../outside/loot"))
    }

    func testUserRootFollowsSymlinkedSkillDirectory() throws {
        let user = tempRoot.appendingPathComponent("user", isDirectory: true)
        try FileManager.default.createDirectory(at: user, withIntermediateDirectories: true)
        let outside = tempRoot.appendingPathComponent("outside-skill", isDirectory: true)
        try makeSkill(in: outside.deletingLastPathComponent(), name: "outside-skill")

        // A symlink INSIDE the root, named like a skill, pointing at a real skill dir outside the root.
        let link = user.appendingPathComponent("escape", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)

        let resolved = try resolver(user: user).resolve(name: "outside-skill")
        XCTAssertEqual(resolved.baseDirectory.standardizedFileURL.path, outside.standardizedFileURL.path)
    }

    func testSystemRootDoesNotFollowSymlinkedSkillDirectory() throws {
        let system = tempRoot.appendingPathComponent("system", isDirectory: true)
        try FileManager.default.createDirectory(at: system, withIntermediateDirectories: true)
        let outside = tempRoot.appendingPathComponent("outside-system-skill", isDirectory: true)
        try makeSkill(in: outside.deletingLastPathComponent(), name: "outside-system-skill")
        try FileManager.default.createSymbolicLink(
            at: system.appendingPathComponent("escape", isDirectory: true),
            withDestinationURL: outside
        )

        let resolver = SkillResolver(roots: [SkillRoot(kind: .system, url: system)])
        XCTAssertThrowsError(try resolver.resolve(name: "outside-system-skill"))
    }

    func testIsSafeSkillName() {
        XCTAssertTrue(SkillResolver.isSafeSkillName("code-review"))
        XCTAssertTrue(SkillResolver.isSafeSkillName("my_skill.v2"))
        XCTAssertTrue(SkillResolver.isSafeSkillName("Skill123"))
        XCTAssertFalse(SkillResolver.isSafeSkillName(""))
        XCTAssertFalse(SkillResolver.isSafeSkillName("."))
        XCTAssertFalse(SkillResolver.isSafeSkillName(".."))
        XCTAssertFalse(SkillResolver.isSafeSkillName("a/b"))
        XCTAssertFalse(SkillResolver.isSafeSkillName("a b"))
        XCTAssertFalse(SkillResolver.isSafeSkillName("a\u{0}b"))
        XCTAssertFalse(SkillResolver.isSafeSkillName(String(repeating: "a", count: 129)))
    }
}
