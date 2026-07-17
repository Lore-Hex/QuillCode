import XCTest

final class ParityAppServerUnixTransportGateTests: QuillCodeParityTestCase {
    func testUnixTransportStaysWiredThroughPlatformRuntimeTestsSmokeAndDocs() throws {
        let root = Self.packageRoot()
        let platform = try text(root, "Sources/QuillCodePlatform/UnixDomainSocket.swift")
        let cPlatform = try text(root, "Sources/CQuillPlatform/cquill_loopback.c")
        let transport = try text(root, "Sources/QuillCodeCLI/AppServerUnixSocketTransport.swift")
        let runner = try text(root, "Sources/QuillCodeCLI/QuillCodeCommandRunner.swift")
        let platformTests = try text(
            root,
            "Tests/QuillCodePlatformTests/UnixDomainSocketTests.swift"
        )
        let cliTests = try text(
            root,
            "Tests/QuillCodeCLITests/AppServerUnixSocketTransportTests.swift"
        )
        let smoke = try text(root, "scripts/app-server-unix-smoke.sh")
        let aggregateSmoke = try text(root, "scripts/smoke.sh")
        let parity = try Self.docsText(named: "CODEX_PARITY_MATRIX.md")
        let decisions = try Self.docsText(named: "DECISIONS.md")

        Self.assertSource(platform, containsAll: [
            "UnixDomainSocketListener",
            "UnixDomainSocketConnection",
            "SocketBlockingIO",
            "ManagedSocketDescriptor",
            "withTaskCancellationHandler"
        ])
        Self.assertSource(cPlatform, containsAll: [
            "cquill_unix_remove_stale_socket",
            "first.st_uid != geteuid()",
            "current.st_ino != first.st_ino",
            "cquill_unix_unlink_if_same"
        ])
        Self.assertSource(transport, containsAll: [
            "app-server-control.sock",
            "AppServerSocketConnectionPool",
            "AppServerWebSocketConnectionHandler",
            ".posixPermissions: NSNumber(value: 0o700)"
        ])
        Self.assertSource(runner, containsAll: [
            "case .unix:",
            "AppServerUnixSocketTransport"
        ])
        Self.assertSource(platformTests, containsAll: [
            "testActiveListenerCannotBeReplaced",
            "testClosePreservesPathReplacedAfterBind",
            "testRegularFileCannotBeReplaced",
            "testBlockedReadsDoNotStarveAdditionalAccepts",
            "testSimultaneousStartsLeaveOneReachableWinner",
            "testStaleOwnedSocketIsRecovered"
        ])
        Self.assertSource(cliTests, containsAll: [
            "testDefaultSocketUsesPrivateControlDirectoryInsideConfiguredHome",
            "testDefaultControlPathRejectsFilesAndSymbolicLinks"
        ])
        Self.assertSource(smoke, containsAll: [
            "socket.AF_UNIX",
            "Sec-WebSocket-Key",
            "forced exit should leave a stale socket",
            "additional = [connect_client() for _ in range(8)]",
            "assert uninitialized.get(\"id\") == request_id"
        ])
        Self.assertSource(aggregateSmoke, contains: "app-server-unix-smoke.sh")
        Self.assertSource(parity, contains: "App-server WebSocket transports")
        Self.assertSource(
            decisions,
            contains: "Unix app-server transport shares protocol behavior without sharing sessions"
        )
    }

    private func text(_ root: URL, _ path: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }
}
