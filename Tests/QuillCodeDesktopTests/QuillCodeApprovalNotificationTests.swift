import XCTest
import UserNotifications
@testable import quill_code_desktop

final class QuillCodeApprovalNotificationTests: XCTestCase {
    func testApproveActionDecidesApprove() {
        XCTAssertEqual(
            QuillCodeApprovalNotification.decision(forActionIdentifier: QuillCodeApprovalNotification.approveActionIdentifier),
            true
        )
    }

    func testSkipActionDecidesDeny() {
        XCTAssertEqual(
            QuillCodeApprovalNotification.decision(forActionIdentifier: QuillCodeApprovalNotification.skipActionIdentifier),
            false
        )
    }

    func testDefaultAndUnknownActionsDecideNothing() {
        // The default tap (open the app) and any unknown action must NOT silently approve or deny.
        XCTAssertNil(QuillCodeApprovalNotification.decision(forActionIdentifier: UNNotificationDefaultActionIdentifier))
        XCTAssertNil(QuillCodeApprovalNotification.decision(forActionIdentifier: UNNotificationDismissActionIdentifier))
        XCTAssertNil(QuillCodeApprovalNotification.decision(forActionIdentifier: "something-else"))
    }

    func testUserInfoRoundTripsToTarget() {
        let threadID = UUID()
        let info = QuillCodeApprovalNotification.userInfo(threadID: threadID, requestID: "req-42")
        let target = QuillCodeApprovalNotification.target(fromUserInfo: info)
        XCTAssertEqual(target?.requestID, "req-42")
        XCTAssertEqual(target?.threadID, threadID)
    }

    func testTargetRequiresANonEmptyRequestID() {
        XCTAssertNil(QuillCodeApprovalNotification.target(fromUserInfo: [:]))
        XCTAssertNil(QuillCodeApprovalNotification.target(fromUserInfo: [QuillCodeApprovalNotification.requestIDKey: ""]))
    }

    func testTargetToleratesAMissingOrUnparseableThreadID() {
        // A gate can be decided by requestID alone; the threadID just selects the right thread first.
        let noThread = QuillCodeApprovalNotification.target(fromUserInfo: [QuillCodeApprovalNotification.requestIDKey: "req-1"])
        XCTAssertEqual(noThread?.requestID, "req-1")
        XCTAssertNil(noThread?.threadID)

        let badThread = QuillCodeApprovalNotification.target(fromUserInfo: [
            QuillCodeApprovalNotification.requestIDKey: "req-1",
            QuillCodeApprovalNotification.threadIDKey: "not-a-uuid"
        ])
        XCTAssertNil(badThread?.threadID)
    }

    func testCategoryExposesApproveAndSkipActions() {
        let category = QuillCodeApprovalNotification.category
        XCTAssertEqual(category.identifier, QuillCodeApprovalNotification.categoryIdentifier)
        XCTAssertEqual(category.actions.map(\.identifier), [
            QuillCodeApprovalNotification.approveActionIdentifier,
            QuillCodeApprovalNotification.skipActionIdentifier
        ])
        XCTAssertEqual(category.actions.map(\.title), ["Approve", "Skip"])
    }
}
