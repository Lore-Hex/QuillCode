import SwiftUI

enum TopBarToneColor {
    static func activityHairline(for topBar: TopBarSurface) -> Color {
        if let issue = topBar.runtimeIssuePresentation {
            return runtimeIssue(issue.tone)
        }
        return status(topBar.agentStatusPresentation.tone)
    }

    static func status(_ tone: TopBarStatusTone) -> Color {
        switch tone {
        case .failed:
            return QuillCodePalette.red
        case .running:
            return QuillCodePalette.yellow
        case .stopped:
            return QuillCodePalette.muted
        case .idle:
            return QuillCodePalette.green
        }
    }

    static func runtimeIssue(_ tone: TopBarRuntimeIssueTone) -> Color {
        switch tone {
        case .error:
            return QuillCodePalette.red
        case .warning:
            return QuillCodePalette.yellow
        }
    }
}
