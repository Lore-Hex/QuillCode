import Foundation
import XCTest
@testable import QuillCodeTools

final class LSPSessionManagerTests: XCTestCase {
    private let workspace = URL(fileURLWithPath: "/tmp/quillcode-lsp-sm")

    /// A registry whose command always resolves to a fixed availability.
    private func registry(available: Bool) -> LSPServerRegistry {
        LSPServerRegistry(
            configs: LSPServerRegistry.defaults,
            commandLocator: StubCommandLocator(resolvedPath: available ? "/usr/bin/sourcekit-lsp" : nil)
        )
    }

    /// A launcher whose transport auto-answers `initialize` so the handshake succeeds.
    private func handshakeLauncher() -> StubLSPServerLauncher {
        StubLSPServerLauncher {
            let server = StubLanguageServer()
            server.initializeResult = ["capabilities": [:]]
            return server
        }
    }

    func testUnsupportedExtensionHasNoServer() {
        let manager = LSPSessionManager(workspaceRoot: workspace, registry: registry(available: true), launcher: handshakeLauncher())
        XCTAssertFalse(manager.hasServer(forPath: "/tmp/quillcode-lsp-sm/readme.md"))
        XCTAssertNil(manager.client(forPath: "/tmp/quillcode-lsp-sm/readme.md"))
    }

    func testMissingServerReturnsNilAndOneTimeNotice() {
        let manager = LSPSessionManager(workspaceRoot: workspace, registry: registry(available: false), launcher: handshakeLauncher())
        XCTAssertTrue(manager.hasServer(forPath: "/tmp/quillcode-lsp-sm/A.swift"), "config exists even though binary is missing")
        XCTAssertNil(manager.client(forPath: "/tmp/quillcode-lsp-sm/A.swift"))

        let notice = manager.consumeUnavailableNoticeIfNeeded(forPath: "/tmp/quillcode-lsp-sm/A.swift")
        XCTAssertNotNil(notice)
        XCTAssertTrue(notice!.contains("not available"))
        // Second call is suppressed (one-time).
        XCTAssertNil(manager.consumeUnavailableNoticeIfNeeded(forPath: "/tmp/quillcode-lsp-sm/A.swift"))
    }

    func testAvailableServerLaunchesOnceAndIsReused() throws {
        let launcher = handshakeLauncher()
        let manager = LSPSessionManager(workspaceRoot: workspace, registry: registry(available: true), launcher: launcher)
        let first = manager.client(forPath: "/tmp/quillcode-lsp-sm/A.swift")
        let second = manager.client(forPath: "/tmp/quillcode-lsp-sm/B.swift")
        XCTAssertNotNil(first)
        XCTAssertNotNil(second)
        XCTAssertEqual(launcher.launchCount, 1, "the same sourcekit-lsp serves all .swift files")
    }

    func testCrashedServerIsRelaunched() throws {
        let launcher = handshakeLauncher()
        let manager = LSPSessionManager(workspaceRoot: workspace, registry: registry(available: true), launcher: launcher)
        XCTAssertNotNil(manager.client(forPath: "/tmp/quillcode-lsp-sm/A.swift"))
        XCTAssertEqual(launcher.launchCount, 1)

        // Simulate a crash: the launched process reports not running.
        launcher.lastProcess?.running = false
        XCTAssertNotNil(manager.client(forPath: "/tmp/quillcode-lsp-sm/A.swift"))
        XCTAssertEqual(launcher.launchCount, 2, "a dead server should be relaunched")
    }

    func testCrashedServerTransportIsClosedOnRelaunch() throws {
        // Track the transport handed to each launch so we can assert the dead one was closed (fds
        // released) before the relaunch, not leaked.
        final class Box: @unchecked Sendable { var servers: [StubLanguageServer] = [] }
        let box = Box()
        let launcher = StubLSPServerLauncher {
            let server = StubLanguageServer()
            server.initializeResult = ["capabilities": [:]]
            box.servers.append(server)
            return server
        }
        let manager = LSPSessionManager(workspaceRoot: workspace, registry: registry(available: true), launcher: launcher)
        XCTAssertNotNil(manager.client(forPath: "/tmp/quillcode-lsp-sm/A.swift"))
        launcher.lastProcess?.running = false
        XCTAssertNotNil(manager.client(forPath: "/tmp/quillcode-lsp-sm/A.swift"))
        XCTAssertEqual(box.servers.count, 2)
        XCTAssertTrue(box.servers[0].transportClosed, "the dead session's transport must be closed on relaunch")
    }

    func testShutdownClosesTransports() throws {
        final class Box: @unchecked Sendable { var server: StubLanguageServer? }
        let box = Box()
        let launcher = StubLSPServerLauncher {
            let server = StubLanguageServer()
            server.initializeResult = ["capabilities": [:]]
            box.server = server
            return server
        }
        let manager = LSPSessionManager(workspaceRoot: workspace, registry: registry(available: true), launcher: launcher)
        XCTAssertNotNil(manager.client(forPath: "/tmp/quillcode-lsp-sm/A.swift"))
        manager.shutdown()
        XCTAssertTrue(box.server?.transportClosed ?? false, "shutdown must close each server's transport")
    }

