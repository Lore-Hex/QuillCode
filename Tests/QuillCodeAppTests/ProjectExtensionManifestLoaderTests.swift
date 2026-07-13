import XCTest
import QuillCodeCore
@testable import QuillCodeApp

final class ProjectExtensionManifestLoaderTests: XCTestCase {
    func testLoadsKindsAndRejectsUnsafeFiles() throws {
        let root = try makeQuillCodeTestDirectory()
        let pluginDirectory = root.appendingPathComponent(".quillcode/plugins")
        let skillDirectory = root.appendingPathComponent(".quillcode/skills")
        let mcpDirectory = root.appendingPathComponent(".quillcode/mcp")
        try FileManager.default.createDirectory(at: pluginDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: skillDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: mcpDirectory, withIntermediateDirectories: true)

        try #"{"id":"github","name":"GitHub","description":"PR and issue helpers.","version":"1.2.0","source":"https://github.com/Lore-Hex/quillcode-github","installCommand":"git clone https://github.com/Lore-Hex/quillcode-github .quillcode/plugins/github","installTimeoutSeconds":600,"updateCommand":"git -C .quillcode/plugins/github pull --ff-only","updateTimeoutSeconds":300}"#.write(
            to: pluginDirectory.appendingPathComponent("github.json"),
            atomically: true,
            encoding: .utf8
        )
        try #"{"id":"review","name":"Code Review","summary":"Review defects first.","enabled":false}"#.write(
            to: skillDirectory.appendingPathComponent("review.json"),
            atomically: true,
            encoding: .utf8
        )
        try #"{"id":"filesystem","name":"Filesystem MCP","command":"quill-mcp","args":["--root","."]}"#.write(
            to: mcpDirectory.appendingPathComponent("filesystem.json"),
            atomically: true,
            encoding: .utf8
        )
        try #"{"id":"broken""#.write(
            to: pluginDirectory.appendingPathComponent("broken.json"),
            atomically: true,
            encoding: .utf8
        )
        let outside = try makeQuillCodeTestDirectory().appendingPathComponent("outside.json")
        try #"{"id":"outside","name":"Outside"}"#.write(to: outside, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(
            at: pluginDirectory.appendingPathComponent("outside.json"),
            withDestinationURL: outside
        )

        let manifests = ProjectExtensionManifestLoader.load(from: root)

        XCTAssertEqual(manifests.map(\.id), [
            "plugin:github",
            "skill:review",
            "mcp_server:filesystem"
        ])
        XCTAssertEqual(manifests.map(\.kind), [.plugin, .skill, .mcpServer])
        XCTAssertEqual(manifests[0].summary, "PR and issue helpers.")
        XCTAssertEqual(manifests[0].version, "1.2.0")
        XCTAssertEqual(manifests[0].sourceURL, "https://github.com/Lore-Hex/quillcode-github")
        XCTAssertEqual(
            manifests[0].installCommand,
            "git clone https://github.com/Lore-Hex/quillcode-github .quillcode/plugins/github"
        )
        XCTAssertEqual(manifests[0].installTimeoutSeconds, 600)
        XCTAssertEqual(manifests[0].updateCommand, "git -C .quillcode/plugins/github pull --ff-only")
        XCTAssertEqual(manifests[0].updateTimeoutSeconds, 300)
        XCTAssertEqual(manifests[1].isEnabled, false)
        XCTAssertEqual(manifests[2].transport, .stdio)
        XCTAssertEqual(manifests[2].launchExecutable, "quill-mcp")
        XCTAssertEqual(manifests[2].launchCommand, "quill-mcp --root .")
        XCTAssertEqual(manifests[2].launchArguments, ["--root", "."])
    }

    func testSkipsUnsafeCustomDirectoriesWithoutStoppingScan() throws {
        let root = try makeQuillCodeTestDirectory()
        let safeDirectory = root.appendingPathComponent(".quillcode/plugins")
        try FileManager.default.createDirectory(at: safeDirectory, withIntermediateDirectories: true)
        try #"{"id":"github","name":"GitHub"}"#.write(
            to: safeDirectory.appendingPathComponent("github.json"),
            atomically: true,
            encoding: .utf8
        )

        let manifests = ProjectExtensionManifestLoader.load(
            from: root,
            directories: [
                ("../outside", .plugin),
                ("/absolute", .skill),
                (".quillcode/./mcp", .mcpServer),
                (".quillcode/plugins", .plugin)
            ]
        )

        XCTAssertEqual(manifests.map(\.id), ["plugin:github"])
        XCTAssertEqual(manifests.map(\.relativePath), [".quillcode/plugins/github.json"])
    }

    func testSkipsSymlinkedDirectoryOutsideProject() throws {
        let root = try makeQuillCodeTestDirectory()
        let quillCodeDirectory = root.appendingPathComponent(".quillcode")
        let outsideDirectory = try makeQuillCodeTestDirectory().appendingPathComponent("plugins")
        try FileManager.default.createDirectory(at: quillCodeDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outsideDirectory, withIntermediateDirectories: true)
        try #"{"id":"outside","name":"Outside"}"#.write(
            to: outsideDirectory.appendingPathComponent("outside.json"),
            atomically: true,
            encoding: .utf8
        )
        try FileManager.default.createSymbolicLink(
            at: quillCodeDirectory.appendingPathComponent("plugins"),
            withDestinationURL: outsideDirectory
        )

        let manifests = ProjectExtensionManifestLoader.load(from: root)

        XCTAssertTrue(manifests.isEmpty)
    }

    func testFallsBackToFilenameForBlankOrMissingName() throws {
        let root = try makeQuillCodeTestDirectory()
        let pluginDirectory = root.appendingPathComponent(".quillcode/plugins")
        try FileManager.default.createDirectory(at: pluginDirectory, withIntermediateDirectories: true)
        try #"{"id":"code-review","name":"   "}"#.write(
            to: pluginDirectory.appendingPathComponent("code-review.json"),
            atomically: true,
            encoding: .utf8
        )
        try #"{"id":"issue-triage"}"#.write(
            to: pluginDirectory.appendingPathComponent("issue-triage.json"),
            atomically: true,
            encoding: .utf8
        )

        let manifests = ProjectExtensionManifestLoader.load(from: root)

        XCTAssertEqual(manifests.map(\.name), ["Code Review", "Issue Triage"])
    }

    func testLoadsMarketplaceEntriesAndFiltersInstalledExtensions() throws {
        let root = try makeQuillCodeTestDirectory()
        let marketplaceDirectory = root.appendingPathComponent(".quillcode/marketplace")
        try FileManager.default.createDirectory(at: marketplaceDirectory, withIntermediateDirectories: true)
        try #"{"id":"github","kind":"plugin","name":"GitHub","description":"PR helpers.","version":"1.2.0","source":"https://github.com/Lore-Hex/quillcode-github","installCommand":"git clone https://github.com/Lore-Hex/quillcode-github .quillcode/plugins/github","installTimeoutSeconds":600}"#.write(
            to: marketplaceDirectory.appendingPathComponent("github.json"),
            atomically: true,
            encoding: .utf8
        )
        try #"{"id":"review","kind":"skill","name":"Code Review","summary":"Review defects first."}"#.write(
            to: marketplaceDirectory.appendingPathComponent("review.json"),
            atomically: true,
            encoding: .utf8
        )
        try #"{"id":"bad","kind":"unknown","name":"Bad"}"#.write(
            to: marketplaceDirectory.appendingPathComponent("bad.json"),
            atomically: true,
            encoding: .utf8
        )

        let manifests = ProjectExtensionManifestLoader.loadMarketplace(
            from: root,
            installedManifests: [
                ProjectExtensionManifest(
                    id: "plugin:github",
                    kind: .plugin,
                    name: "GitHub",
                    relativePath: ".quillcode/plugins/github.json"
                )
            ]
        )

        XCTAssertEqual(manifests.map(\.id), ["skill:review"])
        XCTAssertEqual(manifests.map(\.kind), [.skill])
        XCTAssertEqual(manifests.map(\.relativePath), [".quillcode/marketplace/review.json"])
    }

    func testBundledMarketplaceIncludesBurstyRouterAndFiltersClaimedID() {
        let manifests = BundledExtensionMarketplace.availableManifests(excluding: [])
        let burstyRouter = manifests.first { $0.id == "skill:burstyrouter" }

        XCTAssertEqual(burstyRouter?.kind, .skill)
        XCTAssertEqual(burstyRouter?.name, "BurstyRouter")
        XCTAssertEqual(
            burstyRouter?.summary,
            "Local-first LLM routing to a local server with burst overflow to TrustedRouter Cloud."
        )
        XCTAssertEqual(burstyRouter?.sourceURL, "https://github.com/Lore-Hex/BurstyRouter")
        XCTAssertEqual(burstyRouter?.relativePath, ".quillcode/marketplace/burstyrouter.json")

        let installed = ProjectExtensionManifest(
            id: "skill:burstyrouter",
            kind: .skill,
            name: "BurstyRouter",
            relativePath: ".quillcode/skills/burstyrouter.json"
        )
        XCTAssertFalse(BundledExtensionMarketplace.availableManifests(excluding: [installed]).contains {
            $0.id == "skill:burstyrouter"
        })

        let projectMarketplace = ProjectExtensionManifest(
            id: "skill:burstyrouter",
            kind: .skill,
            name: "Custom BurstyRouter",
            relativePath: ".quillcode/marketplace/burstyrouter.json"
        )
        XCTAssertFalse(BundledExtensionMarketplace.availableManifests(excluding: [projectMarketplace]).contains {
            $0.id == "skill:burstyrouter"
        })
    }

    func testLoadsRemoteHTTPMCPServerWithURLAndHeaders() throws {
        let root = try makeQuillCodeTestDirectory()
        let mcpDirectory = root.appendingPathComponent(".quillcode/mcp")
        try FileManager.default.createDirectory(at: mcpDirectory, withIntermediateDirectories: true)

        // A URL with no explicit transport infers `http`; headers and oauth_client_id come through.
        try #"{"id":"remote","name":"Remote MCP","url":"https://mcp.example.com/mcp","headers":{"X-Api-Key":"secret"},"oauth_client_id":"client-123"}"#.write(
            to: mcpDirectory.appendingPathComponent("remote.json"),
            atomically: true,
            encoding: .utf8
        )
        // An explicit sse transport is preserved.
        try #"{"id":"legacy","name":"Legacy MCP","transport":"sse","url":"https://mcp.example.com/sse"}"#.write(
            to: mcpDirectory.appendingPathComponent("legacy.json"),
            atomically: true,
            encoding: .utf8
        )

        let manifests = ProjectExtensionManifestLoader.load(from: root)
        let remote = try XCTUnwrap(manifests.first { $0.id == "mcp_server:remote" })
        XCTAssertEqual(remote.transport, .http)
        XCTAssertEqual(remote.serverURL, "https://mcp.example.com/mcp")
        XCTAssertEqual(remote.headers, ["X-Api-Key": "secret"])
        XCTAssertEqual(remote.oauthClientID, "client-123")

        let legacy = try XCTUnwrap(manifests.first { $0.id == "mcp_server:legacy" })
        XCTAssertEqual(legacy.transport, .sse)
        XCTAssertEqual(legacy.serverURL, "https://mcp.example.com/sse")
    }

    func testLoadsStandardCodexPluginSkillsAndMCPComponents() throws {
        let root = try makeQuillCodeTestDirectory()
        let packageRoot = root.appendingPathComponent(".quillcode/plugins/acme-tools")
        let manifestDirectory = packageRoot.appendingPathComponent(".codex-plugin")
        let skillDirectory = packageRoot.appendingPathComponent("skills/review")
        try FileManager.default.createDirectory(at: manifestDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: skillDirectory, withIntermediateDirectories: true)
        try "# Review\nFind correctness defects first.".write(
            to: skillDirectory.appendingPathComponent("SKILL.md"),
            atomically: true,
            encoding: .utf8
        )
        try #"{"name":"acme-tools","version":"1.2.0","description":"Fallback summary.","homepage":"https://example.com/acme","skills":"./skills","mcpServers":"./.mcp.json","interface":{"displayName":"Acme Tools","shortDescription":"Review and search tools."}}"#.write(
            to: manifestDirectory.appendingPathComponent("plugin.json"),
            atomically: true,
            encoding: .utf8
        )
        try #"{"mcpServers":{"search":{"command":"./bin/search-mcp","args":["--stdio"],"env":{"ACME_MODE":"plugin"},"env_vars":["ACME_TOKEN"]}}}"#.write(
            to: packageRoot.appendingPathComponent(".mcp.json"),
            atomically: true,
            encoding: .utf8
        )

        let manifests = ProjectExtensionManifestLoader.load(from: root)

        XCTAssertEqual(manifests.map(\.id), [
            "plugin:acme-tools",
            "skill:acme-tools.review",
            "mcp_server:acme-tools.search"
        ])
        let plugin = try XCTUnwrap(manifests.first)
        XCTAssertEqual(plugin.name, "Acme Tools")
        XCTAssertEqual(plugin.summary, "Review and search tools.")
        XCTAssertEqual(plugin.version, "1.2.0")
        XCTAssertEqual(plugin.sourceURL, "https://example.com/acme")
        XCTAssertEqual(plugin.packageRootRelativePath, ".quillcode/plugins/acme-tools")
        XCTAssertEqual(plugin.skillDirectoryRelativePaths, [".quillcode/plugins/acme-tools/skills"])

        let skill = manifests[1]
        XCTAssertEqual(skill.name, "Acme Tools · Review")
        XCTAssertEqual(skill.relativePath, ".quillcode/plugins/acme-tools/skills/review/SKILL.md")

        let mcp = try XCTUnwrap(manifests.last)
        XCTAssertEqual(mcp.name, "Acme Tools · Search")
        XCTAssertEqual(mcp.relativePath, ".quillcode/plugins/acme-tools/.mcp.json#search")
        XCTAssertEqual(mcp.transport, .stdio)
        XCTAssertEqual(mcp.launchExecutable, "./bin/search-mcp")
        XCTAssertEqual(mcp.launchArguments, ["--stdio"])
        XCTAssertEqual(mcp.launchEnvironment, ["ACME_MODE": "plugin"])
        XCTAssertEqual(mcp.inheritedEnvironmentVariableNames, ["ACME_TOKEN"])
        XCTAssertEqual(mcp.packageRootRelativePath, ".quillcode/plugins/acme-tools")
    }

    func testStandardPluginRejectsEscapingComponentsAndShadowedPackages() throws {
        let root = try makeQuillCodeTestDirectory()
        let pluginDirectory = root.appendingPathComponent(".quillcode/plugins")
        let packageRoot = pluginDirectory.appendingPathComponent("acme-tools")
        let manifestDirectory = packageRoot.appendingPathComponent(".codex-plugin")
        try FileManager.default.createDirectory(at: manifestDirectory, withIntermediateDirectories: true)
        try #"{"id":"acme-tools","name":"Direct Acme"}"#.write(
            to: pluginDirectory.appendingPathComponent("acme.json"),
            atomically: true,
            encoding: .utf8
        )
        try #"{"name":"acme-tools","skills":"../outside","mcpServers":"../outside.json"}"#.write(
            to: manifestDirectory.appendingPathComponent("plugin.json"),
            atomically: true,
            encoding: .utf8
        )

        let manifests = ProjectExtensionManifestLoader.load(from: root)

        XCTAssertEqual(manifests.map(\.id), ["plugin:acme-tools"])
        XCTAssertEqual(manifests.first?.name, "Direct Acme")
        XCTAssertNil(manifests.first?.skillDirectoryRelativePaths)
    }

    func testStandardPluginSkipsSymlinkedPackageDirectory() throws {
        let root = try makeQuillCodeTestDirectory()
        let pluginDirectory = root.appendingPathComponent(".quillcode/plugins")
        let outside = try makeQuillCodeTestDirectory()
        try FileManager.default.createDirectory(
            at: outside.appendingPathComponent(".codex-plugin"),
            withIntermediateDirectories: true
        )
        try #"{"name":"outside"}"#.write(
            to: outside.appendingPathComponent(".codex-plugin/plugin.json"),
            atomically: true,
            encoding: .utf8
        )
        try FileManager.default.createDirectory(at: pluginDirectory, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: pluginDirectory.appendingPathComponent("outside"),
            withDestinationURL: outside
        )

        XCTAssertTrue(ProjectExtensionManifestLoader.load(from: root).isEmpty)
    }

    func testStandardPluginLimitCountsOnlyValidPackages() throws {
        let root = try makeQuillCodeTestDirectory()
        let pluginDirectory = root.appendingPathComponent(".quillcode/plugins")
        try FileManager.default.createDirectory(at: pluginDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: pluginDirectory.appendingPathComponent("00-invalid"),
            withIntermediateDirectories: true
        )
        let manifestDirectory = pluginDirectory.appendingPathComponent("valid/.codex-plugin")
        try FileManager.default.createDirectory(at: manifestDirectory, withIntermediateDirectories: true)
        try #"{"name":"valid"}"#.write(
            to: manifestDirectory.appendingPathComponent("plugin.json"),
            atomically: true,
            encoding: .utf8
        )

        let packages = CodexPluginPackageLoader.load(
            from: root,
            pluginDirectory: ".quillcode/plugins",
            maxPackages: 1,
            maxManifestBytes: 64 * 1_024
        )

        XCTAssertEqual(packages.map(\.plugin.id), ["plugin:valid"])
    }

    func testStandardPluginBoundsBundledSkillComponents() throws {
        let root = try makeQuillCodeTestDirectory()
        let packageRoot = root.appendingPathComponent(".quillcode/plugins/many-skills")
        let manifestDirectory = packageRoot.appendingPathComponent(".codex-plugin")
        try FileManager.default.createDirectory(at: manifestDirectory, withIntermediateDirectories: true)
        try #"{"name":"many-skills","skills":"./skills"}"#.write(
            to: manifestDirectory.appendingPathComponent("plugin.json"),
            atomically: true,
            encoding: .utf8
        )
        for index in 0 ..< CodexPluginPackageLoader.maxComponentsPerPackage + 5 {
            let skillDirectory = packageRoot.appendingPathComponent("skills/skill-\(index)")
            try FileManager.default.createDirectory(at: skillDirectory, withIntermediateDirectories: true)
            try "# Skill \(index)".write(
                to: skillDirectory.appendingPathComponent("SKILL.md"),
                atomically: true,
                encoding: .utf8
            )
        }

        let package = try XCTUnwrap(CodexPluginPackageLoader.load(
            from: root,
            pluginDirectory: ".quillcode/plugins",
            maxPackages: 1,
            maxManifestBytes: 64 * 1_024
        ).first)

        XCTAssertEqual(package.components.count, CodexPluginPackageLoader.maxComponentsPerPackage)
        XCTAssertTrue(package.components.allSatisfy { $0.kind == .skill })
    }
}
