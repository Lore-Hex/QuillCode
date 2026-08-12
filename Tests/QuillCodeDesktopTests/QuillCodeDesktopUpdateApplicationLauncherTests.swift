import XCTest
@testable import quill_code_desktop

final class QuillCodeDesktopUpdateApplicationLauncherTests: XCTestCase {
    func testProductionHelperRelaunchesThroughLaunchServices() throws {
        XCTAssertEqual(
            try QuillCodeDesktopUpdateHelperEnvironment.production().applicationLaunchMode,
            .launchServices
        )
    }
}
