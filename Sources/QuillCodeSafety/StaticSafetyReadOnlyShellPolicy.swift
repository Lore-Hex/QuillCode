import Foundation
import QuillCodeCore

enum StaticSafetyReadOnlyShellPolicy {
    static func intentMatches(request: StaticSafetyRequest, context: SafetyContext) -> Bool {
        guard context.toolCall.name.contains("shell.run"),
              let command = shellCommand(from: context.toolCall)
        else {
            return false
        }
        let normalized = command
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard isSingleReadCommand(normalized) else {
            return false
        }

        if isPwdCommand(normalized) {
            return isCurrentDirectoryRequest(request)
        }
        if isLsCommand(normalized) {
            return isFileListingRequest(request)
        }
        if isGitStatusCommand(normalized) {
            return isGitStatusRequest(request)
        }
        return diagnosticRules.contains { rule in
            rule.commandMatches(normalized) && rule.requestMatches(request)
        }
    }

    private static func shellCommand(from call: ToolCall) -> String? {
        try? ToolArguments(call.argumentsJSON).requiredString("cmd")
    }

    private static func isSingleReadCommand(_ command: String) -> Bool {
        [";", "&&", "||", "|", "`", "$(", ">", "<"].allSatisfy { !command.contains($0) }
    }

    private static func isPwdCommand(_ command: String) -> Bool {
        command == "pwd" || command == "/bin/pwd" || command == "command pwd"
    }

    private static func isLsCommand(_ command: String) -> Bool {
        let parts = command.split(separator: " ").map(String.init)
        guard parts.first == "ls", parts.count <= 3 else {
            return false
        }
        return parts.dropFirst().allSatisfy { part in
            if part.hasPrefix("-") {
                return part.dropFirst().allSatisfy { "1aAlLh".contains($0) }
            }
            return isSafeRelativePath(part)
        }
    }

    private static func isGitStatusCommand(_ command: String) -> Bool {
        let parts = words(command)
        guard parts.count >= 2,
              parts[0] == "git",
              parts[1] == "status"
        else {
            return false
        }
        return parts.dropFirst(2).allSatisfy { part in
            part == "--short" || part == "-s" || part == "--porcelain" || part == "--branch" || part == "-b"
        }
    }

    private struct DiagnosticRule: Sendable {
        var commandMatches: @Sendable (String) -> Bool
        var requestMatches: @Sendable (StaticSafetyRequest) -> Bool
    }

    private static let diagnosticRules: [DiagnosticRule] = [
        .init(commandMatches: isWhoamiCommand, requestMatches: isIdentityRequest),
        .init(commandMatches: isDateCommand, requestMatches: isDateTimeRequest),
        .init(commandMatches: isHostnameCommand, requestMatches: isHostnameRequest),
        .init(commandMatches: isUnameCommand, requestMatches: isOperatingSystemRequest),
        .init(commandMatches: isUptimeCommand, requestMatches: isUptimeRequest),
        .init(commandMatches: isProcessListCommand, requestMatches: isProcessListRequest),
        .init(commandMatches: isMemoryCommand, requestMatches: isMemoryRequest),
        .init(commandMatches: isDiskCommand, requestMatches: isDiskRequest)
    ]

    private static func isWhoamiCommand(_ command: String) -> Bool {
        command == "whoami" || command == "/usr/bin/whoami" || command == "id -un" || command == "id -u"
    }

    private static func isDateCommand(_ command: String) -> Bool {
        command == "date" || command == "/bin/date" || command == "/usr/bin/date"
    }

    private static func isHostnameCommand(_ command: String) -> Bool {
        command == "hostname" || command == "/bin/hostname" || command == "/usr/bin/hostname"
    }

    private static func isUnameCommand(_ command: String) -> Bool {
        let parts = words(command)
        guard let executable = parts.first,
              executable == "uname" || executable == "/usr/bin/uname",
              parts.count <= 2
        else {
            return false
        }
        guard let flag = parts.dropFirst().first else {
            return true
        }
        return flag.hasPrefix("-") && flag.dropFirst().allSatisfy { "amnprsvio".contains($0) }
    }

    private static func isUptimeCommand(_ command: String) -> Bool {
        command == "uptime" || command == "/usr/bin/uptime"
    }

    private static func isProcessListCommand(_ command: String) -> Bool {
        switch words(command) {
        case ["ps"], ["ps", "aux"], ["ps", "-ef"], ["ps", "-e"], ["ps", "-a"], ["ps", "-ax"]:
            return true
        default:
            return false
        }
    }

