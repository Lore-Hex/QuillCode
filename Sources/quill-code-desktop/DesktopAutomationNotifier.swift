import Foundation
#if canImport(UserNotifications)
import UserNotifications
#endif
import QuillCodeApp

protocol QuillCodeAutomationNotifying: Sendable {
    func deliver(_ report: AutomationRunReport)
    /// Post a "come back and look" notification for a just-finished agent run (finished / errored /
    /// blocked on approval). Defaulted to a no-op so the smoke/test notifiers need no changes.
    func deliver(_ notification: AgentRunNotification)
}

extension QuillCodeAutomationNotifying {
    func deliver(_ notification: AgentRunNotification) {}
}

enum DesktopAutomationNotifierFactory {
    static func platformDefault() -> any QuillCodeAutomationNotifying {
        #if canImport(UserNotifications)
        MacAutomationNotifier()
        #else
        LinuxAutomationNotifier()
        #endif
    }
}

#if canImport(UserNotifications)
struct MacAutomationNotifier: QuillCodeAutomationNotifying {
    func deliver(_ notification: AgentRunNotification) {
        Task {
            let center = UNUserNotificationCenter.current()
            guard await Self.ensureAuthorization(center: center) else { return }

            let content = UNMutableNotificationContent()
            content.title = notification.title
            content.body = notification.body
            content.sound = .default
            // Approval blocks get action buttons; failed runs get a one-tap Retry; other completed
            // runs only need a "come look" ping.
            if notification.kind == .needsApproval, let requestID = notification.approvalRequestID {
                content.categoryIdentifier = QuillCodeApprovalNotification.categoryIdentifier
                content.userInfo = QuillCodeApprovalNotification.userInfo(
                    threadID: notification.threadID,
                    requestID: requestID
                )
            } else if notification.kind == .failed {
                content.categoryIdentifier = QuillCodeRetryNotification.categoryIdentifier
                content.userInfo = QuillCodeRetryNotification.userInfo(threadID: notification.threadID)
            }

            let request = UNNotificationRequest(
                identifier: "quillcode-run-\(notification.id)",
                content: content,
                trigger: nil
            )
            try? await center.add(request)
        }
    }

    func deliver(_ report: AutomationRunReport) {
        Task {
            let center = UNUserNotificationCenter.current()
            guard await Self.ensureAuthorization(center: center) else { return }

            let content = UNMutableNotificationContent()
            content.title = report.title
            content.body = report.body
            content.sound = .default

            let request = UNNotificationRequest(
                identifier: automationIdentifier(for: report),
                content: content,
                trigger: nil
            )
            try? await center.add(request)
        }
    }

    private static func ensureAuthorization(center: UNUserNotificationCenter) async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            do {
                return try await center.requestAuthorization(options: [.alert, .sound])
            } catch {
                return false
            }
        @unknown default:
            return false
        }
    }

    private func automationIdentifier(for report: AutomationRunReport) -> String {
        "quillcode-automation-\(report.automationID.uuidString)-\(report.followUpThreadID.uuidString)"
    }
}
#endif

struct LinuxAutomationNotifier: QuillCodeAutomationNotifying {
    typealias AgentDelivery = @Sendable (AgentRunNotification) async -> SystemNotificationDeliveryResult
    typealias AutomationDelivery = @Sendable (AutomationRunReport) async -> SystemNotificationDeliveryResult

    private let deliverAgentNotification: AgentDelivery
    private let deliverAutomationReport: AutomationDelivery

    init(runner: LinuxNotificationCommandRunner = LinuxNotificationCommandRunner()) {
        self.init(
            deliverAgentNotification: { await runner.deliver($0) },
            deliverAutomationReport: { await runner.deliver($0) }
        )
    }

    init(
        deliverAgentNotification: @escaping AgentDelivery,
        deliverAutomationReport: @escaping AutomationDelivery
    ) {
        self.deliverAgentNotification = deliverAgentNotification
        self.deliverAutomationReport = deliverAutomationReport
    }

    func deliver(_ notification: AgentRunNotification) {
        Task {
            _ = await deliverAgentNotification(notification)
        }
    }

    func deliver(_ report: AutomationRunReport) {
        Task {
            _ = await deliverAutomationReport(report)
        }
    }
}
