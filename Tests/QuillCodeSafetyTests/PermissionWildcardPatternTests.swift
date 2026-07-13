import XCTest
@testable import QuillCodeSafety

final class PermissionWildcardPatternTests: XCTestCase {
    func testGlobstarDirectoryMatchesZeroOrMoreCompleteSegments() throws {
        try assertMatches("**/.env", [".env", "sub/.env", "a/b/.env"])
        try assertMatches("a/**/b", ["a/b", "a/x/b"])
        try assertMatches("**/x", ["x", "a/x"])
    }

    func testGlobstarDirectoryDoesNotConsumePartialSegments() throws {
        try assertDoesNotMatch("**/.env", ["x.env"])
        try assertDoesNotMatch("a/**/b", ["a/xb"])
        try assertDoesNotMatch("**/x", ["ax"])
    }

    func testGlobstarDirectorySupportsEmptyAndUnicodeSegments() throws {
        try assertMatches("**/", ["", "/", "a/", "a/b/"])
        try assertMatches("**/.env", ["/π/.env", "π/.env"])
        try assertDoesNotMatch("**/", ["a", "a/b"])
    }

    func testBareGlobstarStillCrossesSeparatorsWithoutDirectoryBoundaries() throws {
        try assertMatches("a/**/b**", ["a/b", "a/x/b", "a/x/beta", "a/x/b/y"])
        try assertMatches("**", ["", "x", "a/b", "/a/"])
    }

    func testPermissionTableDenyCoversRootAndNestedSecretFiles() {
        let table = PermissionRuleTable(rules: [
            PermissionRule(
                action: "host.file.read",
                resource: "**/.env",
                decision: .deny
            )
        ])

        XCTAssertEqual(
            table.decision(action: "host.file.read", resource: ".env"),
            .deny
        )
        XCTAssertEqual(
            table.decision(action: "host.file.read", resource: "Sources/App/.env"),
            .deny
        )
        XCTAssertNil(table.decision(action: "host.file.read", resource: "Sources/App.env"))
    }

    func testRepeatedGlobstarDirectoriesStayBoundedAtInputLimits() throws {
        let pattern = String(repeating: "**/", count: 84) + "end"
        let candidate = String(repeating: "segment/", count: 500) + "miss"
        let matcher = try XCTUnwrap(PermissionWildcardPattern(pattern))

        for _ in 0..<10 {
            XCTAssertFalse(matcher.matches(candidate))
        }
    }

    func testGlobstarDirectoryTransitionsCrossBitsetWordBoundaries() throws {
        for prefixLength in [62, 63, 64, 126, 127, 128] {
            let prefix = String(repeating: "a", count: prefixLength)
            let matcher = try XCTUnwrap(PermissionWildcardPattern(prefix + "**/z"))

            XCTAssertTrue(matcher.matches(prefix + "z"), "prefixLength=\(prefixLength)")
            XCTAssertTrue(matcher.matches(prefix + "path/z"), "prefixLength=\(prefixLength)")
            XCTAssertFalse(matcher.matches(prefix + "pathz"), "prefixLength=\(prefixLength)")
        }
    }

    func testMatcherAgreesWithRecursiveReferenceOracleAcrossGeneratedCorpus() throws {
        let patterns = generatedStrings(
            atoms: ["a", "b", "/", "*", "**", "**/"],
            maximumAtomCount: 3
        )
        let candidates = generatedStrings(atoms: ["a", "b", "/"], maximumAtomCount: 4)

        for pattern in patterns {
            let matcher = try XCTUnwrap(PermissionWildcardPattern(pattern))
            for candidate in candidates {
                XCTAssertEqual(
                    matcher.matches(candidate),
                    ReferencePermissionWildcardMatcher.matches(pattern: pattern, candidate: candidate),
                    "pattern=\(pattern.debugDescription), candidate=\(candidate.debugDescription)"
                )
            }
        }
    }

