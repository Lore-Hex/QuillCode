import ApplicationServices
import XCTest
@testable import quill_code_desktop

final class QuillCodeDesktopAccessibilityTreeIdentityTests: XCTestCase {
    func testEquivalentAXApplicationWrappersDeduplicateByCFIdentity() {
        let processID = ProcessInfo.processInfo.processIdentifier
        let first = QuillCodeDesktopAccessibilityElementIdentity(
            element: AXUIElementCreateApplication(processID)
        )
        let second = QuillCodeDesktopAccessibilityElementIdentity(
            element: AXUIElementCreateApplication(processID)
        )
        var identities: Set<QuillCodeDesktopAccessibilityElementIdentity> = []

        XCTAssertEqual(first, second)
        XCTAssertTrue(identities.insert(first).inserted)
        XCTAssertFalse(identities.insert(second).inserted)
        XCTAssertEqual(identities.count, 1)
    }

    func testDistinctAXRootsRemainDistinct() {
        let application = QuillCodeDesktopAccessibilityElementIdentity(
            element: AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
        )
        let systemWide = QuillCodeDesktopAccessibilityElementIdentity(
            element: AXUIElementCreateSystemWide()
        )

        XCTAssertNotEqual(application, systemWide)
        XCTAssertEqual(Set([application, systemWide]).count, 2)
    }
}
