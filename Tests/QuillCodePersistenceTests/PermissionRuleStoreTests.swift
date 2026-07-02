import XCTest
import QuillCodeSafety
@testable import QuillCodePersistence

final class PermissionRuleStoreTests: XCTestCase {
    private func makeDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("PermissionRuleStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }

    private func makeStoreAndRoot() throws -> (PermissionRuleFileStore, URL) {
        let base = try makeDirectory()
        let store = PermissionRuleFileStore(directory: base.appendingPathComponent("permissions"))
        let root = base.appendingPathComponent("project", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return (store, root)
    }

    func testLoadWithoutFileReturnsEmptyTableAndNoDiagnostics() throws {
        let (store, root) = try makeStoreAndRoot()
        let result = store.load(forWorkspaceRoot: root)
        XCTAssertTrue(result.table.isEmpty)
        XCTAssertTrue(result.diagnostics.isEmpty)
    }

    func testSaveLoadRoundTrip() throws {
        let (store, root) = try makeStoreAndRoot()
        let rules = [
            PermissionRule(action: "host.shell.run", resource: "swift test", match: .exact, decision: .allow),
            PermissionRule(action: "host.file.write", resource: "\(root.path)/secrets/**", decision: .deny),
            PermissionRule(action: "host.git.push", resource: "**", decision: .ask)
        ]
        try store.save(PermissionRuleTable(rules: rules), forWorkspaceRoot: root)

        let loaded = store.load(forWorkspaceRoot: root)
        XCTAssertEqual(loaded.table.rules, rules)
        XCTAssertTrue(loaded.diagnostics.isEmpty)
    }

    func testAppendCreatesFileAndAccumulates() throws {
        let (store, root) = try makeStoreAndRoot()
        let first = PermissionRule(action: "host.shell.run", resource: "swift build", match: .exact, decision: .allow)
        let second = PermissionRule(action: "host.shell.run", resource: "swift test", match: .exact, decision: .allow)

        XCTAssertTrue(try store.append(first, forWorkspaceRoot: root).isEmpty)
        XCTAssertTrue(try store.append(second, forWorkspaceRoot: root).isEmpty)

        let loaded = store.load(forWorkspaceRoot: root)
        XCTAssertEqual(loaded.table.rules, [first, second])
    }

    func testWorkspacesAreIsolated() throws {
        let base = try makeDirectory()
        let store = PermissionRuleFileStore(directory: base.appendingPathComponent("permissions"))
        let rootA = base.appendingPathComponent("project-a", isDirectory: true)
        let rootB = base.appendingPathComponent("project-b", isDirectory: true)
        try FileManager.default.createDirectory(at: rootA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: rootB, withIntermediateDirectories: true)

        try store.append(
            PermissionRule(action: "host.shell.run", resource: "swift test", match: .exact, decision: .allow),
            forWorkspaceRoot: rootA
        )

        XCTAssertEqual(store.load(forWorkspaceRoot: rootA).table.rules.count, 1)
        XCTAssertTrue(store.load(forWorkspaceRoot: rootB).table.isEmpty)
        XCTAssertNotEqual(store.fileURL(forWorkspaceRoot: rootA), store.fileURL(forWorkspaceRoot: rootB))
    }

    func testWorkspaceSpellingsShareOneTable() throws {
        let (store, root) = try makeStoreAndRoot()
        try store.append(
            PermissionRule(action: "host.shell.run", resource: "swift test", match: .exact, decision: .allow),
            forWorkspaceRoot: root
        )
        // `..`-spelled and trailing-slash-spelled roots must resolve to the same rules file.
        let respelled = root.appendingPathComponent("sub/..")
        XCTAssertEqual(store.fileURL(forWorkspaceRoot: respelled), store.fileURL(forWorkspaceRoot: root))
        XCTAssertEqual(store.load(forWorkspaceRoot: respelled).table.rules.count, 1)
    }

    func testCorruptFileDegradesToEmptyTableWithDiagnostic() throws {
        let (store, root) = try makeStoreAndRoot()
        let fileURL = store.fileURL(forWorkspaceRoot: root)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("{not json!!".utf8).write(to: fileURL)

        let loaded = store.load(forWorkspaceRoot: root)
        XCTAssertTrue(loaded.table.isEmpty)
        XCTAssertEqual(loaded.diagnostics.count, 1)
        XCTAssertTrue(try XCTUnwrap(loaded.diagnostics.first).contains("not valid JSON"))
        // A plain load must not mutate the file.
        XCTAssertEqual(try Data(contentsOf: fileURL), Data("{not json!!".utf8))
    }

    func testAppendOverCorruptFileBacksItUpAndStartsFresh() throws {
        let (store, root) = try makeStoreAndRoot()
        let fileURL = store.fileURL(forWorkspaceRoot: root)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("garbage".utf8).write(to: fileURL)

        let rule = PermissionRule(action: "host.shell.run", resource: "swift test", match: .exact, decision: .allow)
        let diagnostics = try store.append(rule, forWorkspaceRoot: root)

        XCTAssertFalse(diagnostics.isEmpty)
        XCTAssertEqual(store.load(forWorkspaceRoot: root).table.rules, [rule])
        // The corrupt payload survives as a backup next to the fresh file.
        let siblings = try FileManager.default.contentsOfDirectory(
            at: fileURL.deletingLastPathComponent(),
            includingPropertiesForKeys: nil
        )
        XCTAssertTrue(
            siblings.contains { $0.lastPathComponent.contains("corrupt") },
            "expected a corrupt-file backup, found \(siblings.map(\.lastPathComponent))"
        )
    }

    func testMalformedRuleIsSkippedWithoutDroppingTheRest() throws {
        let (store, root) = try makeStoreAndRoot()
        let fileURL = store.fileURL(forWorkspaceRoot: root)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let json = """
        {"version":1,"rules":[
            {"action":"host.shell.run","resource":"swift test","match":"exact","decision":"allow"},
            {"action":"host.shell.run","resource":"swift build","decision":"launch-the-missiles"},
            {"resource":"missing action","decision":"deny"},
            {"action":"host.git.push","resource":"**","decision":"deny"}
        ]}
        """
        try Data(json.utf8).write(to: fileURL)

        let loaded = store.load(forWorkspaceRoot: root)
        XCTAssertEqual(loaded.table.rules.count, 2)
        XCTAssertEqual(loaded.table.rules.first?.resource, "swift test")
        XCTAssertEqual(loaded.table.rules.last?.action, "host.git.push")
        XCTAssertEqual(loaded.diagnostics.count, 1)
        XCTAssertTrue(try XCTUnwrap(loaded.diagnostics.first).contains("2 malformed rules"))
    }

    func testNewerFileVersionIsLeftAloneAndRefusesAppend() throws {
        let (store, root) = try makeStoreAndRoot()
        let fileURL = store.fileURL(forWorkspaceRoot: root)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let newer = #"{"version":99,"rules":[{"action":"host.future","resource":"**","decision":"allow"}]}"#
        try Data(newer.utf8).write(to: fileURL)

        let loaded = store.load(forWorkspaceRoot: root)
        XCTAssertTrue(loaded.table.isEmpty, "rules from a newer format must not half-apply")
        XCTAssertEqual(loaded.diagnostics.count, 1)

        XCTAssertThrowsError(try store.append(
            PermissionRule(action: "host.shell.run", resource: "ls", match: .exact, decision: .allow),
            forWorkspaceRoot: root
        ))
        // The newer file must be untouched by the refused append.
        XCTAssertEqual(try Data(contentsOf: fileURL), Data(newer.utf8))
    }

    func testProviderConformanceReadsFreshTablePerCall() throws {
        let (store, root) = try makeStoreAndRoot()
        XCTAssertTrue(store.ruleTable(forWorkspaceRoot: root).isEmpty)
        try store.append(
            PermissionRule(action: "host.shell.run", resource: "swift test", match: .exact, decision: .allow),
            forWorkspaceRoot: root
        )
        XCTAssertEqual(
            store.ruleTable(forWorkspaceRoot: root)
                .decision(action: "host.shell.run", resource: "swift test"),
            .allow,
            "a rule saved after the first read must be visible on the next read"
        )
    }
}
