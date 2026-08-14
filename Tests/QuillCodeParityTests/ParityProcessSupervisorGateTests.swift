import Foundation
import XCTest

final class ParityProcessSupervisorGateTests: QuillCodeParityTestCase {
    func testPackagedShellsHaveAParentDeathProcessGroupBoundary() throws {
        let root = Self.packageRoot()
        let supervisor = try String(
            contentsOf: root.appendingPathComponent(
                "Sources/quill-code-process-supervisor/main.c"
            ),
            encoding: .utf8
        )
        let resolver = try String(
            contentsOf: root.appendingPathComponent(
                "Sources/QuillCodeTools/ShellProcessSupervisor.swift"
            ),
            encoding: .utf8
        )
        let shell = try String(
            contentsOf: root.appendingPathComponent("Sources/QuillCodeTools/ShellToolExecutor.swift"),
            encoding: .utf8
        )
        let streaming = try String(
            contentsOf: root.appendingPathComponent(
                "Sources/QuillCodeTools/ShellStreamingProcessRunner.swift"
            ),
            encoding: .utf8
        )
        let terminal = try String(
            contentsOf: root.appendingPathComponent("Sources/QuillCodeTools/PTYProcessSession.swift"),
            encoding: .utf8
        )

        Self.assertSource(supervisor, containsAll: [
            "setpgid(0, 0)",
            "kill(-child, SIGTERM)",
            "kill(-child, SIGKILL)",
            "getppid() != parent",
            "EVFILT_PROC",
            "NOTE_EXIT",
            "struct timespec timeout",
            "kevent(queue, NULL, 0, &event, 1, &timeout)",
            "WEXITED | WNOHANG | WNOWAIT",
            "reap_child(child, &status)",
            "PR_SET_PDEATHSIG"
        ])
        Self.assertSource(resolver, containsAll: [
            "Contents/Helpers",
            "quill-code-process-supervisor",
            "[launch.executable.path] + launch.arguments"
        ])
        for source in [shell, streaming, terminal] {
            Self.assertSource(source, contains: "ShellProcessSupervisor.wrapping")
        }
    }

    func testDistributionBuildsSignsAndUniversallyMergesTheSupervisor() throws {
        let build = try Self.scriptText(named: "build-macos-app.sh")
        let downloads = try Self.scriptText(named: "package-macos-downloads.sh")
        let linuxDownloads = try Self.scriptText(named: "package-linux-downloads.sh")
        let universal = try Self.scriptText(named: "package-macos-universal-installer.sh")
        let packagedSmoke = try Self.scriptText(named: "packaged-macos-smoke.sh")
        let crashSmoke = try Self.desktopSourceText(named: "QuillCodeDesktopAgentRunCrashSmoke.swift")

        Self.assertSource(build, containsAll: [
            "--product quill-code-process-supervisor",
            "HELPERS_DIR=\"$CONTENTS_DIR/Helpers\"",
            "codesign \"${CODESIGN_ARGUMENTS[@]}\" \"$HELPERS_DIR/quill-code-process-supervisor\""
        ])
        Self.assertSource(downloads, containsAll: [
            "cp \"$BIN_DIR/quill-code-process-supervisor\"",
            "sudo install -m 755 quill-code-process-supervisor"
        ])
        Self.assertSource(linuxDownloads, containsAll: [
            "--product quill-code-process-supervisor",
            "cp \"$BIN_DIR/quill-code-process-supervisor\"",
            "sudo install -m 755 quill-code-process-supervisor"
        ])
        Self.assertSource(universal, containsAll: [
            "SUPERVISOR_RELATIVE_PATH",
            "MERGED_SUPERVISOR",
            "-verify_arch arm64 x86_64",
            "\"$CODESIGN_BIN\" \"${CODESIGN_ARGUMENTS[@]}\" \"$UNIVERSAL_SUPERVISOR\""
        ])
        Self.assertSource(packagedSmoke, containsAll: [
            "PROCESS_SUPERVISOR=",
            "Packaged process supervisor is missing or not executable"
        ])
        Self.assertSource(crashSmoke, containsAll: [
            "crash-child.pid",
            "liveChildPID(at: childPIDURL)",
            "guard !processIsAlive(childPID)",
            "childProcessSurvived"
        ])
    }
}
