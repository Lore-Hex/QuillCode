import XCTest
import QuillCodeCore
import QuillCodeTools
@testable import QuillCodeApp

/// Guards the SINGLE cross-language source of truth for the transcript's "Last diff" classifier:
/// the working-tree-content-mutating tool ids. The native side uses
/// `WorkspaceTurnRevertPlanner.workingTreeDiffToolNames`; the HTML/Playwright harness hard-codes
/// the same ids in `DIFF_PRODUCING_TOOL_NAMES` (it cannot import the Swift registry). These tests
/// enumerate every candidate tool id and assert Swift membership == harness membership, so a future
/// divergence — a new file-mutating tool added to one side only, or an excluded op wrongly added —
/// fails CI instead of silently drifting.
final class WorkspaceTurnRevertDiffToolParityTests: XCTestCase {
    /// The exact, intended working-tree-diff set. Both the Swift predicate and the harness must
    /// agree with this, id-for-id. `host.git.pr.checkout` is included because `gh pr checkout`
    /// switches the working tree to the PR head branch and rewrites differing files on disk.
    private let expectedDiffToolIDs: Set<String> = [
        "host.apply_patch",
        "host.git.revert_turn",
        "host.file.write",
        "host.git.restore",
        "host.git.restore_hunk",
        "host.git.pr.checkout"
    ]

    /// Repo/remote ops that are registered non-`read` tools but leave working-tree file bytes
    /// unchanged — they must NOT be diffs (this is the round-3 fix: the risk-based "any non-read"
    /// scope wrongly included these).
    private let expectedNonDiffMutatingIDs: Set<String> = [
        "host.git.commit",
        "host.git.push",
        "host.git.stage",
        "host.git.stage_hunk",
        "host.git.pr.create",
        "host.git.pr.merge",
        "host.git.pr.comment",
        "host.git.pr.reviewers",
        "host.git.pr.labels",
        "host.git.pr.lifecycle",
        "host.git.pr.review",
        "host.git.pr.review_comment",
        "host.git.pr.review_reply",
        "host.git.pr.review_thread",
        "host.git.worktree.create",
        "host.git.worktree.remove",
        "host.git.worktree.prune",
        "host.shell.run"
    ]

    func testSwiftPredicateMatchesTheIntendedWorkingTreeDiffSet() {
        XCTAssertEqual(WorkspaceTurnRevertPlanner.workingTreeDiffToolNames, expectedDiffToolIDs)
        for id in expectedDiffToolIDs {
            XCTAssertTrue(WorkspaceTurnRevertPlanner.isDiffProducingTool(id), "\(id) should be a diff")
        }
        for id in expectedNonDiffMutatingIDs {
            XCTAssertFalse(
                WorkspaceTurnRevertPlanner.isDiffProducingTool(id),
                "\(id) mutates the repo/remote but not working-tree file content, so it is not a diff"
            )
        }
    }

    func testEveryRegisteredToolAndDynamicIDAgreesWithTheHarness() throws {
        let harnessSet = try harnessDiffToolNames()

        // The full candidate universe: every statically-registered tool + the dynamic revert id.
        var candidateIDs = Set(ToolRouter.definitions.map(\.name))
        candidateIDs.insert(WorkspaceTurnRevertPlanner.revertTurnToolName)

        // Sanity: the excluded families are actually in the registry, so this test really exercises
        // them (a typo'd id would silently pass otherwise).
        for id in expectedNonDiffMutatingIDs where id != "host.shell.run" {
            XCTAssertTrue(candidateIDs.contains(id), "expected \(id) to be a registered tool id")
        }

        for id in candidateIDs.sorted() {
            let swiftSaysDiff = WorkspaceTurnRevertPlanner.isDiffProducingTool(id)
            let harnessSaysDiff = harnessSet.contains(id)
            XCTAssertEqual(
                swiftSaysDiff,
                harnessSaysDiff,
                "native and harness disagree on \(id): swift=\(swiftSaysDiff) harness=\(harnessSaysDiff)"
            )
        }
    }

    func testHarnessSetEqualsTheIntendedSet() throws {
        XCTAssertEqual(try harnessDiffToolNames(), expectedDiffToolIDs)
    }

    // MARK: - Harness parsing

    /// Extract the harness's `DIFF_PRODUCING_TOOL_NAMES` string literals from E2E/harness/index.html.
    private func harnessDiffToolNames(filePath: StaticString = #filePath) throws -> Set<String> {
        let root = URL(fileURLWithPath: "\(filePath)")
            .deletingLastPathComponent() // QuillCodeAppTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // package root
        let harness = try String(
            contentsOf: root.appendingPathComponent("E2E/harness/index.html"),
            encoding: .utf8
        )
        guard let declRange = harness.range(of: "const DIFF_PRODUCING_TOOL_NAMES = new Set([") else {
            XCTFail("Could not find DIFF_PRODUCING_TOOL_NAMES in the harness")
            return []
        }
        let afterDecl = harness[declRange.upperBound...]
        guard let closeRange = afterDecl.range(of: "]") else {
            XCTFail("Could not find the end of DIFF_PRODUCING_TOOL_NAMES")
            return []
        }
        let body = afterDecl[..<closeRange.lowerBound]
        // Every quoted string in the Set literal is a tool id (comments after `//` are stripped by
        // taking only single-quoted substrings).
        var ids: Set<String> = []
        var remainder = Substring(body)
        while let open = remainder.range(of: "'") {
            let afterOpen = remainder[open.upperBound...]
            guard let close = afterOpen.range(of: "'") else { break }
            ids.insert(String(afterOpen[..<close.lowerBound]))
            remainder = afterOpen[close.upperBound...]
        }
        return ids
    }
}
