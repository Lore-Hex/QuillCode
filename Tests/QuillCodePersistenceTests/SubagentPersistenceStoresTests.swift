import Foundation
import XCTest
import QuillCodeCore
@testable import QuillCodePersistence

final class SubagentPersistenceStoresTests: PersistenceTestCase {
    func testHiddenThreadStoreRoundTripsAndDeletesChildThread() throws {
        let root = try makeTempDirectory()
        let store = SubagentThreadStore(directory: root.appendingPathComponent("subagent-threads"))
        var child = ChatThread(title: "Subagent: verifier")
        child.messages = [ChatMessage(
            role: .assistant,
            content: "Tests passed",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )]

        try store.save(child)

        let loaded = try store.load(child.id)
        XCTAssertEqual(loaded.id, child.id)
        XCTAssertEqual(loaded.title, child.title)
        XCTAssertEqual(loaded.messages, child.messages)
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: store.directory.path),
            ["\(child.id.uuidString).json"]
        )

        try store.delete(child.id)
        try store.delete(child.id)
        XCTAssertThrowsError(try store.load(child.id))
    }

    func testHiddenThreadStoreDoesNotPopulateNormalThreadDirectory() throws {
        let home = try makeTempDirectory()
        let paths = QuillCodePaths(home: home)
        try paths.ensure()
        let normalStore = JSONThreadStore(directory: paths.threadsDirectory)
        let childStore = SubagentThreadStore(directory: paths.subagentThreadsDirectory)

        try childStore.save(ChatThread(title: "Hidden worker"))

        XCTAssertEqual(try normalStore.list(), [])
    }

    func testApprovalPayloadStoreRoundTripsRawCallAndUsesOwnerOnlyPermissions() throws {
        let root = try makeTempDirectory().appendingPathComponent("approval-payloads")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path)
        let store = SubagentApprovalPayloadStore(directory: root)
        let key = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
        let call = ToolCall(
            id: "call-1",
            name: "shell.run",
            argumentsJSON: #"{"command":"printf secret","environment":{"TOKEN":"raw-value"}}"#
        )

        try store.save(call, key: key)

        XCTAssertEqual(try store.load(key), call)
        XCTAssertEqual(try posixPermissions(at: root), 0o700)
        let file = root.appendingPathComponent("\(key.uuidString).json")
        XCTAssertEqual(try posixPermissions(at: file), 0o600)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), [file.lastPathComponent])
    }

    func testApprovalPayloadStoreAtomicallyReplacesPayloadAndDeletesIdempotently() throws {
        let root = try makeTempDirectory().appendingPathComponent("approval-payloads")
        let store = SubagentApprovalPayloadStore(directory: root)
        let key = UUID()
        let first = ToolCall(id: "call-1", name: "shell.run", argumentsJSON: #"{"command":"whoami"}"#)
        let replacement = ToolCall(id: "call-2", name: "shell.run", argumentsJSON: #"{"command":"pwd"}"#)

        try store.save(first, key: key)
        try store.save(replacement, key: key)

        XCTAssertEqual(try store.load(key), replacement)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path).count, 1)

        try store.delete(key)
        try store.delete(key)
        XCTAssertThrowsError(try store.load(key))
    }

    func testApprovalPayloadLoadRepairsBroadenedPermissions() throws {
        let root = try makeTempDirectory().appendingPathComponent("approval-payloads")
        let store = SubagentApprovalPayloadStore(directory: root)
        let key = UUID()
        let call = ToolCall(name: "shell.run", argumentsJSON: #"{"command":"ls"}"#)
        try store.save(call, key: key)
        let file = root.appendingPathComponent("\(key.uuidString).json")
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)

        XCTAssertEqual(try store.load(key), call)
        XCTAssertEqual(try posixPermissions(at: root), 0o700)
        XCTAssertEqual(try posixPermissions(at: file), 0o600)
    }
}
