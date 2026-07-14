import Foundation
import XCTest
@testable import QuillCodeCore

final class PullRequestLinkTests: XCTestCase {
    func testLifecycleLabelsAndTerminalStatesStayExplicit() {
        XCTAssertEqual(PullRequestLifecycleStatus.draft.label, "Draft")
        XCTAssertEqual(PullRequestLifecycleStatus.queued.label, "Queued")
        XCTAssertFalse(PullRequestLifecycleStatus.open.isTerminal)
        XCTAssertTrue(PullRequestLifecycleStatus.merged.isTerminal)
        XCTAssertTrue(PullRequestLifecycleStatus.closed.isTerminal)
    }

    func testThreadRoundTripPreservesPullRequestIdentity() throws {
        let link = PullRequestLink(
            number: 42,
            title: "Land worktree",
            url: "https://github.test/pull/42",
            status: .queued,
            baseBranch: "main",
            headBranch: "feature/land",
            headCommit: "abc123",
            mergeState: "BLOCKED",
            updatedAt: Date(timeIntervalSince1970: 123)
        )
        let thread = ChatThread(title: "Land", pullRequest: link)

        let decoded = try JSONDecoder().decode(
            ChatThread.self,
            from: JSONEncoder().encode(thread)
        )

        XCTAssertEqual(decoded.pullRequest, link)
        XCTAssertEqual(decoded.pullRequest?.compactLabel, "PR #42 · Queued")
    }

    func testLegacyThreadWithoutPullRequestDecodesAsUnlinked() throws {
        let thread = ChatThread(title: "Legacy")
        let data = try JSONEncoder().encode(thread)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "pullRequest")

        let decoded = try JSONDecoder().decode(
            ChatThread.self,
            from: JSONSerialization.data(withJSONObject: object)
        )

        XCTAssertNil(decoded.pullRequest)
    }
}
