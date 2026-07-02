import Foundation

public struct SystemNotificationDeliveryResult: Sendable, Hashable {
    public enum Status: Sendable, Hashable {
        case delivered
        case unavailable(exitCode: Int32, stderr: String)
        case failed(exitCode: Int32, stderr: String)
    }

    public var command: SystemNotificationCommand
    public var status: Status
    public var stdout: String

    public init(
        command: SystemNotificationCommand,
        status: Status,
        stdout: String = ""
    ) {
        self.command = command
        self.status = status
        self.stdout = stdout
    }
}

public struct LinuxNotificationCommandRunner: Sendable {
    private let environment: [String: String]?

    public init(environment: [String: String]? = nil) {
        self.environment = environment
    }

    public func deliver(_ notification: AgentRunNotification) async -> SystemNotificationDeliveryResult {
        await run(LinuxNotificationAdapter.command(for: notification))
    }

    public func deliver(_ report: AutomationRunReport) async -> SystemNotificationDeliveryResult {
        await run(LinuxNotificationAdapter.command(for: report))
    }

    public func run(_ command: SystemNotificationCommand) async -> SystemNotificationDeliveryResult {
        let executable = command.executable.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !executable.isEmpty else {
            return SystemNotificationDeliveryResult(
                command: command,
                status: .unavailable(exitCode: 127, stderr: "Notification executable is empty.")
            )
        }

        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [executable] + command.arguments
        process.environment = environment
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            return SystemNotificationDeliveryResult(
                command: command,
                status: .unavailable(
                    exitCode: 127,
                    stderr: "Could not launch notification helper: \(error.localizedDescription)"
                )
            )
        }

        process.waitUntilExit()

        let output = readString(from: stdout)
        let errorOutput = readString(from: stderr)
        return SystemNotificationDeliveryResult(
            command: command,
            status: status(exitCode: process.terminationStatus, stderr: errorOutput),
            stdout: output
        )
    }

    private func status(exitCode: Int32, stderr: String) -> SystemNotificationDeliveryResult.Status {
        switch exitCode {
        case 0:
            .delivered
        case 126, 127:
            .unavailable(exitCode: exitCode, stderr: stderr)
        default:
            .failed(exitCode: exitCode, stderr: stderr)
        }
    }

    private func readString(from pipe: Pipe) -> String {
        String(
            data: pipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
    }
}
