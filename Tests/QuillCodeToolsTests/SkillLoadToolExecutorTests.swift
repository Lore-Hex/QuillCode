import XCTest
import QuillCodeCore
@testable import QuillCodeTools

final class SkillLoadToolExecutorTests: XCTestCase {
    private var tempRoot: URL!
    private var userRoot: URL!
    private var builtinRoot: URL!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("skill-exec-\(UUID().uuidString)", isDirectory: true)
        userRoot = tempRoot.appendingPathComponent("user", isDirectory: true)
        builtinRoot = tempRoot.appendingPathComponent("builtin", isDirectory: true)
        try FileManager.default.createDirectory(at: userRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: builtinRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempRoot {
            try? FileManager.default.removeItem(at: tempRoot)
        }
    }

    private func makeSkill(
        in root: URL,
        name: String,
        manifest: String,
        extraFiles: [String: String] = [:]
    ) throws {
        let dir = root.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try manifest.write(to: dir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        for (relative, contents) in extraFiles {
            let fileURL = dir.appendingPathComponent(relative)
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try contents.write(to: fileURL, atomically: true, encoding: .utf8)
        }
    }

    private func executor(
        manifestMaxBytes: Int = SkillLoadToolExecutor.defaultManifestMaxBytes,
        maxListedFiles: Int = SkillLoadToolExecutor.defaultMaxListedFiles
    ) -> SkillLoadToolExecutor {
        SkillLoadToolExecutor(
            resolver: SkillResolver(roots: [
                SkillRoot(kind: .user, url: userRoot),
                SkillRoot(kind: .builtin, url: builtinRoot)
            ]),
            manifestMaxBytes: manifestMaxBytes,
            maxListedFiles: maxListedFiles
        )
    }

    // MARK: - Happy path

    func testLoadInjectsBaseDirFileListAndBody() throws {
        try makeSkill(
            in: builtinRoot,
            name: "reviewer",
            manifest: "# Reviewer\nInspect the diff.\n",
            extraFiles: [
                "checklist.md": "1. correctness\n",
                "scripts/run.sh": "#!/bin/sh\necho hi\n"
            ]
        )

        let result = executor().load(name: "reviewer")
        XCTAssertTrue(result.ok, result.error ?? "")
        let out = result.stdout

        // <skill_content> wrapper with source label.
        XCTAssertTrue(out.contains("<skill_content name=\"reviewer\" source=\"builtin\">"))
        XCTAssertTrue(out.contains("</skill_content>"))

        // Absolute base directory.
        let expectedBase = builtinRoot.appendingPathComponent("reviewer").standardizedFileURL.path
        XCTAssertTrue(out.contains("Base directory (absolute): \(expectedBase)"), out)

        // File listing (relative), excluding directories, including nested files.
        XCTAssertTrue(out.contains("- SKILL.md"))
        XCTAssertTrue(out.contains("- checklist.md"))
        XCTAssertTrue(out.contains("- scripts/run.sh"))

        // Manifest body injected.
        XCTAssertTrue(out.contains("# Reviewer"))
        XCTAssertTrue(out.contains("Inspect the diff."))
    }

    func testUserSkillShadowsBuiltinInLoad() throws {
        try makeSkill(in: userRoot, name: "dup", manifest: "# From user\n")
        try makeSkill(in: builtinRoot, name: "dup", manifest: "# From builtin\n")

        let result = executor().load(name: "dup")
        XCTAssertTrue(result.ok, result.error ?? "")
        XCTAssertTrue(result.stdout.contains("source=\"user\""))
        XCTAssertTrue(result.stdout.contains("# From user"))
        XCTAssertFalse(result.stdout.contains("# From builtin"))
    }

    // MARK: - Errors

    func testMissingSkillGivesActionableErrorWithSuggestion() throws {
        try makeSkill(in: userRoot, name: "code-review", manifest: "# CR\n")

        // Close typo -> "did you mean".
        let result = executor().load(name: "code-reviw")
        XCTAssertFalse(result.ok)
        XCTAssertTrue(result.error?.contains("code-reviw") == true)
        XCTAssertTrue(result.error?.contains("code-review") == true, result.error ?? "")
    }

    func testMissingSkillWithNoSkillsInstalled() {
        let result = executor().load(name: "anything")
        XCTAssertFalse(result.ok)
        XCTAssertTrue(result.error?.contains("no skills are installed") == true, result.error ?? "")
    }

    func testPathTraversalNameRejected() {
        let result = executor().load(name: "../../etc/passwd")
        XCTAssertFalse(result.ok)
        XCTAssertTrue(result.error?.contains("not a valid skill name") == true, result.error ?? "")
    }

    func testEmptyNameRejected() {
        let result = executor().load(name: "   ")
        XCTAssertFalse(result.ok)
    }

    // MARK: - Capping

    func testOversizedManifestIsCapped() throws {
        let big = String(repeating: "line of skill text\n", count: 5_000)
        try makeSkill(in: builtinRoot, name: "huge", manifest: big)

        let result = executor(manifestMaxBytes: 2_048).load(name: "huge")
        XCTAssertTrue(result.ok, result.error ?? "")
        XCTAssertTrue(result.stdout.contains("truncated"), "expected a truncation marker")
        // The tool output must be far smaller than the raw manifest.
        XCTAssertLessThan(result.stdout.utf8.count, big.utf8.count / 2)
        // The truncation note points at the on-disk file for the full text.
        XCTAssertTrue(result.stdout.contains("SKILL.md"))
    }

    func testFileListIsCappedWithMoreMarker() throws {
        var extra: [String: String] = [:]
        for index in 0..<50 {
            extra["file-\(String(format: "%03d", index)).txt"] = "x"
        }
        try makeSkill(in: builtinRoot, name: "manyfiles", manifest: "# many\n", extraFiles: extra)

        let result = executor(maxListedFiles: 10).load(name: "manyfiles")
        XCTAssertTrue(result.ok, result.error ?? "")
        XCTAssertTrue(result.stdout.contains("more"), "expected a truncated-file-list marker")
    }

    func testInvalidUTF8ManifestGivesActionableError() throws {
        let dir = builtinRoot.appendingPathComponent("binary", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // Bytes that are not valid UTF-8.
        try Data([0xFF, 0xFE, 0xFD]).write(to: dir.appendingPathComponent("SKILL.md"))

        let result = executor().load(name: "binary")
        XCTAssertFalse(result.ok)
        XCTAssertTrue(result.error?.contains("valid UTF-8") == true, result.error ?? "")
    }
}
