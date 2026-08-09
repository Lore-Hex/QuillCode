import XCTest

final class ParityReleaseNotesGateTests: QuillCodeParityTestCase {
    func testTesterReleaseNotesExposeDirectInstallersAndActionableGuidance() throws {
        let fixture = try makeFixture(
            channel: "tester",
            commit: String(repeating: "a", count: 40),
            codesign: "ad-hoc",
            signingTeam: "none",
            notarized: "false"
        )
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let result = try runGenerator(
            fixture: fixture,
            tag: "tester-latest",
            channel: "tester",
            commit: String(repeating: "a", count: 40),
            run: "678"
        )
        XCTAssertEqual(result.exitCode, 0, result.output)

        let notes = try String(contentsOf: fixture.output, encoding: .utf8)
        Self.assertSource(notes, containsAll: [
            "# Download Quill Cowork",
            "raw.githubusercontent.com/Lore-Hex/QuillCode/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/",
            "docs/images/quill-cowork-desktop.png",
            "Tester version 0.1.0 (build 678)",
            "macOS 14.0 or later",
            "Apple silicon (M-series)",
            "Intel processor",
            "Quill-Cowork-macOS-arm64.dmg",
            "Quill-Cowork-macOS-x86_64.dmg",
            "Drag **Quill Cowork.app** onto **Applications**",
            "Control-click **Quill Cowork**, choose **Open**",
            "checks this tester channel automatically",
            "the previous build is restored",
            "Machine-readable update manifest",
            "latest-tester-build.json",
            "[`aaaaaaaa`](https://github.com/Lore-Hex/QuillCode/commit/",
            "https://github.com/Lore-Hex/QuillCode/actions/runs/678",
            "Signing: Ad-hoc; not notarized"
        ])
        Self.assertSource(notes, excludes: "macOS-*.dmg")
    }

    func testStableReleaseNotesRequireAndDescribeNotarizedDeveloperIDBuild() throws {
        let commit = String(repeating: "b", count: 40)
        let fixture = try makeFixture(
            channel: "stable",
            commit: commit,
            codesign: "developer-id",
            signingTeam: "ABCDE12345",
            notarized: "true",
            version: "1.2.3"
        )
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let result = try runGenerator(
            fixture: fixture,
            tag: "v1.2.3",
            channel: "stable",
            commit: commit,
            run: "900"
        )
        XCTAssertEqual(result.exitCode, 0, result.output)

        let notes = try String(contentsOf: fixture.output, encoding: .utf8)
        Self.assertSource(notes, containsAll: [
            "Stable version 1.2.3 (build 678)",
            "releases/download/v1.2.3/Quill-Cowork-macOS-arm64.dmg",
            "releases/download/v1.2.3/Quill-Cowork-macOS-x86_64.dmg",
            "Developer ID signed, notarized by Apple, and stapled",
            "Signing: Developer ID, notarized (team `ABCDE12345`)",
            "latest-stable-build.json"
        ])
        Self.assertSource(notes, excludes: "Control-click")
    }

    func testReleaseNotesRejectBuildMetadataFromAnotherCommit() throws {
        let fixture = try makeFixture(
            channel: "tester",
            commit: String(repeating: "c", count: 40),
            codesign: "ad-hoc",
            signingTeam: "none",
            notarized: "false"
        )
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let result = try runGenerator(
            fixture: fixture,
            tag: "tester-latest",
            channel: "tester",
            commit: String(repeating: "d", count: 40),
            run: "678"
        )
        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("BUILD_INFO commit must be"), result.output)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.output.path))
    }

    func testReleaseNotesRejectFalseNotarizationClaim() throws {
        let commit = String(repeating: "e", count: 40)
        let fixture = try makeFixture(
            channel: "stable",
            commit: commit,
            codesign: "ad-hoc",
            signingTeam: "none",
            notarized: "true",
            version: "1.2.3"
        )
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let result = try runGenerator(
            fixture: fixture,
            tag: "v1.2.3",
            channel: "stable",
            commit: commit,
            run: "900"
        )
        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("ad-hoc BUILD_INFO must be unnotarized"), result.output)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.output.path))
    }

    func testStableReleaseNotesRejectTagVersionMismatch() throws {
        let commit = String(repeating: "f", count: 40)
        let fixture = try makeFixture(
            channel: "stable",
            commit: commit,
            codesign: "developer-id",
            signingTeam: "ABCDE12345",
            notarized: "true",
            version: "1.2.4"
        )
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let result = try runGenerator(
            fixture: fixture,
            tag: "v1.2.3",
            channel: "stable",
            commit: commit,
            run: "900"
        )
        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("tag must match the packaged app version"), result.output)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.output.path))
    }

    private func makeFixture(
        channel: String,
        commit: String,
        codesign: String,
        signingTeam: String,
        notarized: String,
        version: String = "0.1.0"
    ) throws -> Fixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("quillcode-release-notes-tests")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let buildInfo = """
        product=Quill Cowork
        platform=macOS
        arch=arm64
        version=\(version)
        build=678
        commit=\(commit)
        configuration=release
        bundleIdentifier=co.lorehex.QuillCowork
        minimumSystemVersion=14.0
        updateChannel=\(channel)
        codesign=\(codesign)
        signingTeamIdentifier=\(signingTeam)
        notarized=\(notarized)
        """
        let buildInfoURL = root.appendingPathComponent("BUILD_INFO.txt")
        try buildInfo.write(to: buildInfoURL, atomically: true, encoding: .utf8)
        return Fixture(
            root: root,
            buildInfo: buildInfoURL,
            output: root.appendingPathComponent("release-notes.md")
        )
    }

    private func runGenerator(
        fixture: Fixture,
        tag: String,
        channel: String,
        commit: String,
        run: String
    ) throws -> ScriptResult {
        let script = Self.packageRoot()
            .appendingPathComponent("scripts")
            .appendingPathComponent("build-release-notes.py")
        return try Self.runPython(script, arguments: [
            "--build-info", fixture.buildInfo.path,
            "--repo", "Lore-Hex/QuillCode",
            "--tag", tag,
            "--channel", channel,
            "--commit", commit,
            "--workflow-run-url", "https://github.com/Lore-Hex/QuillCode/actions/runs/\(run)",
            "--output", fixture.output.path
        ])
    }

    private struct Fixture {
        var root: URL
        var buildInfo: URL
        var output: URL
    }
}
