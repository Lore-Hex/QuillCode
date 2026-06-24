import XCTest
import QuillCodeCore
@testable import QuillCodeApp

final class WorkspaceThreadNoticeAppenderTests: XCTestCase {
    func testAppendNoticeAddsNoticeEventOnly() {
        var thread = ChatThread(title: "Thread")

        WorkspaceThreadNoticeAppender.appendNotice("Refreshed project context", to: &thread)

        XCTAssertTrue(thread.messages.isEmpty)
        XCTAssertEqual(thread.events.map(\.kind), [.notice])
        XCTAssertEqual(thread.events.map(\.summary), ["Refreshed project context"])
    }

    func testAppendAssistantNoticeAddsMessageAndEvent() {
        var thread = ChatThread(title: "Thread")

        WorkspaceThreadNoticeAppender.appendAssistantNotice("Ready.", to: &thread)

        XCTAssertEqual(thread.messages.map(\.role), [.assistant])
        XCTAssertEqual(thread.messages.map(\.content), ["Ready."])
        XCTAssertEqual(thread.events.map(\.kind), [.message])
        XCTAssertEqual(thread.events.map(\.summary), ["Ready."])
    }
}
