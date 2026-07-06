import Foundation

enum TopBarStatusTone: String, Codable, Sendable, Hashable {
    case idle
    case running
    case failed
    case stopped
}

public enum TopBarAgentStatusLabel {
    public static let idle = "Idle"
    public static let queued = "Queued"
    public static let running = "Running"
    public static let review = "Review"
    public static let streaming = "Streaming"
    public static let finishing = "Finishing"
    public static let failed = "Failed"
    public static let stopped = "Stopped"
    public static let terminal = "Terminal"
}

struct TopBarStatusPresentation: Codable, Sendable, Hashable {
    var label: String
    var tone: TopBarStatusTone
    var showsIndicator: Bool

    var accessibilityLabel: String {
        "Agent status: \(label)"
    }

    static func agentStatus(_ status: String) -> TopBarStatusPresentation {
        let label = status.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = label.lowercased()

        if normalized.contains("fail") || normalized.contains("error") {
            return TopBarStatusPresentation(label: label, tone: .failed, showsIndicator: true)
        }

        if normalized.contains("run")
            || normalized.contains("work")
            || normalized.contains("terminal")
        {
            return TopBarStatusPresentation(label: label, tone: .running, showsIndicator: true)
        }

        if normalized.contains("stop") || normalized.contains("cancel") {
            return TopBarStatusPresentation(label: label, tone: .stopped, showsIndicator: true)
        }

        return TopBarStatusPresentation(
            label: label.isEmpty ? TopBarAgentStatusLabel.idle : label,
            tone: .idle,
            showsIndicator: false
        )
    }
}

enum TopBarRuntimeIssueTone: String, Codable, Sendable, Hashable {
    case warning
    case error
}

struct TopBarRuntimeIssuePresentation: Codable, Sendable, Hashable {
    var label: String
    var tone: TopBarRuntimeIssueTone
}

extension TopBarSurface {
    var agentStatusPresentation: TopBarStatusPresentation {
        TopBarStatusPresentation.agentStatus(agentStatus)
    }

    var runtimeIssuePresentation: TopBarRuntimeIssuePresentation? {
        guard let runtimeIssueLabel else { return nil }
        let tone: TopBarRuntimeIssueTone = runtimeIssueSeverity == .error ? .error : .warning
        return TopBarRuntimeIssuePresentation(label: runtimeIssueLabel, tone: tone)
    }

    var showsActivityHairline: Bool {
        agentStatusPresentation.showsIndicator || runtimeIssuePresentation != nil
    }

    var topBarHelpText: String {
        var parts = [subtitle, agentStatusPresentation.accessibilityLabel]
        if let tokenBudget {
            parts.append(tokenBudget.accessibilityLabel)
        }
        if let liveWork {
            parts.append(liveWork.detail)
        }
        if let runtimeIssuePresentation {
            parts.append("Issue: \(runtimeIssuePresentation.label)")
        }
        return parts.joined(separator: ". ")
    }

    var topBarAccessibilityLabel: String {
        var parts = [
            primaryTitle,
            subtitle,
            agentStatusPresentation.accessibilityLabel
        ]
        if let branchStatusLabel {
            parts.append("branch: \(branchStatusLabel)")
        }
        if let worktreeStatusLabel {
            parts.append("worktree: \(worktreeStatusLabel)")
        }
        if let liveWork {
            parts.append("current work: \(liveWork.label)")
        }
        if let tokenBudget {
            parts.append("token budget: \(tokenBudget.accessibilityLabel)")
        }
        if let spendStatusLabel {
            parts.append("spend: \(spendStatusLabel)")
        } else if tokenBudget == nil, let usageStatusLabel {
            parts.append("token usage: \(usageStatusLabel)")
        }
        if let runtimeIssuePresentation {
            parts.append("issue: \(runtimeIssuePresentation.label)")
        }
        return parts.joined(separator: ", ")
    }
}
