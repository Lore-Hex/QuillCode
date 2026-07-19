import Foundation
import UserNotifications

/// The notification category + actions that turn a "needs approval" run notification into a two-tap
/// decision — Approve or Skip the blocked gate — without opening QuillCode. This is the *delivery*
/// layer for async approval: the pure decision (which gate, approve vs deny, run the held tool and
/// resume the plan) lives in the model's `decidePendingApproval`; this file only maps OS notification
/// actions onto it and carries the thread + request id needed to find the gate.
enum QuillCodeApprovalNotification {
    static let categoryIdentifier = "QUILLCODE_APPROVAL"
    static let approveActionIdentifier = "QUILLCODE_APPROVE"
    static let skipActionIdentifier = "QUILLCODE_SKIP"
    static let threadIDKey = "threadID"
    static let requestIDKey = "requestID"

    /// Maps a tapped action identifier onto an approve (true) / skip (false) decision. Returns nil for
    /// the default tap (which just opens the app) or any unknown action, so those never silently
    /// approve or deny anything — only the explicit Approve/Skip buttons decide.
    static func decision(forActionIdentifier identifier: String) -> Bool? {
        switch identifier {
        case approveActionIdentifier:
            return true
        case skipActionIdentifier:
            return false
        default:
            return nil
        }
    }

    /// The userInfo payload carried on a needs-approval notification so a tapped action can find the
    /// exact thread + gate to decide.
    static func userInfo(threadID: UUID, requestID: String) -> [String: String] {
        [threadIDKey: threadID.uuidString, requestIDKey: requestID]
    }

    /// Pulls the (requestID, threadID) back out of a delivered notification's userInfo. The requestID
    /// is required (there is nothing to decide without it); the threadID is optional and used to select
    /// the right thread before deciding.
    static func target(fromUserInfo userInfo: [AnyHashable: Any]) -> (requestID: String, threadID: UUID?)? {
        guard let requestID = userInfo[requestIDKey] as? String, !requestID.isEmpty else { return nil }
        let threadID = (userInfo[threadIDKey] as? String).flatMap(UUID.init(uuidString:))
        return (requestID, threadID)
    }

    static var category: UNNotificationCategory {
        let approve = UNNotificationAction(
            identifier: approveActionIdentifier,
            title: "Approve",
            options: [.authenticationRequired]
        )
        let skip = UNNotificationAction(
            identifier: skipActionIdentifier,
            title: "Skip",
            options: []
        )
        return UNNotificationCategory(
            identifier: categoryIdentifier,
            actions: [approve, skip],
            intentIdentifiers: [],
            options: []
        )
    }
}

/// Routes a tapped Approve/Skip (or failed-run Retry) notification action back into the workspace on
/// the main actor. Held strongly by the controller because `UNUserNotificationCenter.delegate` is a
/// weak reference. One delegate for both categories — `UNUserNotificationCenter` has a single
/// delegate, so approval and retry actions must share it.
final class QuillCodeApprovalNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    private let onDecision: @MainActor @Sendable (_ requestID: String, _ approve: Bool, _ threadID: UUID?) -> Void
    private let onRetry: @MainActor @Sendable (_ threadID: UUID) -> Void

    init(
        onDecision: @escaping @MainActor @Sendable (_ requestID: String, _ approve: Bool, _ threadID: UUID?) -> Void,
        onRetry: @escaping @MainActor @Sendable (_ threadID: UUID) -> Void = { _ in }
    ) {
        self.onDecision = onDecision
        self.onRetry = onRetry
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        defer { completionHandler() }
        let userInfo = response.notification.request.content.userInfo

        if QuillCodeRetryNotification.isRetryAction(response.actionIdentifier) {
            guard let threadID = QuillCodeRetryNotification.threadID(fromUserInfo: userInfo) else { return }
            let handler = onRetry
            Task { @MainActor in
                handler(threadID)
            }
            return
        }

        guard let approve = QuillCodeApprovalNotification.decision(forActionIdentifier: response.actionIdentifier),
              let target = QuillCodeApprovalNotification.target(fromUserInfo: userInfo)
        else {
            return
        }
        let handler = onDecision
        Task { @MainActor in
            handler(target.requestID, approve, target.threadID)
        }
    }
}
