import Foundation
import QuillCodeAgent
@testable import QuillCodeCLI
import QuillCodePersistence
import QuillCodeSafety
import XCTest

final class AppServerFileSystemTests: XCTestCase {
    func testReadWriteSupportsBinaryAndEmptyFiles() async throws {
        let fixture = try await makeSession()
        let binaryPath = fixture.workspace.appendingPathComponent("blob.bin")
        let bytes = Data([0, 1, 2, 255])

        try await fixture.request(
            id: 1,
            method: "fs/writeFile",
            params: ["path": binaryPath.path, "dataBase64": bytes.base64EncodedString()]
        )
        try await fixture.request(id: 2, method: "fs/readFile", params: ["path": binaryPath.path])

        let emptyPath = fixture.workspace.appendingPathComponent("empty.bin")
        try await fixture.request(
            id: 3,
            method: "fs/writeFile",
            params: ["path": emptyPath.path, "dataBase64": ""]
        )
        try await fixture.request(id: 4, method: "fs/readFile", params: ["path": emptyPath.path])

        let records = try await fixture.output.records()
        XCTAssertEqual(result(for: 1, in: records), [:])
        XCTAssertEqual(result(for: 2, in: records)?["dataBase64"]?.stringValue, bytes.base64EncodedString())
        XCTAssertEqual(result(for: 3, in: records), [:])
        XCTAssertEqual(result(for: 4, in: records)?["dataBase64"]?.stringValue, "")
        XCTAssertEqual(try Data(contentsOf: binaryPath), bytes)
        XCTAssertEqual(try Data(contentsOf: emptyPath), Data())
    }

    func testReadFileRejectsOversizedAndNonRegularFilesBeforeReading() async throws {
        let fixture = try await makeSession()
        let oversized = fixture.workspace.appendingPathComponent("oversized.bin")
        XCTAssertTrue(FileManager.default.createFile(atPath: oversized.path, contents: Data()))
        let handle = try FileHandle(forWritingTo: oversized)
        try handle.truncate(atOffset: UInt64(AppServerSession.maximumReadFileBytes + 1))
        try handle.close()

        let fifo = fixture.workspace.appendingPathComponent("named-pipe")
        try makeFIFO(at: fifo)

        try await fixture.request(id: 1, method: "fs/readFile", params: ["path": oversized.path])
        try await fixture.request(id: 2, method: "fs/readFile", params: ["path": fifo.path])

        let records = try await fixture.output.records()
        XCTAssertEqual(errorCode(for: 1, in: records), -32_600)
        XCTAssertEqual(
            errorMessage(for: 1, in: records),
            "file is too large to read: limit is \(AppServerSession.maximumReadFileBytes) bytes"
        )
        XCTAssertEqual(errorCode(for: 2, in: records), -32_600)
        XCTAssertEqual(errorMessage(for: 2, in: records), "path `\(fifo.path)` is not a file")
    }

    func testCreateDirectoryDefaultsToRecursiveAndHonorsFalse() async throws {
        let fixture = try await makeSession()
        let nested = fixture.workspace.appendingPathComponent("one/two", isDirectory: true)
        try await fixture.request(id: 1, method: "fs/createDirectory", params: ["path": nested.path])

        let missingParent = fixture.workspace.appendingPathComponent("missing/child", isDirectory: true)
        try await fixture.request(
            id: 2,
            method: "fs/createDirectory",
            params: ["path": missingParent.path, "recursive": false]
        )

        let direct = fixture.workspace.appendingPathComponent("direct", isDirectory: true)
        try await fixture.request(
            id: 3,
            method: "fs/createDirectory",
            params: ["path": direct.path, "recursive": false]
        )

        let records = try await fixture.output.records()
        XCTAssertEqual(result(for: 1, in: records), [:])
        XCTAssertTrue(nested.hasDirectoryPath && FileManager.default.fileExists(atPath: nested.path))
        XCTAssertEqual(errorCode(for: 2, in: records), -32_603)
        XCTAssertFalse(FileManager.default.fileExists(atPath: missingParent.path))
        XCTAssertEqual(result(for: 3, in: records), [:])
        XCTAssertTrue(FileManager.default.fileExists(atPath: direct.path))
    }

