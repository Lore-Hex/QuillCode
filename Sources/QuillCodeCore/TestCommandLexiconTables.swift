import Foundation

extension TestCommandLexicon {
    /// Single-program test runners: argv[0]'s basename alone means "running tests".
    /// Matched against the command basename, case-insensitively.
    public static let runnerBasenames: [String] = [
        "pytest",
        "py.test",
        "nosetests",
        "jest",
        "vitest",
        "mocha",
        "ava",
        "rspec",
        "phpunit",
        "gotestsum",
        "ctest",
        "tox",
        "nose2",
        "xctest",
        "karma",
        "cypress",
        "playwright",
    ]

    /// Build/package drivers where a `test`/`check` subcommand means "running tests".
    public static let driverSubcommands: [String: Set<String>] = [
        "swift": ["test"],
        "go": ["test"],
        "cargo": ["test", "nextest"],
        "npm": ["test", "t"],
        "yarn": ["test"],
        "pnpm": ["test"],
        "bun": ["test"],
        "make": ["test", "check"],
        "gradle": ["test", "check"],
        "gradlew": ["test", "check"],
        "mvn": ["test", "verify"],
        "dotnet": ["test"],
        "rake": ["test", "spec"],
        "rails": ["test"],
        "bazel": ["test"],
        "ninja": ["test"],
        "xcodebuild": ["test", "test-without-building", "build-for-testing"],
        "nx": ["test", "e2e"],
    ]

    /// Drivers that legitimately place flags before the test subcommand.
    public static let flagsBeforeSubcommandDrivers: Set<String> = ["xcodebuild"]

    /// `npm`/`yarn`/`pnpm run <script>` where the script name is test-shaped.
    public static let scriptRunnerBasenames: Set<String> = ["npm", "yarn", "pnpm", "bun"]

    /// Test script paths whose argv[0] basename is itself a test script.
    public static let testScriptBasenames: [String] = [
        "test.sh",
        "tests.sh",
        "runtests",
        "runtests.sh",
        "run-tests",
        "run-tests.sh",
        "run_tests",
        "run_tests.sh",
        "test.py",
        "runtests.py",
        "test.bat",
        "check.sh",
    ]

    /// Command wrappers that pass through to the real command.
    static let passthroughWrappers: Set<String> = [
        "sudo", "env", "time", "nice", "nohup", "stdbuf", "xargs", "command", "exec",
        "npx", "pnpx",
    ]

    /// Wrappers of the shape `<wrapper> run/exec <program>`.
    static let runVerbWrappers: [String: Set<String>] = [
        "poetry": ["run"],
        "pipenv": ["run"],
        "uv": ["run"],
        "rye": ["run"],
        "hatch": ["run"],
        "bundle": ["exec"],
        "pdm": ["run"],
    ]

    /// Presence-probe programs describe a command instead of executing it.
    static let presenceProbePrograms: Set<String> = ["which", "type", "hash", "whereis"]

    /// Test modules invoked via `python -m <module>`.
    public static let pythonTestModules: Set<String> = [
        "pytest", "unittest", "nose", "nose2", "tox", "green", "ward", "behave", "trial",
    ]

    /// Python interpreters that front a `-m <module>` invocation.
    static let pythonInterpreters: Set<String> = ["python", "python3", "python2", "py", "pypy", "pypy3"]

    /// Flags ignored by `scopeKey`: unambiguously non-selecting output/verbosity flags.
    ///
    /// Everything not on this list is treated as potentially suite-selecting,
    /// which over-distinguishes at worst and avoids false-clearing a standing
    /// test failure with an unrelated green run.
    static let benignNonSelectingFlags: Set<String> = [
        "-v", "-vv", "-vvv", "-q", "-qq",
        "--verbose", "--quiet", "--silent", "--color", "--no-color", "--colour", "--no-colour",
        "--nocolor", "--help", "--version", "--full-trace", "--show-output",
        "--nocapture", "--no-capture", "--capture", "--tb",
    ]
}
