import XCTest
import QuillCodeCore
@testable import QuillCodeTools

/// Guards the fix for the "GUI app can't find Homebrew" bug: a `.app` launched from Finder inherits
/// only launchd's minimal PATH, so `uv`/`python3`/`node`/`rg` 127 in the agent's shell. `augmentedPATH`
/// must make those resolvable without disturbing an already-working PATH.
final class ShellEnvironmentPathTests: XCTestCase {
    /// The exact minimal PATH a GUI-launched app sees (from the live `env -i … /bin/sh -lc` repro).
    private let launchdMinimalPATH =
        "/usr/local/bin:/System/Cryptexes/App/usr/bin:/usr/bin:/bin:/usr/sbin:/sbin:/Library/Apple/usr/bin"

    func testHomebrewBinIsAddedToAMinimalLaunchdPath() {
        let path = ShellEnvironmentPath.augmentedPATH(base: launchdMinimalPATH, home: "/Users/dev")
        let dirs = path.split(separator: ":").map(String.init)
        XCTAssertTrue(dirs.contains("/opt/homebrew/bin"), "Homebrew bin must be reachable: \(path)")
        XCTAssertTrue(dirs.contains("/opt/homebrew/sbin"))
    }

    func testExistingEntriesKeepPriorityAndAugmentationIsAppended() {
        let path = ShellEnvironmentPath.augmentedPATH(base: "/usr/bin:/bin", home: nil)
        let dirs = path.split(separator: ":").map(String.init)
        // Base entries come first (so a task relying on /usr/bin/python3 still gets it), dev dirs after.
        XCTAssertEqual(Array(dirs.prefix(2)), ["/usr/bin", "/bin"])
        XCTAssertLessThan(dirs.firstIndex(of: "/usr/bin")!, dirs.firstIndex(of: "/opt/homebrew/bin")!)
    }

    func testNoDuplicateWhenHomebrewAlreadyPresent() {
        let base = "/opt/homebrew/bin:/usr/bin:/bin"
        let path = ShellEnvironmentPath.augmentedPATH(base: base, home: nil)
        let occurrences = path.split(separator: ":").filter { $0 == "/opt/homebrew/bin" }.count
        XCTAssertEqual(occurrences, 1, "must not duplicate an already-present dir: \(path)")
        // And it keeps its original (front) position, not re-appended.
        XCTAssertEqual(path.split(separator: ":").first.map(String.init), "/opt/homebrew/bin")
    }

    func testHomeRelativeToolDirsResolvedAgainstHome() {
        let path = ShellEnvironmentPath.augmentedPATH(base: "/usr/bin", home: "/Users/dev")
        let dirs = path.split(separator: ":").map(String.init)
        XCTAssertTrue(dirs.contains("/Users/dev/.local/bin"))
        XCTAssertTrue(dirs.contains("/Users/dev/.cargo/bin"))
        XCTAssertTrue(dirs.contains("/Users/dev/go/bin"))
    }

    func testTrailingSlashOnHomeDoesNotDoubleSlash() {
        let path = ShellEnvironmentPath.augmentedPATH(base: "/usr/bin", home: "/Users/dev/")
        XCTAssertTrue(path.contains("/Users/dev/.local/bin"))
        XCTAssertFalse(path.contains("//"), "no double slashes: \(path)")
    }

    func testNilOrEmptyBaseStillYieldsDevTooling() {
        for base in [nil, ""] as [String?] {
            let path = ShellEnvironmentPath.augmentedPATH(base: base, home: "/Users/dev")
            XCTAssertTrue(path.split(separator: ":").contains("/opt/homebrew/bin"))
            XCTAssertFalse(path.hasPrefix(":"), "no leading empty segment: \(path)")
        }
    }

    /// End-to-end: a command dispatched through the real shell tool must see the augmented PATH, so the
    /// fix works through the whole `ShellToolCallDispatcher` → `ShellToolExecutor` → child `/bin/sh`
    /// path, not just in the pure helper. Asserts the directory is PRESENT in the child's `$PATH`
    /// (env-independent: the augmentation always adds it, whether or not Homebrew is installed on CI).
    func testDispatchedShellCommandReceivesAugmentedPathEndToEnd() throws {
        let dispatcher = ShellToolCallDispatcher(
            workspaceRoot: URL(fileURLWithPath: NSTemporaryDirectory()),
            shell: ShellToolExecutor(),
            accessScope: .unrestricted
        )
        let result = try dispatcher.execute(
            name: "host.shell.run",
            arguments: try ToolArguments(#"{"cmd":"echo \"$PATH\""}"#)
        )
        XCTAssertTrue(result.ok, "shell should run: \(result.error ?? "")")
        XCTAssertTrue(
            result.stdout.contains("/opt/homebrew/bin"),
            "the augmented developer PATH must reach the child shell: \(result.stdout)"
        )
    }
}
