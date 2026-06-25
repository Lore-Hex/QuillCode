import XCTest
import QuillCodeCore
@testable import QuillCodeApp

final class WorkspaceMessageFeedbackPlannerTests: XCTestCase {
    func testEventEncodesHelpfulFeedbackPayloadAndSummary() throws {
        let messageID = UUID()

        let event = try WorkspaceMessageFeedbackPlanner.event(
            messageID: messageID,
            value: .helpful
        )

        XCTAssertEqual(event.kind, .messageFeedback)
        XCTAssertEqual(event.summary, "Marked assistant response helpful")
        let payloadJSON = try XCTUnwrap(event.payloadJSON)
        let feedback: MessageFeedback = try JSONHelpers.decode(MessageFeedback.self, from: payloadJSON)
        XCTAssertEqual(feedback.messageID, messageID)
        XCTAssertEqual(feedback.value, MessageFeedbackValue.helpful)
    }

    func testSummaryCoversBothFeedbackValues() {
        XCTAssertEqual(
            WorkspaceMessageFeedbackPlanner.summary(for: .helpful),
            "Marked assistant response helpful"
        )
        XCTAssertEqual(
            WorkspaceMessageFeedbackPlanner.summary(for: .notHelpful),
            "Marked assistant response not helpful"
        )
    }
}
