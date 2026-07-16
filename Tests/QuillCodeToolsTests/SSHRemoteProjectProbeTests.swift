import Foundation
import QuillCodeCore
@testable import QuillCodeTools
import XCTest

final class SSHRemoteProjectProbeTests: XCTestCase {
    func testProbeReportsResolvedRemoteFolder() async throws {
        let root = try makeTempDirectory()
        let fakeSSH = root.appendingPathComponent("fake-ssh")
        try #"""
        #!/bin/sh
        printf '__QUILLCODE_SSH_READY__\n/srv/quill\n'
        """#.write(to: fakeSSH, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeSSH.path)

        let result = await SSHRemoteProjectProbe(
            remoteExecutor: SSHRemoteShellExecutor(sshExecutable: fakeSSH.path)
        ).run(connection: .ssh(path: "/srv/quill", host: "feather"))

        XCTAssertTrue(result.isReachable, result.errorMessage ?? "")
        XCTAssertEqual(result.resolvedPath, "/srv/quill")
    }

    func testProbeReturnsBoundedSSHFailureDetail() async throws {
        let root = try makeTempDirectory()
        let fakeSSH = root.appendingPathComponent("fake-ssh")
        try #"""
        #!/bin/sh
        printf 'Permission denied (publickey).\n' >&2
        exit 255
        """#.write(to: fakeSSH, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeSSH.path)

        let result = await SSHRemoteProjectProbe(
            remoteExecutor: SSHRemoteShellExecutor(sshExecutable: fakeSSH.path)
        ).run(connection: .ssh(path: "/srv/quill", host: "feather"))

        XCTAssertFalse(result.isReachable)
        XCTAssertEqual(result.errorMessage, "Permission denied (publickey).")
    }

    func testProbeRejectsSuccessWithoutResolvedFolder() async throws {
        let root = try makeTempDirectory()
        let fakeSSH = root.appendingPathComponent("fake-ssh")
        try #"""
        #!/bin/sh
        printf '__QUILLCODE_SSH_READY__\n'
        """#.write(to: fakeSSH, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeSSH.path)

        let result = await SSHRemoteProjectProbe(
            remoteExecutor: SSHRemoteShellExecutor(sshExecutable: fakeSSH.path)
        ).run(connection: .ssh(path: "/missing", host: "feather"))

        XCTAssertFalse(result.isReachable)
        XCTAssertEqual(result.errorMessage, "SSH connected but did not resolve the remote project folder.")
    }
}
