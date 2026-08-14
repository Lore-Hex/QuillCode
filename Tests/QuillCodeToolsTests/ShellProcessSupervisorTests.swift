import Foundation
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

    func testBuiltSupervisorDoesNotMissRapidChildExits() throws {
        let supervisor = try builtSupervisorURL()

        for iteration in 0..<100 {
            let process = Process()
            let stdout = Pipe()
            let stderr = Pipe()
            let completion = DispatchSemaphore(value: 0)
            process.executableURL = supervisor
            process.arguments = ["/bin/sh", "-lc", "printf 'quill-\(iteration)'"]
            process.standardOutput = stdout
            process.standardError = stderr
            process.terminationHandler = { _ in completion.signal() }

            try process.run()
            guard completion.wait(timeout: .now() + 1) == .success else {
                process.terminate()
                process.waitUntilExit()
                return XCTFail("Supervisor missed immediate child exit at iteration \(iteration)")
            }

            let output = String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            let error = String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            XCTAssertEqual(process.terminationStatus, 0, "Iteration \(iteration): \(error)")
            XCTAssertEqual(output, "quill-\(iteration)")
        }
    }

    private func builtSupervisorURL() throws -> URL {
        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let debugProduct = sourceRoot
            .appendingPathComponent(".build/debug")
            .appendingPathComponent(ShellProcessSupervisor.executableName)
        if FileManager.default.isExecutableFile(atPath: debugProduct.path) {
            return debugProduct
        }

        let starts = [
            Bundle(for: ShellProcessSupervisorTests.self).executableURL,
            Bundle.main.executableURL,
            URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
        ].compactMap { $0 }

        for start in starts {
            var directory = start.deletingLastPathComponent()
            for _ in 0..<10 {
                let candidate = directory.appendingPathComponent(ShellProcessSupervisor.executableName)
                if FileManager.default.isExecutableFile(atPath: candidate.path) {
                    return candidate
                }
                let parent = directory.deletingLastPathComponent()
                if parent.path == directory.path { break }
                directory = parent
            }
        }

        return try XCTUnwrap(nil, "Could not locate the built process supervisor")
    }
}
