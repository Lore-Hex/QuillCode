import Foundation

enum WorkspaceHTMLPrimitives {
    static let interactiveHitTargetClass = "interactive-hit-target"
    static let iconHitTargetClass = "hit-target-icon"
    static let textHitTargetClass = "hit-target-text"
    static let rowHitTargetClass = "hit-target-row"
    static let capsuleHitTargetClass = "hit-target-capsule"
    static let formActionHitTargetClass = "hit-target-form-action"

    static func escape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    static func button(
        _ label: String,
        testID: String,
        type: String = "button",
        classes: [String] = [],
        ariaLabel: String? = nil,
        title: String? = nil,
        role: String? = nil,
        disabled: Bool = false,
        attributes: [(String, String?)] = []
    ) -> String {
        """
        <button\(buttonAttributes(
            type: type,
            testID: testID,
            classes: classes,
            ariaLabel: ariaLabel,
            title: title,
            role: role,
            disabled: disabled,
            attributes: attributes
        ))>\(escape(label))</button>
        """
    }

    static func commandButton(
        _ label: String,
        testID: String,
        commandID: String,
        classes: [String] = [textHitTargetClass],
        ariaLabel: String? = nil,
        title: String? = nil,
        role: String? = nil,
        disabled: Bool = false,
        attributes: [(String, String?)] = []
    ) -> String {
        button(
            label,
            testID: testID,
            classes: classes,
            ariaLabel: ariaLabel,
            title: title,
            role: role,
            disabled: disabled,
            attributes: [("data-command-id", commandID)] + attributes
        )
    }

    static func buttonAttributes(
        type: String = "button",
        testID: String,
        classes: [String] = [],
        ariaLabel: String? = nil,
        title: String? = nil,
        role: String? = nil,
        disabled: Bool = false,
        attributes: [(String, String?)] = []
    ) -> String {
        var parts = [
            #"type="\#(escape(type))""#
        ]
        let classAttribute = classes
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        if !classAttribute.isEmpty {
            parts.append(#"class="\#(escape(classAttribute))""#)
        }
        parts.append(#"data-testid="\#(escape(testID))""#)
        if let ariaLabel, !ariaLabel.isEmpty {
            parts.append(#"aria-label="\#(escape(ariaLabel))""#)
        }
        if let title, !title.isEmpty {
            parts.append(#"title="\#(escape(title))""#)
        }
        if let role, !role.isEmpty {
            parts.append(#"role="\#(escape(role))""#)
        }
        for (name, value) in attributes {
            let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedName.isEmpty else { continue }
            if let value {
                parts.append(#"\#(escape(trimmedName))="\#(escape(value))""#)
            } else {
                parts.append(escape(trimmedName))
            }
        }
        if disabled {
            parts.append("disabled")
            parts.append(#"aria-disabled="true""#)
        }
        return " " + parts.joined(separator: " ")
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
