import Foundation

public struct QuillCodeNotificationPreferences: Codable, Sendable, Hashable {
    public var agentRunNotificationsEnabled: Bool
    public var agentRunNotificationsOnlyWhenInactive: Bool
    public var automationNotificationsEnabled: Bool

    public init(
        agentRunNotificationsEnabled: Bool = true,
        agentRunNotificationsOnlyWhenInactive: Bool = true,
        automationNotificationsEnabled: Bool = true
    ) {
        self.agentRunNotificationsEnabled = agentRunNotificationsEnabled
        self.agentRunNotificationsOnlyWhenInactive = agentRunNotificationsOnlyWhenInactive
        self.automationNotificationsEnabled = automationNotificationsEnabled
    }

    public var anyNotificationEnabled: Bool {
        agentRunNotificationsEnabled || automationNotificationsEnabled
    }
}
