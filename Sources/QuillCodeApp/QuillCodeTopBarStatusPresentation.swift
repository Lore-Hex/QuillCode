import Foundation

enum TopBarStatusTone: String, Codable, Sendable, Hashable {
    case idle
    case running
    case failed
    case stopped
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

        return TopBarStatusPresentation(label: label.isEmpty ? "Idle" : label, tone: .idle, showsIndicator: false)
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
}