    func testPoisonedClientIsEvictedAndRelaunched() throws {
        // Track every launched stub server so we can corrupt the first one's stream and assert the
        // manager hands back a fresh, healthy client on the next request.
        final class Box: @unchecked Sendable { var servers: [StubLanguageServer] = [] }
        let box = Box()
        let launcher = StubLSPServerLauncher {
            let server = StubLanguageServer()
            server.initializeResult = ["capabilities": [:]]
            box.servers.append(server)
            return server
        }
        let manager = LSPSessionManager(workspaceRoot: workspace, registry: registry(available: true), launcher: launcher)

        let first = try XCTUnwrap(manager.client(forPath: "/tmp/quillcode-lsp-sm/A.swift"))
        XCTAssertTrue(first.isHealthy)
        // Make the server leak a malformed frame on the next request, then make that request so the
        // client poisons itself.
        box.servers[0].corruptNextResponse = true
        XCTAssertThrowsError(try first.definition(path: "/tmp/quillcode-lsp-sm/A.swift", line: 1, character: 0))
        XCTAssertFalse(first.isHealthy)

        // The manager must NOT hand back the poisoned client; it evicts + relaunches and returns a new,
        // healthy one — nav recovers rather than being permanently broken.
        let second = try XCTUnwrap(manager.client(forPath: "/tmp/quillcode-lsp-sm/A.swift"))
        XCTAssertTrue(second.isHealthy)
        XCTAssertFalse(second === first, "a fresh client must replace the poisoned one")
        XCTAssertEqual(box.servers.count, 2, "the server was relaunched")
        XCTAssertTrue(box.servers[0].transportClosed, "the poisoned session's transport must be closed")
    }

    func testRepeatedCrashesDisableAfterMaxRestarts() {
        let launcher = handshakeLauncher()
        let manager = LSPSessionManager(workspaceRoot: workspace, registry: registry(available: true), launcher: launcher)
        // Each call: launch (or reuse), then kill it so the next call must relaunch.
        for _ in 0...(LSPSessionManager.maxRestarts + 2) {
            _ = manager.client(forPath: "/tmp/quillcode-lsp-sm/A.swift")
            launcher.lastProcess?.running = false
        }
        // After exhausting the restart budget, the server is disabled: no further launches.
        let before = launcher.launchCount
        XCTAssertNil(manager.client(forPath: "/tmp/quillcode-lsp-sm/A.swift"))
        XCTAssertEqual(launcher.launchCount, before, "a repeatedly-crashing server is disabled, not relaunched forever")
    }

    func testFailedHandshakeDoesNotWedge() {
        // Launcher whose transport never answers initialize -> handshake times out -> launch fails.
        // A short initializeTimeout keeps the test fast while proving the manager gives up, not hangs.
        let launcher = StubLSPServerLauncher { ScriptedLSPTransport() }
        let manager = LSPSessionManager(
            workspaceRoot: workspace,
            registry: registry(available: true),
            launcher: launcher,
            initializeTimeout: 0.3
        )
        XCTAssertNil(manager.client(forPath: "/tmp/quillcode-lsp-sm/A.swift"))
    }
}

final class LSPServerRegistryTests: XCTestCase {
    func testSwiftIsTheShippedDefault() {
        let registry = LSPServerRegistry(commandLocator: StubCommandLocator(resolvedPath: "/x"))
        let config = registry.config(forPath: "/ws/Main.swift")
        XCTAssertEqual(config?.command, "sourcekit-lsp")
        XCTAssertEqual(config?.languageID, "swift")
    }

    func testUnknownExtensionHasNoConfig() {
        let registry = LSPServerRegistry(commandLocator: StubCommandLocator(resolvedPath: "/x"))
        XCTAssertNil(registry.config(forPath: "/ws/notes.txt"))
        XCTAssertNil(registry.config(forPath: "/ws/noextension"))
    }

    func testResolveExecutableReflectsAvailability() {
        let present = LSPServerRegistry(commandLocator: StubCommandLocator(resolvedPath: "/usr/bin/sourcekit-lsp"))
        let absent = LSPServerRegistry(commandLocator: StubCommandLocator(resolvedPath: nil))
        let config = LSPServerConfig(fileExtensions: ["swift"], languageID: "swift", command: "sourcekit-lsp")
        XCTAssertEqual(present.resolveExecutable(for: config), "/usr/bin/sourcekit-lsp")
        XCTAssertNil(absent.resolveExecutable(for: config))
    }

    func testGenericTableSupportsOtherLanguages() {
        let registry = LSPServerRegistry(
            configs: [LSPServerConfig(fileExtensions: ["ts", "tsx"], languageID: "typescript", command: "typescript-language-server")],
            commandLocator: StubCommandLocator(resolvedPath: "/x")
        )
        XCTAssertEqual(registry.config(forPath: "/ws/app.tsx")?.languageID, "typescript")
        XCTAssertNil(registry.config(forPath: "/ws/app.swift"))
    }
}
