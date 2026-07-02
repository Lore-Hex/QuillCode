import XCTest
import QuillCodeCore
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
        // #5: a corrupt file must be flagged DEGRADED (fail safe), not silently "no rules".
        XCTAssertTrue(loaded.degraded, "a corrupt file must fail safe (degraded), not read as empty")
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

    func testStructurallyMalformedRuleIsSkippedWithoutDroppingTheRestAndNotDegraded() throws {
        let (store, root) = try makeStoreAndRoot()
        let fileURL = store.fileURL(forWorkspaceRoot: root)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        // Structurally-malformed rules only (missing required fields / wrong types) — a partial
        // read that must NOT degrade the load: the surviving rules still apply.
        let json = """
        {"version":1,"rules":[
            {"action":"host.shell.run","resource":"swift test","match":"exact","decision":"allow"},
            {"resource":"missing action","decision":"deny"},
            {"action":"host.shell.run","resource":123,"decision":"deny"},
            {"action":"host.git.push","resource":"**","decision":"deny"}
        ]}
        """
        try Data(json.utf8).write(to: fileURL)

        let loaded = store.load(forWorkspaceRoot: root)
        XCTAssertEqual(loaded.table.rules.count, 2)
        XCTAssertEqual(loaded.table.rules.first?.resource, "swift test")
        XCTAssertEqual(loaded.table.rules.last?.action, "host.git.push")
        XCTAssertFalse(loaded.degraded, "a partial read of structurally-malformed rules is not degraded")
        XCTAssertTrue(try XCTUnwrap(loaded.diagnostics.first).contains("2 malformed rules"))
    }

    /// RESIDUAL MINOR: a well-STRUCTURED rule whose `decision` (or `match`) string is unknown to
    /// this build is NOT structurally malformed — it might be a DENY this build can't represent.
    /// Dropping it silently while reporting a healthy load would let a matching call auto-approve in
    /// Auto. The load must be DEGRADED even though other rules parsed fine.
    func testUnknownDecisionValueDegradesTheLoad() throws {
        let (store, root) = try makeStoreAndRoot()
        let fileURL = store.fileURL(forWorkspaceRoot: root)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        // One valid allow + one well-formed rule carrying an unknown `decision`, at the CURRENT
        // version (no version bump — the exact gap: a newer build's extra decision, or a hand edit).
        let json = """
        {"version":1,"rules":[
            {"action":"host.shell.run","resource":"swift test","match":"exact","decision":"allow"},
            {"action":"host.git.push","resource":"**","decision":"quarantine"}
        ]}
        """
        try Data(json.utf8).write(to: fileURL)

        let loaded = store.load(forWorkspaceRoot: root)
        XCTAssertTrue(loaded.degraded, "an unknown decision value must degrade the load (fail safe)")
        XCTAssertTrue(
            try XCTUnwrap(loaded.diagnostics.last).contains("unknown match/decision"),
            "the diagnostic should explain the unrepresentable rule"
        )
    }

    func testUnknownMatchKindDegradesTheLoad() throws {
        let (store, root) = try makeStoreAndRoot()
        let fileURL = store.fileURL(forWorkspaceRoot: root)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        // A future `regex` match kind written without a version bump.
        let json = """
        {"version":1,"rules":[
            {"action":"host.shell.run","resource":".*","match":"regex","decision":"deny"}
        ]}
        """
        try Data(json.utf8).write(to: fileURL)

        let loaded = store.load(forWorkspaceRoot: root)
        XCTAssertTrue(loaded.degraded, "an unknown match kind must degrade the load (fail safe)")
    }

    func testAppendRefusesOverFileWithUnrepresentableRules() throws {
        let (store, root) = try makeStoreAndRoot()
        let fileURL = store.fileURL(forWorkspaceRoot: root)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let json = """
        {"version":1,"rules":[
            {"action":"host.git.push","resource":"**","decision":"quarantine"}
        ]}
        """
        try Data(json.utf8).write(to: fileURL)

        // Appending would rewrite the file and silently drop the unrepresentable (possibly deny)
        // rule — so it must refuse, leaving the file untouched.
        XCTAssertThrowsError(try store.append(
            PermissionRule(action: "host.shell.run", resource: "ls", match: .exact, decision: .allow),
            forWorkspaceRoot: root
        ))
        XCTAssertEqual(try Data(contentsOf: fileURL), Data(json.utf8), "the file must be left untouched")
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
        // #5: a newer-version file must be DEGRADED (fail safe): a rule this build can't represent
        // could be a deny, so the reviewer forces ask rather than treating the table as empty.
        XCTAssertTrue(loaded.degraded)
        XCTAssertEqual(loaded.diagnostics.count, 1)

        XCTAssertThrowsError(try store.append(
            PermissionRule(action: "host.shell.run", resource: "ls", match: .exact, decision: .allow),
            forWorkspaceRoot: root
        ))
        // The newer file must be untouched by the refused append.
        XCTAssertEqual(try Data(contentsOf: fileURL), Data(newer.utf8))
    }

    func testUnreadableFileFailsSafeAsDegraded() throws {
        let (store, root) = try makeStoreAndRoot()
        let fileURL = store.fileURL(forWorkspaceRoot: root)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        // A directory where the rules FILE is expected: reading it as data throws → degraded.
        try FileManager.default.createDirectory(at: fileURL, withIntermediateDirectories: true)

        let loaded = store.load(forWorkspaceRoot: root)
        XCTAssertTrue(loaded.degraded, "an unreadable rules file must fail safe (degraded)")
        XCTAssertTrue(loaded.table.isEmpty)
    }

    func testAllRulesMalformedIsDegraded() throws {
        let (store, root) = try makeStoreAndRoot()
        let fileURL = store.fileURL(forWorkspaceRoot: root)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        // Valid JSON envelope but every rule is unparseable → effectively corrupt → degraded.
        let json = #"{"version":1,"rules":[{"nope":true},{"also":"bad"}]}"#
        try Data(json.utf8).write(to: fileURL)

        let loaded = store.load(forWorkspaceRoot: root)
        XCTAssertTrue(loaded.table.isEmpty)
        XCTAssertTrue(loaded.degraded, "a file whose every rule is malformed must fail safe (degraded)")
    }

    func testMissingFileIsNotDegraded() throws {
        let (store, root) = try makeStoreAndRoot()
        // No file at all is the legitimate "no rules yet" state — NOT degraded (existing behavior).
        let loaded = store.load(forWorkspaceRoot: root)
        XCTAssertFalse(loaded.degraded)
        XCTAssertTrue(loaded.table.isEmpty)
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

    /// End-to-end: a real file with an unknown `decision` value degrades the load, and the
    /// permission-rule-gated reviewer therefore forces an approval gate instead of auto-approving in
    /// Auto — even for a call that would otherwise pass. Fails on revert of the residual fix.
    func testUnknownDecisionValueForcesAskThroughTheReviewer() async throws {
        let (store, root) = try makeStoreAndRoot()
        let fileURL = store.fileURL(forWorkspaceRoot: root)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let json = """
        {"version":1,"rules":[
            {"action":"host.git.push","resource":"**","decision":"quarantine"}
        ]}
        """
        try Data(json.utf8).write(to: fileURL)

        struct ApprovingReviewer: SafetyReviewer {
            func review(_ context: SafetyContext) async -> SafetyReview {
                SafetyReview(verdict: .approve, rationale: "auto approved")
            }
        }
        let reviewer = PermissionRuleGatedSafetyReviewer(base: ApprovingReviewer(), rules: store)
        let review = await reviewer.review(SafetyContext(
            mode: .auto,
            userMessage: "push",
            toolCall: ToolCall(name: "host.git.push", argumentsJSON: "{}"),
            toolDefinition: nil,
            recentMessages: [],
            workspaceRoot: root
        ))
        XCTAssertEqual(
            review.verdict,
            .clarify,
            "an unknown-decision rule (possibly a deny) must force ask, not auto-approve"
        )
    }
}
