import Foundation
import UserNotifications
import QuillCodeApp

protocol QuillCodeAutomationNotifying: Sendable {
    func deliver(_ report: AutomationRunReport)
}

struct MacAutomationNotifier: QuillCodeAutomationNotifying {
    func deliver(_ report: AutomationRunReport) {
        Task {
            let center = UNUserNotificationCenter.current()
            guard await Self.ensureAuthorization(center: center) else { return }

            let content = UNMutableNotificationContent()
            content.title = report.title
            content.body = report.body
            content.sound = .default

            let request = UNNotificationRequest(
                identifier: "quillcode-automation-\(report.automationID.uuidString)-\(report.followUpThreadID.uuidString)",
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
}
