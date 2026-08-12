import Foundation
import QuillCodeApp

extension QuillCodeDesktopController {
    /// Routes a notification decision through the same serialized path as the in-app tool card.
    func decideNotificationApproval(requestID: String, approve: Bool, threadID: UUID?) {
        if let threadID, model.selectedThread?.id != threadID {
            selectThread(threadID)
        }
        runToolCardAction(ToolCardActionSurface(
            title: approve ? "Approve" : "Skip",
            kind: approve ? .approve : .deny,
            requestID: requestID,
            style: approve ? .primary : .secondary
        ))
    }
}
