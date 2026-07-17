import XCTest

final class ParityAppServerPluginReadGateTests: QuillCodeParityTestCase {
    func testLocalPluginSkillReadStaysWiredThroughRuntimeTestsSmokeAndDocs() throws {
        let root = Self.packageRoot()
        let session = try text(root, "Sources/QuillCodeCLI/AppServerSession.swift")
        let read = try text(root, "Sources/QuillCodeCLI/AppServerPluginRead.swift")
        let tests = try text(
            root,
            "Tests/QuillCodeCLITests/AppServerPluginDiscoveryTests.swift"
        )
        let smoke = try text(root, "scripts/app-server-smoke.sh")
        let decisions = try Self.docsText(named: "DECISIONS.md")
        let parity = try Self.docsText(named: "CODEX_PARITY_MATRIX.md")

        Self.assertSource(session, contains: "case \"plugin/skill/read\"")
        Self.assertSource(read, containsAll: [
            "func readPluginSkill",
            "func readLocalPluginSkill",
            "maximumPluginSkillBodyBytes",
            "WorkspaceBoundary.isWithin",
            "remote plugin skill read is not available"
        ])
        Self.assertSource(tests, containsAll: [
            "testPluginSkillReadReturnsBoundedLocalSkillContent",
            "demo:review",
            "chatgpt-only"
        ])
        Self.assertSource(smoke, containsAll: [
            "\"method\": \"plugin/skill/read\"",
            "Use this plugin skill in the app-server smoke."
        ])
        Self.assertSource(decisions, contains: "Local `plugin/skill/read` re-resolves")
        Self.assertSource(parity, contains: "local `plugin/skill/read` content")
    }

    private func text(_ root: URL, _ path: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }
}