    func testMetadataAndDirectoryEntriesMatchCodexShapes() async throws {
        let fixture = try await makeSession()
        let directory = fixture.workspace.appendingPathComponent("notes", isDirectory: true)
        let file = fixture.workspace.appendingPathComponent("note.txt")
        let link = fixture.workspace.appendingPathComponent("note-link.txt")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        try Data("hello".utf8).write(to: file)
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: file.path)

        try await fixture.request(id: 1, method: "fs/getMetadata", params: ["path": file.path])
        try await fixture.request(id: 2, method: "fs/getMetadata", params: ["path": directory.path])
        try await fixture.request(id: 3, method: "fs/getMetadata", params: ["path": link.path])
        try await fixture.request(id: 4, method: "fs/readDirectory", params: ["path": fixture.workspace.path])

        let records = try await fixture.output.records()
        let fileMetadata = try XCTUnwrap(result(for: 1, in: records))
        XCTAssertEqual(Set(fileMetadata.keys), metadataKeys)
        XCTAssertEqual(fileMetadata["isDirectory"]?.boolValue, false)
        XCTAssertEqual(fileMetadata["isFile"]?.boolValue, true)
        XCTAssertEqual(fileMetadata["isSymlink"]?.boolValue, false)
        XCTAssertGreaterThan(fileMetadata["modifiedAtMs"]?.numberValue ?? 0, 0)

        let directoryMetadata = try XCTUnwrap(result(for: 2, in: records))
        XCTAssertEqual(directoryMetadata["isDirectory"]?.boolValue, true)
        XCTAssertEqual(directoryMetadata["isFile"]?.boolValue, false)
        XCTAssertEqual(directoryMetadata["isSymlink"]?.boolValue, false)

        let linkMetadata = try XCTUnwrap(result(for: 3, in: records))
        XCTAssertEqual(linkMetadata["isDirectory"]?.boolValue, false)
        XCTAssertEqual(linkMetadata["isFile"]?.boolValue, true)
        XCTAssertEqual(linkMetadata["isSymlink"]?.boolValue, true)

