import XCTest
import QuillCodeCore
@testable import QuillCodeApp

final class LocalEnvironmentActionMatcherTests: XCTestCase {
    func testFindsActionByExactID() {
        let action = Self.action(
            id: "local-env:.quillcode/actions/bootstrap.sh",
            title: "Bootstrap",
            relativePath: ".quillcode/actions/bootstrap.sh"
        )

        XCTAssertEqual(
            LocalEnvironmentActionMatcher.action(withID: action.id, in: [action])?.id,
            action.id
        )
        XCTAssertNil(LocalEnvironmentActionMatcher.action(withID: "missing", in: [action]))
    }

    func testFindsActionByTitlePathAndNormalizedAliases() {
        let action = Self.action(
            id: "local-env:.quillcode/actions/build-release.sh",
            title: "Build Release",
            relativePath: ".quillcode/actions/build-release.sh"
        )

        XCTAssertEqual(LocalEnvironmentActionMatcher.action(matching: "Build Release", in: [action])?.id, action.id)
        XCTAssertEqual(LocalEnvironmentActionMatcher.action(matching: "build release", in: [action])?.id, action.id)
        XCTAssertEqual(LocalEnvironmentActionMatcher.action(matching: ".quillcode/actions/build-release.sh", in: [action])?.id, action.id)
        XCTAssertEqual(LocalEnvironmentActionMatcher.action(matching: "buildrelease", in: [action])?.id, action.id)
        XCTAssertNil(LocalEnvironmentActionMatcher.action(matching: "ship release", in: [action]))
    }

    func testNormalizedActionNameKeepsOnlyLettersAndNumbers() {
        XCTAssertEqual(
            LocalEnvironmentActionMatcher.normalizedActionName(".quillcode/actions/build-release.sh"),
            "quillcodeactionsbuildreleasesh"
        )
    }

    private static func action(id: String, title: String, relativePath: String) -> LocalEnvironmentAction {
        LocalEnvironmentAction(
            id: id,
            title: title,
            relativePath: relativePath,
            command: "bash \(relativePath)"
        )
    }
}
