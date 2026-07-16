import XCTest
@testable import QuillCodeHooks

final class ProjectPluginHookMatcherTests: XCTestCase {
    func testMatchAllFormsAcceptEveryCandidate() {
        XCTAssertTrue(ProjectPluginHookMatcher.matches(nil, candidates: ["shell.run"]))
        XCTAssertTrue(ProjectPluginHookMatcher.matches("", candidates: ["shell.run"]))
        XCTAssertTrue(ProjectPluginHookMatcher.matches("*", candidates: ["shell.run"]))
    }

    func testRegularExpressionMatchesAnyBoundedCandidate() {
        XCTAssertTrue(ProjectPluginHookMatcher.matches(
            "^(shell|file)\\.",
            candidates: ["browser.open", "file.write"]
        ))
        XCTAssertFalse(ProjectPluginHookMatcher.matches(
            "^(shell|file)\\.",
            candidates: ["browser.open"]
        ))
    }

    func testMalformedAndOversizedPatternsFailClosed() {
        XCTAssertFalse(ProjectPluginHookMatcher.isValid("["))
        XCTAssertFalse(ProjectPluginHookMatcher.matches("[", candidates: ["shell.run"]))
        XCTAssertFalse(ProjectPluginHookMatcher.isValid(
            String(repeating: "x", count: ProjectPluginHookMatcher.maximumPatternCharacters + 1)
        ))
    }
}