        let entries = try XCTUnwrap(
            result(for: 4, in: records)?["entries"]?.arrayValue?.compactMap(\.objectValue)
        )
        XCTAssertEqual(entries.map { $0["fileName"]?.stringValue }, ["note-link.txt", "note.txt", "notes"])
        XCTAssertEqual(Set(entries[0].keys), ["fileName", "isDirectory", "isFile"])
        XCTAssertEqual(entries[0]["isFile"]?.boolValue, true)
        XCTAssertEqual(entries[2]["isDirectory"]?.boolValue, true)
    }

    func testRemoveDefaultsRecursiveAndForceAndHonorsFalse() async throws {
        let fixture = try await makeSession()
        let tree = fixture.workspace.appendingPathComponent("tree/child", isDirectory: true)
        try FileManager.default.createDirectory(at: tree, withIntermediateDirectories: true)
        try Data("content".utf8).write(to: tree.appendingPathComponent("note.txt"))

        try await fixture.request(
            id: 1,
            method: "fs/remove",
            params: ["path": fixture.workspace.appendingPathComponent("tree").path, "recursive": false]
        )
        try await fixture.request(
            id: 2,
            method: "fs/remove",
            params: ["path": fixture.workspace.appendingPathComponent("tree").path]
        )

        let missing = fixture.workspace.appendingPathComponent("missing")
        try await fixture.request(id: 3, method: "fs/remove", params: ["path": missing.path])
        try await fixture.request(
            id: 4,
            method: "fs/remove",
            params: ["path": missing.path, "force": false]
        )

        let empty = fixture.workspace.appendingPathComponent("empty", isDirectory: true)
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: false)
        try await fixture.request(
            id: 5,
            method: "fs/remove",
            params: ["path": empty.path, "recursive": false]
        )

        let records = try await fixture.output.records()
        XCTAssertEqual(errorCode(for: 1, in: records), -32_603)
        XCTAssertEqual(result(for: 2, in: records), [:])
        XCTAssertFalse(FileManager.default.fileExists(atPath: tree.deletingLastPathComponent().path))
        XCTAssertEqual(result(for: 3, in: records), [:])
        XCTAssertEqual(errorCode(for: 4, in: records), -32_603)
        XCTAssertEqual(result(for: 5, in: records), [:])
        XCTAssertFalse(FileManager.default.fileExists(atPath: empty.path))
    }

    func testCopyMergesTreesOverwritesFilesAndPreservesSymlinks() async throws {
        let fixture = try await makeSession()
        let source = fixture.workspace.appendingPathComponent("source", isDirectory: true)
        let nested = source.appendingPathComponent("nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let sourceFile = nested.appendingPathComponent("note.txt")
        try Data("new content".utf8).write(to: sourceFile)
        try FileManager.default.createSymbolicLink(
            atPath: source.appendingPathComponent("nested-link").path,
            withDestinationPath: "nested"
        )

        let destination = fixture.workspace.appendingPathComponent("parent/copied", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let destinationFile = destination.appendingPathComponent("nested/note.txt")
        try FileManager.default.createDirectory(
            at: destinationFile.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("old".utf8).write(to: destinationFile)
        try Data("keep".utf8).write(to: destination.appendingPathComponent("existing.txt"))

        try await fixture.request(
            id: 1,
            method: "fs/copy",
            params: [
                "sourcePath": source.path,
                "destinationPath": destination.path,
                "recursive": true
            ]
        )

        let standalone = fixture.workspace.appendingPathComponent("standalone.txt")
        try Data("first".utf8).write(to: standalone)
        let standaloneCopy = fixture.workspace.appendingPathComponent("standalone-copy.txt")
        try Data("stale".utf8).write(to: standaloneCopy)
        try await fixture.request(
            id: 2,
            method: "fs/copy",
            params: ["sourcePath": standalone.path, "destinationPath": standaloneCopy.path]
        )

        let records = try await fixture.output.records()
        XCTAssertEqual(result(for: 1, in: records), [:])
        XCTAssertEqual(try String(contentsOf: destinationFile, encoding: .utf8), "new content")
        XCTAssertEqual(
            try String(contentsOf: destination.appendingPathComponent("existing.txt"), encoding: .utf8),
            "keep"
        )
        let copiedLink = destination.appendingPathComponent("nested-link")
        XCTAssertTrue(try copiedLink.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true)
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: copiedLink.path), "nested")
        XCTAssertEqual(result(for: 2, in: records), [:])
        XCTAssertEqual(try String(contentsOf: standaloneCopy, encoding: .utf8), "first")
    }

    func testCopyRejectsUnsafeAndUnsupportedSources() async throws {
        let fixture = try await makeSession()
        let source = fixture.workspace.appendingPathComponent("source", isDirectory: true)
        try FileManager.default.createDirectory(
            at: source.appendingPathComponent("nested", isDirectory: true),
            withIntermediateDirectories: true
        )

        try await fixture.request(
            id: 1,
            method: "fs/copy",
            params: [
                "sourcePath": source.path,
                "destinationPath": fixture.workspace.appendingPathComponent("copy").path
            ]
        )
        try await fixture.request(
            id: 2,
            method: "fs/copy",
            params: [
                "sourcePath": source.path,
                "destinationPath": source.appendingPathComponent("nested/copy").path,
                "recursive": true
            ]
        )

        let alias = fixture.workspace.appendingPathComponent("source-alias")
        try FileManager.default.createSymbolicLink(atPath: alias.path, withDestinationPath: source.path)
        try await fixture.request(
            id: 3,
            method: "fs/copy",
            params: [
                "sourcePath": source.path,
                "destinationPath": alias.appendingPathComponent("through-alias").path,
                "recursive": true
            ]
        )

        let fifo = fixture.workspace.appendingPathComponent("named-pipe")
        try makeFIFO(at: fifo)
        try await fixture.request(
            id: 4,
            method: "fs/copy",
            params: [
                "sourcePath": fifo.path,
                "destinationPath": fixture.workspace.appendingPathComponent("fifo-copy").path
            ]
        )

        let records = try await fixture.output.records()
        for id in 1...4 {
            XCTAssertEqual(errorCode(for: id, in: records), -32_600)
        }
        XCTAssertEqual(
            errorMessage(for: 1, in: records),
            "fs/copy requires recursive: true when sourcePath is a directory"
        )
        XCTAssertEqual(
            errorMessage(for: 2, in: records),
            "fs/copy cannot copy a directory to itself or one of its descendants"
        )
        XCTAssertEqual(errorMessage(for: 3, in: records), errorMessage(for: 2, in: records))
        XCTAssertEqual(
            errorMessage(for: 4, in: records),
            "fs/copy only supports regular files, directories, and symlinks"
        )
    }

    func testRecursiveCopySkipsSpecialChildren() async throws {
        let fixture = try await makeSession()
        let source = fixture.workspace.appendingPathComponent("source", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try Data("hello".utf8).write(to: source.appendingPathComponent("note.txt"))
        try makeFIFO(at: source.appendingPathComponent("named-pipe"))
        let destination = fixture.workspace.appendingPathComponent("copied", isDirectory: true)

        try await fixture.request(
            id: 1,
            method: "fs/copy",
            params: [
                "sourcePath": source.path,
                "destinationPath": destination.path,
                "recursive": true
            ]
        )

        let records = try await fixture.output.records()
        XCTAssertEqual(result(for: 1, in: records), [:])
        XCTAssertEqual(
            try String(contentsOf: destination.appendingPathComponent("note.txt"), encoding: .utf8),
            "hello"
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.appendingPathComponent("named-pipe").path))
    }

    func testFilesystemMethodsRejectRelativePathsAndInvalidBase64() async throws {
        let fixture = try await makeSession()
        let absolute = fixture.workspace.appendingPathComponent("absolute.txt")
        try Data("hello".utf8).write(to: absolute)

        let requests: [(String, [String: Any])] = [
            ("fs/readFile", ["path": "relative.txt"]),
            ("fs/writeFile", ["path": "relative.txt", "dataBase64": ""]),
            ("fs/createDirectory", ["path": "relative-dir"]),
            ("fs/getMetadata", ["path": "relative.txt"]),
            ("fs/readDirectory", ["path": "relative-dir"]),
            ("fs/remove", ["path": "relative.txt"]),
            ("fs/copy", ["sourcePath": "relative.txt", "destinationPath": absolute.path]),
            ("fs/copy", ["sourcePath": absolute.path, "destinationPath": "relative-copy.txt"]),
            ("fs/watch", ["watchId": "relative", "path": "relative.txt"])
        ]
        for (offset, request) in requests.enumerated() {
            try await fixture.request(id: offset + 1, method: request.0, params: request.1)
        }
        try await fixture.request(
            id: 100,
            method: "fs/writeFile",
            params: ["path": absolute.path, "dataBase64": "%%%"]
        )

        let records = try await fixture.output.records()
        for id in 1...requests.count {
            XCTAssertEqual(errorCode(for: id, in: records), -32_600)
            XCTAssertEqual(
                errorMessage(for: id, in: records),
                "Invalid request: AbsolutePathBuf deserialized without a base path"
            )
        }
        XCTAssertEqual(errorCode(for: 100, in: records), -32_600)
        XCTAssertTrue(
            errorMessage(for: 100, in: records)?
                .hasPrefix("fs/writeFile requires valid base64 dataBase64:") == true
        )
    }

    func testDirectoryWatchReportsImmediateChildChangeAndUnwatchStopsNotifications() async throws {
        let fixture = try await makeSession()
        let directory = fixture.workspace.appendingPathComponent("repo/.git", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let changed = directory.appendingPathComponent("FETCH_HEAD")

        try await fixture.request(
            id: 1,
            method: "fs/watch",
            params: ["watchId": "git-dir", "path": directory.path]
        )
        try Data("updated\n".utf8).write(to: changed)

        let notification = try await fixture.output.waitForNotification(
            method: "fs/changed",
            watchID: "git-dir"
        )
        XCTAssertEqual(notification["watchId"]?.stringValue, "git-dir")
        XCTAssertEqual(notification["changedPaths"]?.arrayValue?.compactMap(\.stringValue), [changed.path])

        try await fixture.request(id: 2, method: "fs/unwatch", params: ["watchId": "git-dir"])
        let countAfterUnwatch = try await fixture.output.notificationCount(method: "fs/changed")
        try Data("refs\n".utf8).write(to: directory.appendingPathComponent("packed-refs"))
        try await Task.sleep(nanoseconds: 500_000_000)

        let records = try await fixture.output.records()
        let finalNotificationCount = try await fixture.output.notificationCount(method: "fs/changed")
        XCTAssertEqual(result(for: 1, in: records)?["path"]?.stringValue, directory.path)
        XCTAssertEqual(result(for: 2, in: records), [:])
        XCTAssertEqual(finalNotificationCount, countAfterUnwatch)
    }

    func testFileWatchesReportAtomicReplacementAndMissingTargetCreation() async throws {
        let fixture = try await makeSession()
        let directory = fixture.workspace.appendingPathComponent("repo/.git", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let head = directory.appendingPathComponent("HEAD")
        try Data("main\n".utf8).write(to: head)
        let missing = directory.appendingPathComponent("FETCH_HEAD")

        try await fixture.request(
            id: 1,
            method: "fs/watch",
            params: ["watchId": "head", "path": head.path]
        )
        try await fixture.request(
            id: 2,
            method: "fs/watch",
            params: ["watchId": "fetch", "path": missing.path]
        )
        try replaceAtomically(head, with: Data("feature\n".utf8))
        try replaceAtomically(missing, with: Data("origin/main\n".utf8))

        let headChange = try await fixture.output.waitForNotification(method: "fs/changed", watchID: "head")
        let fetchChange = try await fixture.output.waitForNotification(method: "fs/changed", watchID: "fetch")
        XCTAssertEqual(headChange["changedPaths"]?.arrayValue?.compactMap(\.stringValue), [head.path])
        XCTAssertEqual(fetchChange["changedPaths"]?.arrayValue?.compactMap(\.stringValue), [missing.path])
    }

    func testDuplicateWatchIsRejectedAndDisconnectCancelsNotifications() async throws {
        let fixture = try await makeSession()
        let watched = fixture.workspace.appendingPathComponent("watched")
        try Data("before".utf8).write(to: watched)

        try await fixture.request(
            id: 1,
            method: "fs/watch",
            params: ["watchId": "same", "path": watched.path]
        )
        try await fixture.request(
            id: 2,
            method: "fs/watch",
            params: ["watchId": "same", "path": fixture.workspace.path]
        )

        await fixture.session.finishInput()
        let countAtDisconnect = try await fixture.output.notificationCount(method: "fs/changed")
        try Data("after".utf8).write(to: watched)
        try await Task.sleep(nanoseconds: 500_000_000)

        let records = try await fixture.output.records()
        let finalNotificationCount = try await fixture.output.notificationCount(method: "fs/changed")
        XCTAssertEqual(result(for: 1, in: records)?["path"]?.stringValue, watched.path)
        XCTAssertEqual(errorCode(for: 2, in: records), -32_600)
        XCTAssertEqual(errorMessage(for: 2, in: records), "watchId already exists: same")
        XCTAssertEqual(finalNotificationCount, countAtDisconnect)
    }

    private let metadataKeys: Set<String> = [
        "isDirectory", "isFile", "isSymlink", "createdAtMs", "modifiedAtMs"
    ]

    private func makeSession() async throws -> FileSystemFixture {
        let home = try temporaryDirectory(prefix: "app-server-fs-home")
        let workspace = try temporaryDirectory(prefix: "app-server-fs-workspace")
        let output = FileSystemOutputCollector()
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
        let fixture = FileSystemFixture(
            session: session,
            output: output,
            workspace: workspace
        )
        try await fixture.request(
            id: 10_000,
            method: "initialize",
            params: ["clientInfo": ["name": "FileSystemTests", "version": "1"]]
        )
        try await fixture.notify(method: "initialized")
        return fixture
    }

    private func result(
        for id: Int,
        in records: [[String: CLIJSONValue]]
    ) -> [String: CLIJSONValue]? {
        records.first { $0["id"]?.numberValue == Double(id) }?["result"]?.objectValue
    }

    private func errorCode(for id: Int, in records: [[String: CLIJSONValue]]) -> Double? {
        records.first { $0["id"]?.numberValue == Double(id) }?["error"]?
            .objectValue?["code"]?.numberValue
    }

    private func errorMessage(for id: Int, in records: [[String: CLIJSONValue]]) -> String? {
        records.first { $0["id"]?.numberValue == Double(id) }?["error"]?
            .objectValue?["message"]?.stringValue
    }

    private func temporaryDirectory(prefix: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("quillcode-\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }

    private func makeFIFO(at url: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["mkfifo", url.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw FileSystemTestError.fifoCreationFailed(process.terminationStatus)
        }
    }

    private func replaceAtomically(_ destination: URL, with data: Data) throws {
        let temporary = destination.appendingPathExtension("replacement")
        try data.write(to: temporary)
        if FileManager.default.fileExists(atPath: destination.path) {
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: temporary)
        } else {
            try FileManager.default.moveItem(at: temporary, to: destination)
        }
    }
}

private struct FileSystemFixture {
    let session: AppServerSession
    let output: FileSystemOutputCollector
    let workspace: URL

    func request(id: Int, method: String, params: [String: Any] = [:]) async throws {
        try await send(["id": id, "method": method, "params": params])
    }

    func notify(method: String, params: [String: Any] = [:]) async throws {
        try await send(["method": method, "params": params])
    }

    private func send(_ object: [String: Any]) async throws {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        await session.receive(data)
    }
}

private actor FileSystemOutputCollector {
    private var lines: [String] = []

    func append(_ line: String) {
        lines.append(line)
    }

    func records() throws -> [[String: CLIJSONValue]] {
        try lines.map { line in
            guard let record = try CLIJSONCodec.decode(line).objectValue else {
                throw FileSystemTestError.invalidRecord
            }
            return record
        }
    }

    func notificationCount(method: String) throws -> Int {
        try records().count { $0["method"]?.stringValue == method }
    }

    func waitForNotification(
        method: String,
        watchID: String,
        timeoutNanoseconds: UInt64 = 3_000_000_000
    ) async throws -> [String: CLIJSONValue] {
        let deadline = ContinuousClock.now + .nanoseconds(Int64(timeoutNanoseconds))
        while ContinuousClock.now < deadline {
            if let params = try records().lazy.compactMap({ record -> [String: CLIJSONValue]? in
                guard record["method"]?.stringValue == method else { return nil }
                return record["params"]?.objectValue
            }).first(where: { $0["watchId"]?.stringValue == watchID }) {
                return params
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        throw FileSystemTestError.timedOut(method: method, watchID: watchID)
    }
}

private enum FileSystemTestError: Error {
    case fifoCreationFailed(Int32)
    case invalidRecord
    case timedOut(method: String, watchID: String)
}
