import XCTest
import UserNotifications
@testable import quill_code_desktop

final class QuillCodeRetryNotificationTests: XCTestCase {
    func testOnlyTheRetryActionIsARetry() {
        XCTAssertTrue(QuillCodeRetryNotification.isRetryAction(QuillCodeRetryNotification.retryActionIdentifier))
        // The default tap (open the app), dismiss, and unknown actions must never resume a run.
        XCTAssertFalse(QuillCodeRetryNotification.isRetryAction(UNNotificationDefaultActionIdentifier))
        XCTAssertFalse(QuillCodeRetryNotification.isRetryAction(UNNotificationDismissActionIdentifier))
        XCTAssertFalse(QuillCodeRetryNotification.isRetryAction(QuillCodeApprovalNotification.approveActionIdentifier))
        XCTAssertFalse(QuillCodeRetryNotification.isRetryAction("something-else"))
    }

    func testUserInfoRoundTripsThreadID() {
        let threadID = UUID()
        let info = QuillCodeRetryNotification.userInfo(threadID: threadID)
        XCTAssertEqual(QuillCodeRetryNotification.threadID(fromUserInfo: info), threadID)
    }

    func testMissingOrUnparseableThreadIDYieldsNoTarget() {
        // A retry with no target must never fall back to "whatever thread is selected".
        XCTAssertNil(QuillCodeRetryNotification.threadID(fromUserInfo: [:]))
        XCTAssertNil(QuillCodeRetryNotification.threadID(fromUserInfo: [
            QuillCodeRetryNotification.threadIDKey: "not-a-uuid"
        ]))
    }

    func testCategoryOffersExactlyOneRetryAction() {
        let category = QuillCodeRetryNotification.category
        XCTAssertEqual(category.identifier, QuillCodeRetryNotification.categoryIdentifier)
        XCTAssertEqual(category.actions.map(\.identifier), [QuillCodeRetryNotification.retryActionIdentifier])
        XCTAssertEqual(category.actions.first?.title, "Retry")
    }

    func testRetryAndApprovalCategoryIdentifiersAreDistinct() {
        // Both categories are registered on the one notification center — a collision would make
        // approval notifications sprout a Retry button (or vice versa).
        XCTAssertNotEqual(
            QuillCodeRetryNotification.categoryIdentifier,
            QuillCodeApprovalNotification.categoryIdentifier
        )
    }
}
