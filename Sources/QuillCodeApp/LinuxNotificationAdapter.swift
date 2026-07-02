import Foundation

public struct SystemNotificationCommand: Sendable, Hashable {
    public var executable: String
    public var arguments: [String]

    public init(executable: String, arguments: [String]) {
        self.executable = executable
        self.arguments = arguments
    }
}

public enum LinuxNotificationAdapter {
    public static let executable = "notify-send"

    public static func command(for notification: AgentRunNotification) -> SystemNotificationCommand {
        command(
            title: notification.title,
            body: notification.body,
            policy: policy(for: notification.kind)
        )
    }

    public static func command(for report: AutomationRunReport) -> SystemNotificationCommand {
        command(
            title: report.title,
            body: report.body,
            policy: .automation
        )
    }

    private static func command(
        title: String,
        body: String,
        policy: DeliveryPolicy
    ) -> SystemNotificationCommand {
        SystemNotificationCommand(
            executable: executable,
            arguments: [
                "--app-name=QuillCode",
                "--urgency=\(policy.urgency.rawValue)",
                "--expire-time=\(policy.expireTimeMilliseconds)",
                boundedText(title, fallback: "QuillCode", limit: 96),
                boundedText(body, fallback: "Open QuillCode for details.", limit: 240)
            ]
        )
    }

    private static func policy(for kind: AgentRunNotification.Kind) -> DeliveryPolicy {
        switch kind {
        case .needsApproval:
            .init(urgency: .critical, expireTimeMilliseconds: 0)
        case .failed, .checksFailing:
            .init(urgency: .critical, expireTimeMilliseconds: 12_000)
        case .unverified:
            .init(urgency: .normal, expireTimeMilliseconds: 8_000)
        case .finished:
            .init(urgency: .normal, expireTimeMilliseconds: 6_000)
        case .verifiedGreen:
            .init(urgency: .low, expireTimeMilliseconds: 5_000)
        }
    }

    private static func boundedText(_ value: String, fallback: String, limit: Int) -> String {
        let cleaned = collapsedNotificationText(value)
        let nonEmpty = cleaned.isEmpty ? fallback : cleaned
        guard nonEmpty.count > limit, limit > 3 else { return nonEmpty }

        let end = nonEmpty.index(nonEmpty.startIndex, offsetBy: limit - 3)
        let prefix = String(nonEmpty[..<end]).trimmingCharacters(in: .whitespaces)
        return prefix + "..."
    }

    private static func collapsedNotificationText(_ value: String) -> String {
        var result = ""
        var previousWasSpace = false
        for scalar in value.unicodeScalars {
            if CharacterSet.whitespacesAndNewlines.contains(scalar)
                || CharacterSet.controlCharacters.contains(scalar) {
                if !previousWasSpace {
                    result.append(" ")
                    previousWasSpace = true
                }
            } else {
                result.unicodeScalars.append(scalar)
                previousWasSpace = false
            }
        }
        return result.trimmingCharacters(in: .whitespaces)
    }

    private struct DeliveryPolicy: Sendable, Hashable {
        var urgency: NotificationUrgency
        var expireTimeMilliseconds: Int

        static let automation = Self(urgency: .normal, expireTimeMilliseconds: 8_000)
    }

    private enum NotificationUrgency: String, Sendable, Hashable {
        case low
        case normal
        case critical
    }
}
