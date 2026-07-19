import Foundation
#if canImport(UserNotifications)
import UserNotifications
#endif

/// The notification category + action that turn a failed-run notification into a one-tap Retry —
/// resuming the dead thread without opening QuillCode. This is the *delivery* layer only: the pure
/// gate and the retry turn live in the model's `canRetryFailedRun`/`retryFailedRun` (guards at the
/// model level, like async approval), and this file just maps the OS action onto them, carrying the
/// thread id needed to find the failed run.
enum QuillCodeRetryNotification {
    static let categoryIdentifier = "QUILLCODE_RUN_FAILED"
    static let retryActionIdentifier = "QUILLCODE_RETRY_RUN"
    static let threadIDKey = "threadID"

    /// Maps a tapped action identifier onto a retry decision. Nil for the default tap (which just
    /// opens the app) or any unknown action, so only the explicit Retry button resumes a run.
    static func isRetryAction(_ identifier: String) -> Bool {
        identifier == retryActionIdentifier
    }

    static func userInfo(threadID: UUID) -> [String: String] {
        [threadIDKey: threadID.uuidString]
    }

    /// The failed run's thread id, parsed back out of a delivered notification. Nil (no retry) when
    /// absent or unparseable — a retry with no target must never fall back to "whatever is selected".
    static func threadID(fromUserInfo userInfo: [AnyHashable: Any]) -> UUID? {
        (userInfo[threadIDKey] as? String).flatMap(UUID.init(uuidString:))
    }

    #if canImport(UserNotifications)
    static var category: UNNotificationCategory {
        let retry = UNNotificationAction(
            identifier: retryActionIdentifier,
            title: "Retry",
            options: []
        )
        return UNNotificationCategory(
            identifier: categoryIdentifier,
            actions: [retry],
            intentIdentifiers: [],
            options: []
        )
    }
    #endif
}
