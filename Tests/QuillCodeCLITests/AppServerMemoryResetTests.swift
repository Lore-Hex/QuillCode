import Foundation
import QuillCodeAgent
@testable import QuillCodeCLI
import QuillCodeSafety
import XCTest

final class AppServerMemoryResetTests: XCTestCase {
    func testResetClearsOnlyGlobalMemoryAndAcceptsOmittedParams() async throws {
        let fixture = try await makeFixture()
        let globalNested = fixture.home.appendingPathComponent("memories/nested", isDirectory: true)
        try FileManager.default.createDirectory(at: globalNested, withIntermediateDirectories: true)
        try Data("forget".utf8).write(to: globalNested.appendingPathComponent("memory.md"))
        let projectMemory = fixture.workspace
            .appendingPathComponent(".quillcode/memories", isDirectory: true)
            .appendingPathComponent("project.md")
        try FileManager.default.createDirectory(
            at: projectMemory.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("preserve".utf8).write(to: projectMemory)

        try await fixture.request(id: 1, method: "memory/reset", params: nil)
        try await fixture.request(id: 2, method: "memory/reset")

        let records = try await fixture.output.records()
        XCTAssertEqual(fixture.result(id: 1, records: records), [:])
        XCTAssertEqual(fixture.result(id: 2, records: records), [:])
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.globalMemoryRoot.path))
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(
                at: fixture.globalMemoryRoot,
                includingPropertiesForKeys: nil
            ),
            []
        )
        XCTAssertEqual(try Data(contentsOf: projectMemory), Data("preserve".utf8))
    }

    func testResetRejectsSymlinkRootWithoutDeletingItsTarget() async throws {
        let fixture = try await makeFixture()
        let external = fixture.home.appendingPathComponent("external", isDirectory: true)
        try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)
        let sentinel = external.appendingPathComponent("preserve.md")
        try Data("preserve".utf8).write(to: sentinel)
        try FileManager.default.removeItem(at: fixture.globalMemoryRoot)
        try FileManager.default.createSymbolicLink(
            at: fixture.globalMemoryRoot,
            withDestinationURL: external
        )

        try await fixture.request(id: 1, method: "memory/reset")

        let records = try await fixture.output.records()
        let error = try XCTUnwrap(fixture.error(id: 1, records: records))
        XCTAssertEqual(error["code"]?.numberValue, -32603)
        XCTAssertTrue(
            error["message"]?.stringValue?.contains("failed to reset global memory") == true
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: sentinel.path))
    }

    private func makeFixture() async throws -> MemoryResetFixture {
        let home = try temporaryDirectory(named: "home")
        let workspace = try temporaryDirectory(named: "workspace")
        let output = MemoryResetOutputCollector()
        let session = try AppServerSession(
            request: CLIAppServerRequest(live: false, home: home),
            environment: [:],
            currentDirectory: workspace,
            runnerFactory: { configuration in
                AgentRunner(
                    llm: MockLLMClient(),
                    safety: StaticSafetyReviewer(),
                    maxToolSteps: configuration.appConfig.maxToolSteps
                )
            },
            sink: { line in await output.append(line) }
        )
        let fixture = MemoryResetFixture(
            session: session,
            output: output,
            home: home,
            workspace: workspace
        )
        try await fixture.request(
            id: 100,
            method: "initialize",
            params: ["clientInfo": ["name": "MemoryResetTests", "version": "1"]]
        )
        try await fixture.notify(method: "initialized")
        return fixture
    }

    private func temporaryDirectory(named name: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("quillcode-memory-reset-\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }
}

private struct MemoryResetFixture {
    let session: AppServerSession
    let output: MemoryResetOutputCollector
    let home: URL
    let workspace: URL

    var globalMemoryRoot: URL {
        home.appendingPathComponent("memories", isDirectory: true)
    }

    func request(
        id: Int,
        method: String,
        params: [String: Any]? = [:]
    ) async throws {
        var request: [String: Any] = ["id": id, "method": method]
        if let params { request["params"] = params }
        try await send(request)
    }

    func notify(method: String, params: [String: Any] = [:]) async throws {
        try await send(["method": method, "params": params])
    }

    func result(
        id: Int,
        records: [[String: CLIJSONValue]]
    ) -> [String: CLIJSONValue]? {
        records.first { $0["id"]?.numberValue == Double(id) }?["result"]?.objectValue
    }

    func error(
        id: Int,
        records: [[String: CLIJSONValue]]
    ) -> [String: CLIJSONValue]? {
        records.first { $0["id"]?.numberValue == Double(id) }?["error"]?.objectValue
    }

    private func send(_ value: [String: Any]) async throws {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        await session.receive(data)
    }
}

private actor MemoryResetOutputCollector {
    private var lines: [String] = []

    func append(_ line: String) {
        lines.append(line)
    }

    func records() throws -> [[String: CLIJSONValue]] {
        try lines.map { line in
            guard let object = try CLIJSONCodec.decode(line).objectValue else {
                throw MemoryResetTestError.invalidRecord
            }
            return object
        }
    }
}

private enum MemoryResetTestError: Error {
    case invalidRecord
}
