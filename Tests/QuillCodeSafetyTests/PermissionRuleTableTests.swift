import XCTest
import QuillCodeCore
@testable import QuillCodeSafety

final class PermissionRuleTableTests: XCTestCase {
    // MARK: - Wildcard semantics

    func testExactPatternMatchesOnlyItself() throws {
        let pattern = try XCTUnwrap(PermissionWildcardPattern("swift test"))
        XCTAssertTrue(pattern.matches("swift test"))
        XCTAssertFalse(pattern.matches("swift test --filter Foo"))
        XCTAssertFalse(pattern.matches("swift"))
        XCTAssertFalse(pattern.matches(""))
    }

    func testSingleStarMatchesWithinOneSegment() throws {
        let pattern = try XCTUnwrap(PermissionWildcardPattern("npm run *"))
        XCTAssertTrue(pattern.matches("npm run build"))
        XCTAssertTrue(pattern.matches("npm run "))
        XCTAssertFalse(pattern.matches("npm run scripts/build.sh"), "* must not cross a path separator")

        let fileGlob = try XCTUnwrap(PermissionWildcardPattern("/repo/*.env"))
        XCTAssertTrue(fileGlob.matches("/repo/prod.env"))
        XCTAssertFalse(fileGlob.matches("/repo/sub/dev.env"))
    }

    func testGlobstarCrossesSegments() throws {
        let pattern = try XCTUnwrap(PermissionWildcardPattern("/repo/secrets/**"))
        XCTAssertTrue(pattern.matches("/repo/secrets/a"))
        XCTAssertTrue(pattern.matches("/repo/secrets/deeply/nested/key.pem"))
        XCTAssertFalse(pattern.matches("/repo/public/readme.md"))

        let command = try XCTUnwrap(PermissionWildcardPattern("git push **"))
        XCTAssertTrue(command.matches("git push origin feature/branch-name"))
    }

    func testStarRunsCollapse() throws {
        // 3+ stars behave like ** (a glob typo should not create an unmatchable rule).
        let pattern = try XCTUnwrap(PermissionWildcardPattern("a***b"))
        XCTAssertTrue(pattern.matches("a/x/b"))
    }

    func testMultipleStarsBacktrackCorrectly() throws {
        // NFA simulation must handle patterns where a later star's match position depends on an
        // earlier globstar consuming more (the case single-backtrack greedy matchers get wrong).
        let pattern = try XCTUnwrap(PermissionWildcardPattern("**a*b"))
        XCTAssertTrue(pattern.matches("a/ab"))

        let plain = try XCTUnwrap(PermissionWildcardPattern("*a*b"))
        XCTAssertTrue(plain.matches("xaYb"))
        XCTAssertFalse(plain.matches("xa/Yb"))
    }

    func testEmptyPatternMatchesOnlyEmpty() throws {
        let pattern = try XCTUnwrap(PermissionWildcardPattern(""))
        XCTAssertTrue(pattern.matches(""))
        XCTAssertFalse(pattern.matches("x"))
    }

    func testOversizedPatternIsRejected() {
        let hostile = String(repeating: "a", count: PermissionWildcardPattern.maxPatternScalarCount + 1)
        XCTAssertNil(PermissionWildcardPattern(hostile))
    }

    func testHostilePatternsAreBounded() throws {
        // The classic exponential-backtracking killer: many stars against a near-matching long
        // candidate. The NFA simulation must stay comfortably fast.
        let starBomb = String(repeating: "a*", count: 100) + "b"
        let candidate = String(repeating: "a", count: PermissionWildcardPattern.maxCandidateScalarCount)
        let pattern = try XCTUnwrap(PermissionWildcardPattern(starBomb))

        let start = Date()
        for _ in 0..<10 {
            XCTAssertFalse(pattern.matches(candidate))
        }
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertLessThan(elapsed, 2.0, "hostile pattern matching must be linear-time, took \(elapsed)s")
    }

    // MARK: - Table evaluation

    func testNoMatchReturnsNilSoExistingBehaviorIsUnchanged() {
        let table = PermissionRuleTable(rules: [
            PermissionRule(action: "host.shell.run", resource: "swift build", decision: .allow)
        ])
        XCTAssertNil(table.decision(action: "host.shell.run", resource: "swift test"))
        XCTAssertNil(table.decision(action: "host.file.write", resource: "swift build"))
        XCTAssertNil(PermissionRuleTable().decision(action: "host.shell.run", resource: "ls"))
    }

    func testLastMatchingRuleWins() {
        let table = PermissionRuleTable(rules: [
            PermissionRule(action: "host.shell.run", resource: "npm **", decision: .allow),
            PermissionRule(action: "host.shell.run", resource: "npm publish*", decision: .deny),
            PermissionRule(action: "host.shell.run", resource: "npm publish --dry-run", decision: .allow)
        ])
        XCTAssertEqual(table.decision(action: "host.shell.run", resource: "npm test"), .allow)
        XCTAssertEqual(table.decision(action: "host.shell.run", resource: "npm publish"), .deny)
        XCTAssertEqual(table.decision(action: "host.shell.run", resource: "npm publish --dry-run"), .allow)
    }