    private static func isMemoryCommand(_ command: String) -> Bool {
        let parts = words(command)
        switch parts.first {
        case "free":
            return parts.count <= 2 && parts.dropFirst().allSatisfy { ["-h", "-m", "-g", "-k", "-b"].contains($0) }
        case "vm_stat":
            return parts.count == 1
        default:
            return false
        }
    }

    private static func isDiskCommand(_ command: String) -> Bool {
        let parts = words(command)
        guard parts.first == "df", parts.count <= 5 else {
            return false
        }
        return parts.dropFirst().allSatisfy { part in
            if part.hasPrefix("-") {
                return part.dropFirst().allSatisfy { "hHkmgTP".contains($0) }
            }
            return isSafeInspectionPath(part)
        }
    }

    private static func words(_ command: String) -> [String] {
        command.split(separator: " ").map(String.init)
    }

    private static func isSafeRelativePath(_ path: String) -> Bool {
        !path.isEmpty
            && !path.hasPrefix("/")
            && !path.hasPrefix("~")
            && !path.contains("..")
    }

    private static func isSafeInspectionPath(_ path: String) -> Bool {
        !path.isEmpty
            && !path.hasPrefix("~")
            && !path.contains("..")
            && path.rangeOfCharacter(from: CharacterSet(charactersIn: "*?[]{};$`\\\"'")) == nil
    }

    private static func isCurrentDirectoryRequest(_ request: StaticSafetyRequest) -> Bool {
        request.containsAffirmedAny([
            "current directory",
            "working directory",
            "current folder",
            "workspace path",
            "where am i",
            "pwd"
        ])
    }

    private static func isFileListingRequest(_ request: StaticSafetyRequest) -> Bool {
        request.containsAffirmedAny(["list files", "list the files", "show files", "show the files"])
            || ((request.containsToken("files") || request.containsToken("directory") || request.containsToken("folder"))
                && (request.containsToken("list") || request.containsToken("show") || request.containsToken("what")))
    }

    private static func isGitStatusRequest(_ request: StaticSafetyRequest) -> Bool {
        request.containsAffirmedAny([
            "git status",
            "repo status",
            "repository status",
            "working tree status",
            "working directory status"
        ])
            || (request.containsToken("status") && (request.containsToken("git") || request.containsToken("repo")))
    }

    private static func isIdentityRequest(_ request: StaticSafetyRequest) -> Bool {
        request.containsAffirmedAny([
            "whoami",
            "who am i",
            "current user",
            "username",
            "which user"
        ])
    }

    private static func isDateTimeRequest(_ request: StaticSafetyRequest) -> Bool {
        request.containsAffirmedAny([
            "what time",
            "current time",
            "what date",
            "current date",
            "system time",
            "system date"
        ])
            || request.containsToken("date")
            || request.containsToken("time")
    }

    private static func isHostnameRequest(_ request: StaticSafetyRequest) -> Bool {
        request.containsAffirmedAny([
            "hostname",
            "host name",
            "machine name",
            "computer name",
            "device name"
        ])
    }

    private static func isOperatingSystemRequest(_ request: StaticSafetyRequest) -> Bool {
        request.containsAffirmedAny([
            "operating system",
            "system version",
            "kernel version",
            "linux version",
            "macos version",
            "unix name"
        ])
            || request.containsToken("os")
            || request.containsToken("kernel")
            || request.containsToken("uname")
    }

    private static func isUptimeRequest(_ request: StaticSafetyRequest) -> Bool {
        request.containsAffirmedAny([
            "uptime",
            "how long has it been running",
            "how long has the system been running",
            "how long since reboot",
            "last reboot"
        ])
    }

    private static func isProcessListRequest(_ request: StaticSafetyRequest) -> Bool {
        request.containsAffirmedAny([
            "list processes",
            "show processes",
            "running processes",
            "process list",
            "what is running",
            "show running apps"
        ])
            || (request.containsToken("processes")
                && (request.containsToken("list") || request.containsToken("show") || request.containsToken("running")))
    }

    private static func isMemoryRequest(_ request: StaticSafetyRequest) -> Bool {
        request.containsAffirmedAny([
            "memory usage",
            "ram usage",
            "free memory",
            "available memory",
            "how much memory",
            "how much ram"
        ])
            || request.containsToken("memory")
            || request.containsToken("ram")
    }

    private static func isDiskRequest(_ request: StaticSafetyRequest) -> Bool {
        request.containsAffirmedAny([
            "disk usage",
            "disk space",
            "storage usage",
            "storage space",
            "free space",
            "how much disk",
            "how much hd"
        ])
            || request.containsToken("disk")
            || request.containsToken("storage")
            || request.containsToken("hd")
    }
}
