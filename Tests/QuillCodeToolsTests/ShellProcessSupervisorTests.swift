import XCTest
@testable import QuillCodeTools

final class ShellProcessSupervisorTests: XCTestCase {
    func testWrappingPreservesSandboxIdentityAndCommandArguments() throws {
        let supervisor = URL(fileURLWithPath: "/tmp/quill-code-process-supervisor")
        let launch = ShellProcessLaunch(
            executable: URL(fileURLWithPath: "/usr/bin/sandbox-exec"),
            arguments: ["-p", "(version 1)", "--", "/bin/sh", "-lc", "printf ok"],
            isSandboxed: true
        )

        let wrapped = ShellProcessSupervisor.wrapping(launch, supervisorURL: supervisor)

        XCTAssertEqual(wrapped.executable, supervisor)
        XCTAssertEqual(wrapped.arguments, [launch.executable.path] + launch.arguments)
        XCTAssertTrue(wrapped.isSandboxed)
    }

    func testMissingSupervisorLeavesLaunchUnchanged() {
        let launch = ShellProcessLaunch(
            executable: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-lc", "printf ok"],
            isSandboxed: false
        )

        XCTAssertEqual(ShellProcessSupervisor.wrapping(launch, supervisorURL: nil), launch)
    }

    func testResolverUsesExplicitExecutableOverride() throws {
        let root = try makeTempDirectory()
        let supervisor = root.appendingPathComponent("supervisor")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: supervisor)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: supervisor.path
        )

        let resolved = ShellProcessSupervisor.resolveExecutable(
            environment: [ShellProcessSupervisor.environmentKey: supervisor.path],
            bundle: .main,
            currentExecutableURL: nil
        )

        XCTAssertEqual(resolved, supervisor.standardizedFileURL)
    }

    func testResolverFindsSupervisorBesideCurrentExecutable() throws {
        let root = try makeTempDirectory()
        let current = root.appendingPathComponent("quill-code")
        let supervisor = root.appendingPathComponent(ShellProcessSupervisor.executableName)
        for executable in [current, supervisor] {
            try Data("#!/bin/sh\nexit 0\n".utf8).write(to: executable)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: executable.path
            )
        }

        let resolved = ShellProcessSupervisor.resolveExecutable(
            environment: [:],
            bundle: .main,
            currentExecutableURL: current
        )

        XCTAssertEqual(resolved, supervisor)
    }
}
