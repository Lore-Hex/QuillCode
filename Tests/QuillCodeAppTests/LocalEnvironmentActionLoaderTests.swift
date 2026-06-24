import XCTest
@testable import QuillCodeApp

final class LocalEnvironmentActionLoaderTests: XCTestCase {
    func testUsesMetadataSidecars() throws {
        let root = try makeQuillCodeTestDirectory()
        let actionsDirectory = root.appendingPathComponent(".quillcode/actions")
        try FileManager.default.createDirectory(at: actionsDirectory, withIntermediateDirectories: true)
        try "printf second".write(
            to: actionsDirectory.appendingPathComponent("z-second.sh"),
            atomically: true,
            encoding: .utf8
        )
        try """
        {
          "title": "Second Check",
          "description": "Runs after dependencies are ready.",
          "order": 20
        }
        """.write(
            to: actionsDirectory.appendingPathComponent("z-second.json"),
            atomically: true,
            encoding: .utf8
        )
        try "printf first".write(
            to: actionsDirectory.appendingPathComponent("a-first.sh"),
            atomically: true,
            encoding: .utf8
        )
        try """
        {
          "title": "Prepare Workspace",
          "description": "Install dependencies and warm caches.",
          "order": 10
        }
        """.write(
            to: actionsDirectory.appendingPathComponent("a-first.json"),
            atomically: true,
            encoding: .utf8
        )

        let actions = LocalEnvironmentActionLoader.load(from: root)

        XCTAssertEqual(actions.map(\.title), ["Prepare Workspace", "Second Check"])
        XCTAssertEqual(actions.map(\.detail), [
            "Install dependencies and warm caches.",
            "Runs after dependencies are ready."
        ])
        XCTAssertEqual(actions.map(\.relativePath), [
            ".quillcode/actions/a-first.sh",
            ".quillcode/actions/z-second.sh"
        ])
        XCTAssertEqual(actions[0].command, #"sh '.quillcode/actions/a-first.sh'"#)
    }

    func testRejectsUnsafeWorkingDirectory() throws {
        let root = try makeQuillCodeTestDirectory()
        let outsideDirectory = try makeQuillCodeTestDirectory()
        let actionsDirectory = root.appendingPathComponent(".quillcode/actions")
        try FileManager.default.createDirectory(at: actionsDirectory, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("escape"),
            withDestinationURL: outsideDirectory
        )
        try "printf safe".write(
            to: actionsDirectory.appendingPathComponent("safe.sh"),
            atomically: true,
            encoding: .utf8
        )
        try """
        {
          "title": "Safe",
          "workingDirectory": "escape"
        }
        """.write(
            to: actionsDirectory.appendingPathComponent("safe.json"),
            atomically: true,
            encoding: .utf8
        )

        let action = try XCTUnwrap(LocalEnvironmentActionLoader.load(from: root).first)

        XCTAssertNil(action.workingDirectory)
        XCTAssertEqual(action.command, #"sh '.quillcode/actions/safe.sh'"#)
    }

    func testRejectsUnsafeTimeoutSeconds() throws {
        let root = try makeQuillCodeTestDirectory()
        let actionsDirectory = root.appendingPathComponent(".quillcode/actions")
        try FileManager.default.createDirectory(at: actionsDirectory, withIntermediateDirectories: true)
        try "printf safe".write(
            to: actionsDirectory.appendingPathComponent("safe.sh"),
            atomically: true,
            encoding: .utf8
        )
        try """
        {
          "title": "Safe",
          "timeout_seconds": 1801
        }
        """.write(
            to: actionsDirectory.appendingPathComponent("safe.json"),
            atomically: true,
            encoding: .utf8
        )

        let action = try XCTUnwrap(LocalEnvironmentActionLoader.load(from: root).first)

        XCTAssertNil(action.timeoutSeconds)
    }

    func testBoundsScriptsAndRejectsSymlinkEscape() throws {
        let root = try makeQuillCodeTestDirectory()
        let outside = try makeQuillCodeTestDirectory().appendingPathComponent("outside.sh")
        try "printf bad".write(to: outside, atomically: true, encoding: .utf8)
        let outsideMetadata = outside.deletingPathExtension().appendingPathExtension("json")
        try """
        { "title": "Escaped Metadata" }
        """.write(to: outsideMetadata, atomically: true, encoding: .utf8)
        let actionsDirectory = root.appendingPathComponent(".quillcode/actions")
        try FileManager.default.createDirectory(at: actionsDirectory, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: actionsDirectory.appendingPathComponent("outside.sh"),
            withDestinationURL: outside
        )
        try "printf one".write(
            to: actionsDirectory.appendingPathComponent("one.sh"),
            atomically: true,
            encoding: .utf8
        )
        try FileManager.default.createSymbolicLink(
            at: actionsDirectory.appendingPathComponent("one.json"),
            withDestinationURL: outsideMetadata
        )
        try "printf two".write(
            to: actionsDirectory.appendingPathComponent("two.sh"),
            atomically: true,
            encoding: .utf8
        )

        let actions = LocalEnvironmentActionLoader.load(from: root, maxActions: 1)

        XCTAssertEqual(actions.map(\.relativePath), [".quillcode/actions/one.sh"])
        XCTAssertEqual(actions[0].title, "One")
        XCTAssertEqual(actions[0].command, #"sh '.quillcode/actions/one.sh'"#)
    }
}