    private func assertMatches(_ pattern: String, _ candidates: [String]) throws {
        let matcher = try XCTUnwrap(PermissionWildcardPattern(pattern))
        for candidate in candidates {
            XCTAssertTrue(
                matcher.matches(candidate),
                "expected \(pattern.debugDescription) to match \(candidate.debugDescription)"
            )
        }
    }

    private func assertDoesNotMatch(_ pattern: String, _ candidates: [String]) throws {
        let matcher = try XCTUnwrap(PermissionWildcardPattern(pattern))
        for candidate in candidates {
            XCTAssertFalse(
                matcher.matches(candidate),
                "expected \(pattern.debugDescription) not to match \(candidate.debugDescription)"
            )
        }
    }

    private func generatedStrings(atoms: [String], maximumAtomCount: Int) -> [String] {
        var all = Set([""])
        var frontier = [""]
        for _ in 0..<maximumAtomCount {
            frontier = frontier.flatMap { prefix in atoms.map { prefix + $0 } }
            all.formUnion(frontier)
        }
        return all.sorted()
    }
}

private enum ReferencePermissionWildcardMatcher {
    static func matches(pattern: String, candidate: String) -> Bool {
        var matcher = Matcher(
            pattern: Array(pattern.unicodeScalars),
            candidate: Array(candidate.unicodeScalars)
        )
        return matcher.matches(patternIndex: 0, candidateIndex: 0)
    }

    private struct State: Hashable {
        var patternIndex: Int
        var candidateIndex: Int
    }

    private struct Matcher {
        var pattern: [Unicode.Scalar]
        var candidate: [Unicode.Scalar]
        var memo: [State: Bool] = [:]

        mutating func matches(patternIndex: Int, candidateIndex: Int) -> Bool {
            let state = State(patternIndex: patternIndex, candidateIndex: candidateIndex)
            if let cached = memo[state] { return cached }

            let result = uncachedMatch(patternIndex: patternIndex, candidateIndex: candidateIndex)
            memo[state] = result
            return result
        }

        private mutating func uncachedMatch(patternIndex: Int, candidateIndex: Int) -> Bool {
            guard patternIndex < pattern.count else { return candidateIndex == candidate.count }
            guard pattern[patternIndex] == "*" else {
                return candidateIndex < candidate.count
                    && pattern[patternIndex] == candidate[candidateIndex]
                    && matches(patternIndex: patternIndex + 1, candidateIndex: candidateIndex + 1)
            }

            var afterStars = patternIndex
            while afterStars < pattern.count, pattern[afterStars] == "*" {
                afterStars += 1
            }
            let isGlobstar = afterStars - patternIndex >= 2
            if isGlobstar,
               afterStars < pattern.count,
               pattern[afterStars] == "/" {
                return matchesGlobstarDirectory(
                    patternIndex: patternIndex,
                    afterSlash: afterStars + 1,
                    candidateIndex: candidateIndex
                )
            }
            return matchesStarRun(
                afterStars: afterStars,
                candidateIndex: candidateIndex,
                crossesSeparators: isGlobstar
            )
        }

        private mutating func matchesGlobstarDirectory(
            patternIndex: Int,
            afterSlash: Int,
            candidateIndex: Int
        ) -> Bool {
            if matches(patternIndex: afterSlash, candidateIndex: candidateIndex) {
                return true
            }
            for index in candidateIndex..<candidate.count where candidate[index] == "/" {
                if matches(patternIndex: patternIndex, candidateIndex: index + 1) {
                    return true
                }
                break
            }
            return false
        }

        private mutating func matchesStarRun(
            afterStars: Int,
            candidateIndex: Int,
            crossesSeparators: Bool
        ) -> Bool {
            if matches(patternIndex: afterStars, candidateIndex: candidateIndex) {
                return true
            }
            var index = candidateIndex
            while index < candidate.count,
                  crossesSeparators || candidate[index] != "/" {
                index += 1
                if matches(patternIndex: afterStars, candidateIndex: index) {
                    return true
                }
            }
            return false
        }
    }
}
