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
        parts += elementAttributeParts(
            testID: testID,
            classes: classes,
            ariaLabel: ariaLabel,
            title: title,
            role: role,
            attributes: attributes
        )
        if disabled {
            parts.append("disabled")
            parts.append(#"aria-disabled="true""#)
        }
        return " " + parts.joined(separator: " ")
    }

    static func summary(
        _ label: String,
        testID: String? = nil,
        classes: [String] = [rowHitTargetClass],
        ariaLabel: String? = nil,
        title: String? = nil,
        attributes: [(String, String?)] = []
    ) -> String {
        """
        <summary\(elementAttributes(
            testID: testID,
            classes: classes,
            ariaLabel: ariaLabel,
            title: title,
            attributes: attributes
        ))>\(escape(label))</summary>
        """
    }

    private static func elementAttributes(
        testID: String?,
        classes: [String] = [],
        ariaLabel: String? = nil,
        title: String? = nil,
        role: String? = nil,
        attributes: [(String, String?)] = []
    ) -> String {
        let parts = elementAttributeParts(
            testID: testID,
            classes: classes,
            ariaLabel: ariaLabel,
            title: title,
            role: role,
            attributes: attributes
        )
        return parts.isEmpty ? "" : " " + parts.joined(separator: " ")
    }

    private static func elementAttributeParts(
        testID: String?,
        classes: [String],
        ariaLabel: String?,
        title: String?,
        role: String? = nil,
        attributes: [(String, String?)]
    ) -> [String] {
        var parts: [String] = []
        let classAttribute = classesWithDefaultHitTarget(classes)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        if !classAttribute.isEmpty {
            parts.append(#"class="\#(escape(classAttribute))""#)
        }
        if let testID, !testID.isEmpty {
            parts.append(#"data-testid="\#(escape(testID))""#)
        }
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
        return parts
    }

    private static func classesWithDefaultHitTarget(_ classes: [String]) -> [String] {
        let trimmed = classes
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if trimmed.contains(where: isHitTargetClass) {
            return trimmed
        }
        return trimmed + [textHitTargetClass]
    }

    private static func isHitTargetClass(_ className: String) -> Bool {
        [
            interactiveHitTargetClass,
            iconHitTargetClass,
            textHitTargetClass,
            rowHitTargetClass,
            capsuleHitTargetClass,
            formActionHitTargetClass
        ].contains(className)
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
