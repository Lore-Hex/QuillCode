import Foundation

enum WorkspaceHTMLPrimitives {
    static let ownedHitTargetClass = "hit-target-owned"
    static let interactiveHitTargetClass = "interactive-hit-target"
    static let iconHitTargetClass = "hit-target-icon"
    static let textHitTargetClass = "hit-target-text"
    static let textEntryHitTargetClass = "hit-target-text-entry"
    static let rowHitTargetClass = "hit-target-row"
    static let capsuleHitTargetClass = "hit-target-capsule"
    static let formActionHitTargetClass = "hit-target-form-action"
    static let hitTargetKindAttributeName = "data-hit-target-kind"

    static func hitTargetKindAttribute(for className: String) -> String {
        hitTargetKindAttribute(forClasses: [className])
    }

    static func hitTargetKindAttribute(forClasses classes: [String]) -> String {
        guard let kind = hitTargetKind(forClasses: classes) else { return "" }
        return #" \#(hitTargetKindAttributeName)="\#(escape(kind))""#
    }

    static func hitTargetAttributes(for className: String) -> String {
        hitTargetAttributes(classes: [className])
    }

    static func hitTargetAttributes(classes: [String]) -> String {
        let parts = classAndHitTargetKindAttributeParts(
            classes: normalizedClasses(classes),
            explicitAttributes: []
        )
        return parts.isEmpty ? "" : " " + parts.joined(separator: " ")
    }

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
        let normalizedClasses = classesWithDefaultHitTarget(classes)
        parts += classAndHitTargetKindAttributeParts(
            classes: normalizedClasses,
            explicitAttributes: attributes
        )
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
        let trimmed = normalizedClasses(classes)
        if trimmed.contains(where: isHitTargetClass) {
            return trimmed
        }
        return trimmed + [textHitTargetClass]
    }

    private static func normalizedClasses(_ classes: [String]) -> [String] {
        classes
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func classAndHitTargetKindAttributeParts(
        classes: [String],
        explicitAttributes: [(String, String?)]
    ) -> [String] {
        let classAttribute = classes.joined(separator: " ")
        var parts: [String] = []
        if !classAttribute.isEmpty {
            parts.append(#"class="\#(escape(classAttribute))""#)
        }
        if !explicitAttributes.contains(where: { $0.0 == hitTargetKindAttributeName }),
           let hitTargetKind = hitTargetKind(forClasses: classes) {
            parts.append(#"\#(hitTargetKindAttributeName)="\#(escape(hitTargetKind))""#)
        }
        return parts
    }

    private static func isHitTargetClass(_ className: String) -> Bool {
        hitTargetKind(forClasses: [className]) != nil
    }

    private static func hitTargetKind(forClasses classes: [String]) -> String? {
        let normalized = Set(classes.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        })
        for (className, kind) in hitTargetKindByClass {
            if normalized.contains(className) {
                return kind
            }
        }
        return nil
    }

    private static let hitTargetKindByClass: [(String, String)] = [
        (iconHitTargetClass, "icon"),
        (textEntryHitTargetClass, "text-entry"),
        (rowHitTargetClass, "row"),
        (capsuleHitTargetClass, "capsule"),
        (formActionHitTargetClass, "form-action"),
        (textHitTargetClass, "text"),
        (interactiveHitTargetClass, "link"),
        (ownedHitTargetClass, "owned")
    ]

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
