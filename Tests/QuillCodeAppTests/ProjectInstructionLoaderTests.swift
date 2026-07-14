import XCTest
@testable import QuillCodeApp

final class ProjectInstructionLoaderTests: XCTestCase {
    func testBoundsFilesAndRejectsSymlinkEscape() throws {
        let root = try makeQuillCodeTestDirectory()
        let outside = try makeQuillCodeTestDirectory().appendingPathComponent("outside.md")
        try "outside rules\n".write(to: outside, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("AGENTS.md"),
            withDestinationURL: outside
        )
        let quillcodeDirectory = root.appendingPathComponent(".quillcode")
        try FileManager.default.createDirectory(at: quillcodeDirectory, withIntermediateDirectories: true)
        try String(repeating: "x", count: 64).write(
            to: quillcodeDirectory.appendingPathComponent("rules.md"),
            atomically: true,
            encoding: .utf8
        )

        let instructions = ProjectInstructionLoader.load(
            from: root,
            maxFileBytes: 12,
            maxTotalBytes: 20
        )

        XCTAssertEqual(instructions.map(\.path), [".quillcode/rules.md"])
        XCTAssertTrue(instructions[0].wasTruncated)
        XCTAssertTrue(instructions[0].content.contains("truncated"))
        XCTAssertFalse(instructions[0].content.contains("outside rules"))
    }

    func testLoadsNestedInstructionsInPrecedenceOrder() throws {
        let root = try makeQuillCodeTestDirectory()
        try "Root rules\n".write(
            to: root.appendingPathComponent("AGENTS.md"),
            atomically: true,
            encoding: .utf8
        )

        let feature = root.appendingPathComponent("Sources/Feature")
        try FileManager.default.createDirectory(at: feature, withIntermediateDirectories: true)
        try "Sources rules\n".write(
            to: root.appendingPathComponent("Sources/AGENTS.md"),
            atomically: true,
            encoding: .utf8
        )
        try "Feature rules\n".write(
            to: feature.appendingPathComponent("AGENTS.md"),
            atomically: true,
            encoding: .utf8
        )

        let featureQuillCode = feature.appendingPathComponent(".quillcode")
        try FileManager.default.createDirectory(at: featureQuillCode, withIntermediateDirectories: true)
        try "Feature QuillCode rules\n".write(
            to: featureQuillCode.appendingPathComponent("rules.md"),
            atomically: true,
            encoding: .utf8
        )

        let generated = root.appendingPathComponent(".build/generated")
        try FileManager.default.createDirectory(at: generated, withIntermediateDirectories: true)
        try "Generated rules should not load\n".write(
            to: generated.appendingPathComponent("AGENTS.md"),
            atomically: true,
            encoding: .utf8
        )

        let instructions = ProjectInstructionLoader.load(from: root)

        XCTAssertEqual(instructions.map(\.path), [
            "AGENTS.md",
            "Sources/AGENTS.md",
            "Sources/Feature/AGENTS.md",
            "Sources/Feature/.quillcode/rules.md"
        ])
        XCTAssertEqual(instructions.map(\.scopePath), [
            ".",
            "Sources",
            "Sources/Feature",
            "Sources/Feature"
        ])
        XCTAssertTrue(instructions.last?.content.contains("Feature QuillCode rules") == true)
        XCTAssertFalse(instructions.contains { $0.content.contains("Generated rules") })
    }

    func testCapsNestedInstructionCount() throws {
        let root = try makeQuillCodeTestDirectory()
        for index in 0..<5 {
            let directory = root.appendingPathComponent("Area\(index)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try "Rules \(index)\n".write(
                to: directory.appendingPathComponent("AGENTS.md"),
                atomically: true,
                encoding: .utf8
            )
        }

        let instructions = ProjectInstructionLoader.load(
            from: root,
            maxInstructionFiles: 2
        )

        XCTAssertEqual(instructions.map(\.path), [
            "Area0/AGENTS.md",
            "Area1/AGENTS.md"
        ])
    }

    func testLoadsAdditiveRuleFilesWithoutFollowingSymlinks() throws {
        let root = try makeQuillCodeTestDirectory()
        let rules = root.appendingPathComponent(".quillcode/rules")
        try FileManager.default.createDirectory(at: rules, withIntermediateDirectories: true)
        try "Imported guidance\n".write(
            to: rules.appendingPathComponent("imported-claude.md"),
            atomically: true,
            encoding: .utf8
        )
        let outside = try makeQuillCodeTestDirectory().appendingPathComponent("outside.md")
        try "Do not load\n".write(to: outside, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(
            at: rules.appendingPathComponent("escaped.md"),
            withDestinationURL: outside
        )

        let instructions = ProjectInstructionLoader.load(from: root)

        XCTAssertEqual(instructions.map(\.path), [".quillcode/rules/imported-claude.md"])
        XCTAssertEqual(instructions.map(\.scopePath), ["."])
        XCTAssertEqual(instructions.map(\.title), ["QuillCode rule: imported-claude"])
        XCTAssertFalse(instructions.contains { $0.content.contains("Do not load") })
    }
}
