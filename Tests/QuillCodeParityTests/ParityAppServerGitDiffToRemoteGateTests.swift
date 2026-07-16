import XCTest

final class ParityAppServerGitDiffToRemoteGateTests: QuillCodeParityTestCase {
    func testGitDiffToRemoteStaysWiredThroughProtocolTestsSmokeAndDocs() throws {
        let root = Self.packageRoot()
        let session = try text(root, "Sources/QuillCodeCLI/AppServerSession.swift")
        let endpoint = try text(root, "Sources/QuillCodeCLI/AppServerGitDiffToRemote.swift")
        let protocolTests = try text(
            root,
            "Tests/QuillCodeCLITests/AppServerGitDiffToRemoteTests.swift"
        )
        let smoke = try text(root, "scripts/app-server-smoke.sh")
        let parity = try Self.docsText(named: "CODEX_PARITY_MATRIX.md")
        let research = try Self.docsText(named: "CODEX_RESEARCH.md")

        Self.assertSource(session, contains: "case \"gitDiffToRemote\"")
        Self.assertSource(endpoint, containsAll: [
            "func gitDiffToRemote",
            "@{upstream}^{commit}",
            "--exclude-standard",
            "--no-index",
            "--binary",
            "maximumDiffBytes",
            "maximumUntrackedFiles"
        ])
        Self.assertSource(protocolTests, containsAll: [
            "testReturnsUpstreamSHAAndCompleteWorkingTreeDiff",
            "testUsesCurrentUpstreamTipRatherThanMergeBase",
            "testRejectsMissingInvalidAndUnpublishedRepositoriesWithCodexErrors",
            "testReaderFailsClosedWhenDiffExceedsConfiguredLimit"
        ])
        Self.assertSource(smoke, containsAll: [
            "\"method\": \"gitDiffToRemote\"",
            "git-diff-untracked.txt"
        ])
        Self.assertSource(parity, contains: "gitDiffToRemote")
        Self.assertSource(research, contains: "gitDiffToRemote")
    }

    private func text(_ root: URL, _ path: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }
}
