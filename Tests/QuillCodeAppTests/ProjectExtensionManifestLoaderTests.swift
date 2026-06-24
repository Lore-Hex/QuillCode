import XCTest
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

        try #"{"id":"github","name":"GitHub","description":"PR and issue helpers.","version":"1.2.0","source":"https://github.com/Lore-Hex/quillcode-github","updateCommand":"git -C .quillcode/plugins/github pull --ff-only","updateTimeoutSeconds":300}"#.write(
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
}
