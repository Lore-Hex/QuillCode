import Foundation

enum WorkspaceHTMLPrimitives {
    static let interactiveHitTargetClass = "interactive-hit-target"

    static func escape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    static func executionContextChip(
        _ context: ExecutionContextSurface?,
        testID: String
    ) -> String {
        guard let context else { return "" }
        let title: String
        switch context.kind {
        case .local:
            title = context.label
        case .sshRemote:
            title = "\(context.label) · \(context.detail)"
        }
        return """
        <span class="execution-context-chip" data-testid="\(escape(testID))" data-execution-context-kind="\(escape(context.kind.rawValue))">\(escape(title))</span>
        """
    }
}
