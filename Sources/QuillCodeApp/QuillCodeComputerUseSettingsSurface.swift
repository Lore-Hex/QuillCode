import Foundation
import QuillCodeCore
import QuillComputerUseKit

public struct ComputerUseRequirementSurface: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var title: String
    public var detail: String
    public var statusLabel: String
    public var isGranted: Bool
    public var command: WorkspaceCommandSurface

    public init(
        id: String,
        title: String,
        detail: String,
        statusLabel: String,
        isGranted: Bool,
        command: WorkspaceCommandSurface
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.statusLabel = statusLabel
        self.isGranted = isGranted
        self.command = command
    }
}

enum ComputerUseSettingsProjection {
    static func defaultStatus() -> ComputerUseStatus {
        .permissionStatus(screenRecordingGranted: false, accessibilityGranted: false)
    }

    static func statusLabel(_ status: ComputerUseStatus) -> String {
        if status.available {
            return "Ready"
        }
        if status.unavailableReason != nil {
            return "Unavailable"
        }
        if !status.screenRecordingGranted && !status.accessibilityGranted {
            return "Setup needed"
        }
        if !status.screenRecordingGranted {
            return "Screen Recording needed"
        }
        return "Accessibility needed"
    }

    static func setupSummary(_ status: ComputerUseStatus) -> String {
        if status.available {
            return "Ready for screenshots, clicks, typing, scrolling, and keyboard shortcuts."
        }
        if let unavailableReason = status.unavailableReason {
            return unavailableReason
        }
        return "Computer Use needs desktop permissions before QuillCode can inspect or control the screen."
    }

    static func nextAction(_ status: ComputerUseStatus) -> String {
        if status.available {
            return "Computer Use is enabled. Ask QuillCode to inspect the screen or operate an app."
        }
        if status.unavailableReason != nil {
            return "Install or enable the required desktop backend, then refresh status."
        }
        if !status.screenRecordingGranted && !status.accessibilityGranted {
            return "Open Screen Recording first, enable QuillCode, then open Accessibility."
        }
        if !status.screenRecordingGranted {
            return "Open Screen Recording, enable QuillCode, then refresh status."
        }
        return "Open Accessibility, enable QuillCode, then refresh status."
    }

    static func onboardingSteps(status: ComputerUseStatus, config: AppConfig) -> [String] {
        if let unavailableReason = status.unavailableReason {
            return [
                unavailableReason,
                "After installing the missing backend or helper tools, refresh status before asking QuillCode to use the screen."
            ]
        }

        var steps = [String]()
        if !status.screenRecordingGranted {
            steps.append("Enable Screen Recording so QuillCode can see screenshots and verify visual state.")
        }
        if !status.accessibilityGranted {
            steps.append("Enable Accessibility so QuillCode can click, type, scroll, move the cursor, and send shortcuts.")
        }
        if steps.isEmpty {
            steps.append("Computer Use can inspect screenshots and dispatch input to the foreground app.")
        } else {
            steps.append("Return to QuillCode and refresh status after macOS accepts the permission changes.")
        }

        if config.computerUseApprovedBundleIdentifiers.isEmpty && config.computerUseApprovedAppNames.isEmpty {
            steps.append("Add foreground app approvals when you want Computer Use limited to specific apps.")
        } else {
            steps.append("Foreground app approvals are active; Computer Use will stop before controlling unapproved apps.")
        }
        return steps
    }

    static func requirements(
        status: ComputerUseStatus,
        screenRecordingCommand: WorkspaceCommandSurface,
        accessibilityCommand: WorkspaceCommandSurface
    ) -> [ComputerUseRequirementSurface] {
        guard status.unavailableReason == nil else {
            return []
        }
        return [
            ComputerUseRequirementSurface(
                id: "screen-recording",
                title: "Screen Recording",
                detail: "Required for screenshots and visual inspection.",
                statusLabel: status.screenRecordingGranted ? "Granted" : "Required",
                isGranted: status.screenRecordingGranted,
                command: screenRecordingCommand
            ),
            ComputerUseRequirementSurface(
                id: "accessibility",
                title: "Accessibility",
                detail: "Required for clicks, typing, scrolling, cursor moves, and keyboard shortcuts.",
                statusLabel: status.accessibilityGranted ? "Granted" : "Required",
                isGranted: status.accessibilityGranted,
                command: accessibilityCommand
            )
        ]
    }

    static func approvalStatusLabel(_ config: AppConfig) -> String {
        let count = config.computerUseApprovedBundleIdentifiers.count + config.computerUseApprovedAppNames.count
        guard count > 0 else { return "Unrestricted" }
        return "\(count) approved"
    }

    static func approvalSummary(_ config: AppConfig) -> String {
        let bundleCount = config.computerUseApprovedBundleIdentifiers.count
        let appNameCount = config.computerUseApprovedAppNames.count
        guard bundleCount + appNameCount > 0 else {
            return "Computer Use may operate whichever app is in front. "
                + "Add approvals to restrict control to named apps."
        }
        let bundlePart = bundleCount == 1 ? "1 bundle ID" : "\(bundleCount) bundle IDs"
        let appPart = appNameCount == 1 ? "1 app name" : "\(appNameCount) app names"
        return "Computer Use is restricted to \(bundlePart) and \(appPart)."
    }
}
