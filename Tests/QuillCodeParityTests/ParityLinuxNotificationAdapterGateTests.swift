import XCTest

final class ParityLinuxNotificationAdapterGateTests: QuillCodeParityTestCase {
    func testLinuxNotificationsStayPlatformNeutralAndArgvBased() throws {
        let adapterText = try Self.appSourceText(named: "LinuxNotificationAdapter.swift")
        let runnerText = try Self.appSourceText(named: "LinuxNotificationCommandRunner.swift")
        let desktopNotifierText = try Self.desktopSourceText(named: "DesktopAutomationNotifier.swift")

        Self.assertSource(adapterText, containsAll: [
            "public enum LinuxNotificationAdapter",
            "public struct SystemNotificationCommand",
            "notify-send",
            "--app-name=QuillCode",
            "--urgency=",
            "--expire-time=",
            "AutomationRunReport",
            "AgentRunNotification"
        ])
        Self.assertSource(adapterText, excludesAll: [
            "UserNotifications",
            "AppKit",
            "Process()",
            "shell"
        ])
        Self.assertSource(runnerText, containsAll: [
            "public struct LinuxNotificationCommandRunner",
            "SystemNotificationDeliveryResult",
            "LinuxNotificationAdapter.command(for: notification)",
            "LinuxNotificationAdapter.command(for: report)",
            "Process()",
            "process.arguments = [executable] + command.arguments"
        ])
        Self.assertSource(runnerText, excludesAll: [
            "UserNotifications",
            "AppKit",
            "-c"
        ])
        Self.assertSource(desktopNotifierText, excludes: "notify-send")
    }
}
