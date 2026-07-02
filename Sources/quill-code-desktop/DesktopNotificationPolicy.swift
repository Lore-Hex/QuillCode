import QuillCodeCore

enum DesktopNotificationPolicy {
    static func shouldDeliverAgentRun(
        preferences: QuillCodeNotificationPreferences,
        appIsActive: Bool
    ) -> Bool {
        guard preferences.agentRunNotificationsEnabled else { return false }
        return !preferences.agentRunNotificationsOnlyWhenInactive || !appIsActive
    }

    static func shouldDeliverAutomationReport(
        preferences: QuillCodeNotificationPreferences
    ) -> Bool {
        preferences.automationNotificationsEnabled
    }
}
