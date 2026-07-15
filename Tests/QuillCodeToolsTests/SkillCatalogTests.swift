import Foundation
import XCTest
@testable import QuillCodeTools

final class SkillCatalogTests: XCTestCase {
    private var tempRoot: URL!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("skill-catalog-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempRoot { try? FileManager.default.removeItem(at: tempRoot) }
    }

    func testParsesFrontmatterInterfaceAndToolDependencies() throws {
        let root = tempRoot.appendingPathComponent("skills", isDirectory: true)
        let skill = try makeSkill(
            in: root,
            name: "browser-use",
            description: "Drive a browser to complete web tasks.",
            shortDescription: "Browse with a controlled browser.",
            metadata: """
            interface:
              display_name: Browser Use
              short_description: Browse and interact with web pages.
              icon_small: assets/browser.svg
              brand_color: "#12ABef"
              default_prompt: Complete this browser task.
            dependencies:
              tools:
                - type: mcp
                  value: browser
                  description: Browser automation server.
                  transport: stdio
                  command: browser-mcp
            """
        )
        let assets = skill.appendingPathComponent("assets", isDirectory: true)
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        try "icon".write(
            to: assets.appendingPathComponent("browser.svg"),
            atomically: true,
            encoding: .utf8
        )

        let snapshot = SkillCatalog(roots: [SkillRoot(kind: .user, url: root)]).load()

        XCTAssertTrue(snapshot.errors.isEmpty, snapshot.errors.map(\.message).joined(separator: "\n"))
        let metadata = try XCTUnwrap(snapshot.skills.first)
        XCTAssertEqual(metadata.name, "browser-use")
        XCTAssertEqual(metadata.description, "Drive a browser to complete web tasks.")
        XCTAssertEqual(metadata.shortDescription, "Browse with a controlled browser.")
        XCTAssertEqual(metadata.scope, .user)
        XCTAssertEqual(metadata.interface?.displayName, "Browser Use")
        XCTAssertEqual(metadata.interface?.brandColor, "#12ABef")
        XCTAssertEqual(metadata.interface?.iconSmall?.lastPathComponent, "browser.svg")
        XCTAssertEqual(metadata.dependencies.first?.type, "mcp")
        XCTAssertEqual(metadata.dependencies.first?.value, "browser")
        XCTAssertEqual(metadata.dependencies.first?.transport, "stdio")
    }

    func testInvalidManifestIsReportedAndExcluded() throws {
        let root = tempRoot.appendingPathComponent("skills", isDirectory: true)
        let directory = root.appendingPathComponent("invalid", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try "# Missing frontmatter".write(
            to: directory.appendingPathComponent("SKILL.md"),
            atomically: true,
            encoding: .utf8
        )

        let snapshot = SkillCatalog(roots: [SkillRoot(kind: .repo, url: root)]).load()

        XCTAssertTrue(snapshot.skills.isEmpty)
        XCTAssertEqual(snapshot.errors.count, 1)
        XCTAssertTrue(snapshot.errors[0].message.contains("missing YAML frontmatter"))
    }

    func testSymlinkedManifestFileIsNotLoaded() throws {
        let root = tempRoot.appendingPathComponent("skills", isDirectory: true)
        let directory = root.appendingPathComponent("linked", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let outsideManifest = tempRoot.appendingPathComponent("outside-SKILL.md")
        try """
        ---
        name: linked
        description: Must remain outside discovery.
        ---
        """.write(to: outsideManifest, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(
            at: directory.appendingPathComponent("SKILL.md"),
            withDestinationURL: outsideManifest
        )

        let snapshot = SkillCatalog(roots: [SkillRoot(kind: .user, url: root)]).load()

        XCTAssertTrue(snapshot.skills.isEmpty)
    }

    func testResolverDiscoversAncestorAgentsSkillsThroughRepositoryRoot() throws {
        let repository = tempRoot.appendingPathComponent("repository", isDirectory: true)
        let workspace = repository.appendingPathComponent("Sources/Feature", isDirectory: true)
        let home = tempRoot.appendingPathComponent("home", isDirectory: true)
        try FileManager.default.createDirectory(
            at: repository.appendingPathComponent(".git", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        let skill = try makeSkill(
            in: repository.appendingPathComponent(".agents/skills", isDirectory: true),
            name: "code-review",
            description: "Review code for defects."
        )

        let resolver = SkillResolver(roots: SkillResolver.roots(
            workspaceRoot: workspace,
            locations: .isolated(quillCodeHome: home)
        ))
        let resolved = try resolver.resolve(name: "code-review")

        XCTAssertEqual(resolved.kind, .repo)
        XCTAssertEqual(resolved.baseDirectory.standardizedFileURL.path, skill.standardizedFileURL.path)
    }

    @discardableResult
    private func makeSkill(
        in root: URL,
        name: String,
        description: String,
        shortDescription: String? = nil,
        metadata: String? = nil
    ) throws -> URL {
        let directory = root.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try """
        ---
        name: \(name)
        description: \(description)
        \(shortDescription.map { "short_description: \($0)" } ?? "")
        ---

        # \(name)
        """.write(
            to: directory.appendingPathComponent("SKILL.md"),
            atomically: true,
            encoding: .utf8
        )
        if let metadata {
            let agents = directory.appendingPathComponent("agents", isDirectory: true)
            try FileManager.default.createDirectory(at: agents, withIntermediateDirectories: true)
            try metadata.write(
                to: agents.appendingPathComponent("openai.yaml"),
                atomically: true,
                encoding: .utf8
            )
        }
        return directory
    }
}