    func testAppendedRuleOverridesEarlierRules() {
        var table = PermissionRuleTable(rules: [
            PermissionRule(action: "host.shell.run", resource: "swift test", decision: .deny)
        ])
        table.append(PermissionRule(action: "host.shell.run", resource: "swift test", match: .exact, decision: .allow))
        XCTAssertEqual(table.decision(action: "host.shell.run", resource: "swift test"), .allow)
    }

    func testActionPatternsMatchToolFamilies() {
        let table = PermissionRuleTable(rules: [
            PermissionRule(action: "host.git.**", resource: "**", decision: .allow)
        ])
        XCTAssertEqual(table.decision(action: "host.git.push", resource: ""), .allow)
        XCTAssertEqual(table.decision(action: "host.git.pr.merge", resource: ""), .allow)
        XCTAssertNil(table.decision(action: "host.shell.run", resource: ""))
    }

    func testExactMatchRulesDoNotInterpretWildcards() {
        let table = PermissionRuleTable(rules: [
            PermissionRule(action: "host.shell.run", resource: "rm *.log", match: .exact, decision: .allow)
        ])
        XCTAssertEqual(table.decision(action: "host.shell.run", resource: "rm *.log"), .allow)
        XCTAssertNil(
            table.decision(action: "host.shell.run", resource: "rm important.log"),
            "an exact rule saved for a command containing * must never wildcard-match"
        )
    }

    func testOversizedResourceDegradesConservatively() {
        let oversized = "rm " + String(repeating: "a", count: PermissionWildcardPattern.maxCandidateScalarCount + 10)
        let allowTable = PermissionRuleTable(rules: [
            PermissionRule(action: "host.shell.run", resource: "rm **", decision: .allow)
        ])
        // Padding a command past the cap must never earn a silent allow…
        XCTAssertEqual(allowTable.decision(action: "host.shell.run", resource: oversized), .ask)

        let denyTable = PermissionRuleTable(rules: [
            PermissionRule(action: "host.shell.run", resource: "rm **", decision: .deny)
        ])
        // …and must never dodge a deny into a nil (existing-behavior) verdict either.
        XCTAssertEqual(denyTable.decision(action: "host.shell.run", resource: oversized), .ask)

        let exactDeny = PermissionRuleTable(rules: [
            PermissionRule(action: "host.shell.run", resource: "rm **", decision: .deny),
            PermissionRule(action: "host.shell.run", resource: oversized, match: .exact, decision: .deny)
        ])
        // An exact deny still lands even at hostile lengths (string equality is safe).
        XCTAssertEqual(exactDeny.decision(action: "host.shell.run", resource: oversized), .deny)

        let unrelated = PermissionRuleTable(rules: [
            PermissionRule(action: "host.file.write", resource: "**", decision: .deny)
        ])
        // No rule for this action → no opinion, oversized or not.
        XCTAssertNil(unrelated.decision(action: "host.shell.run", resource: oversized))
    }

    func testRuleCountIsCapped() {
        let filler = (0..<(PermissionRuleTable.maxRuleCount + 50)).map { index in
            PermissionRule(action: "host.shell.run", resource: "cmd-\(index)", match: .exact, decision: .allow)
        }
        let table = PermissionRuleTable(rules: filler)
        XCTAssertEqual(table.rules.count, PermissionRuleTable.maxRuleCount)

        var appended = table
        appended.append(PermissionRule(action: "host.shell.run", resource: "fresh", match: .exact, decision: .deny))
        XCTAssertEqual(appended.rules.count, PermissionRuleTable.maxRuleCount)
        XCTAssertEqual(
            appended.decision(action: "host.shell.run", resource: "fresh"),
            .deny,
            "a freshly taught rule must never be dropped in favor of an old one"
        )
    }

    // MARK: - Tie-break helper

    func testStrongestDecisionOrdersAllowOverDenyOverAsk() {
        XCTAssertEqual(PermissionRuleDecision.strongest(.allow, .deny), .allow)
        XCTAssertEqual(PermissionRuleDecision.strongest(.deny, .allow), .allow)
        XCTAssertEqual(PermissionRuleDecision.strongest(.deny, .ask), .deny)
        XCTAssertEqual(PermissionRuleDecision.strongest(.ask, .deny), .deny)
        XCTAssertEqual(PermissionRuleDecision.strongest(.ask, .ask), .ask)
    }

    // MARK: - Rule decoding tolerance

    func testRuleDecodingDefaultsAbsentMatchKindToPattern() throws {
        let json = #"{"action":"host.shell.run","resource":"npm *","decision":"allow"}"#
        let rule = try JSONDecoder().decode(PermissionRule.self, from: Data(json.utf8))
        XCTAssertEqual(rule.match, .pattern)
    }
}
