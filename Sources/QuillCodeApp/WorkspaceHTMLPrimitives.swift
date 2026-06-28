import Foundation

enum WorkspaceHTMLHitTargetKind: String, CaseIterable {
    case icon
    case text
    case textEntry = "text-entry"
    case row
    case capsule
    case formAction = "form-action"
    case adjustable = "adjustable"
    case link
    case owned

    var className: String {
        switch self {
        case .icon:
            return "hit-target-icon"
        case .text:
            return "hit-target-text"
        case .textEntry:
            return "hit-target-text-entry"
        case .row:
            return "hit-target-row"
        case .capsule:
            return "hit-target-capsule"
        case .formAction:
            return "hit-target-form-action"
        case .adjustable:
            return "hit-target-adjustable"
        case .link:
            return "hit-target-link"
        case .owned:
            return "hit-target-owned"
        }
    }

    var action: String {
        switch self {
        case .textEntry:
            return "text-input"
        case .adjustable:
            return "adjust"
        case .link:
            return "link"
        case .owned:
            return "owned-gesture"
        case .icon, .text, .row, .capsule, .formAction:
            return "press"
        }
    }
}

enum WorkspaceHTMLPrimitives {
    static let ownedHitTargetClass = WorkspaceHTMLHitTargetKind.owned.className
    static let linkHitTargetClass = WorkspaceHTMLHitTargetKind.link.className
    @available(*, deprecated, message: "Use linkHitTargetClass for explicit link semantics.")
    static let interactiveHitTargetClass = WorkspaceHTMLHitTargetKind.link.className
    static let iconHitTargetClass = WorkspaceHTMLHitTargetKind.icon.className
    static let textHitTargetClass = WorkspaceHTMLHitTargetKind.text.className
    static let textEntryHitTargetClass = WorkspaceHTMLHitTargetKind.textEntry.className
    static let rowHitTargetClass = WorkspaceHTMLHitTargetKind.row.className
    static let capsuleHitTargetClass = WorkspaceHTMLHitTargetKind.capsule.className
    static let formActionHitTargetClass = WorkspaceHTMLHitTargetKind.formAction.className
    static let adjustableHitTargetClass = WorkspaceHTMLHitTargetKind.adjustable.className
    static let hitTargetKindAttributeName = "data-hit-target-kind"
    static let hitTargetActionAttributeName = "data-hit-target-action"
    static let hitTargetSourceAttributeName = "data-hit-target-source"

    static func hitTargetKindAttribute(for className: String) -> String {
        hitTargetKindAttribute(forClasses: [className])
    }

    static func hitTargetKindAttribute(forClasses classes: [String]) -> String {
        guard let kind = hitTargetKind(forClasses: classes) else { return "" }
        return [
            #"\#(hitTargetKindAttributeName)="\#(escape(kind.rawValue))""#,
            #"\#(hitTargetActionAttributeName)="\#(escape(kind.action))""#,
            #"\#(hitTargetSourceAttributeName)="explicit""#
        ]
        .map { " " + $0 }
        .joined()
    }

    static func hitTargetAttributes(for className: String) -> String {
        hitTargetAttributes(classes: [className])
    }

    static func hitTargetAttributes(kind: WorkspaceHTMLHitTargetKind, classes: [String] = []) -> String {
        hitTargetAttributes(classes: classesWithDefaultHitTarget(classes, defaultKind: kind))
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
        hitTargetKind: WorkspaceHTMLHitTargetKind = .text,
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
            hitTargetKind: hitTargetKind,
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
        hitTargetKind: WorkspaceHTMLHitTargetKind = .text,
        classes: [String] = [],
        ariaLabel: String? = nil,
        title: String? = nil,
        role: String? = nil,
        disabled: Bool = false,
        attributes: [(String, String?)] = []
    ) -> String {
        button(
            label,
            testID: testID,
            hitTargetKind: hitTargetKind,
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
        hitTargetKind: WorkspaceHTMLHitTargetKind = .text,
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
            hitTargetKind: hitTargetKind,
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
        hitTargetKind: WorkspaceHTMLHitTargetKind = .row,
        classes: [String] = [],
        ariaLabel: String? = nil,
        title: String? = nil,
        attributes: [(String, String?)] = []
    ) -> String {
        """
        <summary\(elementAttributes(
            testID: testID,
            hitTargetKind: hitTargetKind,
            classes: classes,
            ariaLabel: ariaLabel,
            title: title,
            attributes: attributes
        ))>\(escape(label))</summary>
        """
    }

    private static func elementAttributes(
        testID: String?,
        hitTargetKind: WorkspaceHTMLHitTargetKind = .text,
        classes: [String] = [],
        ariaLabel: String? = nil,
        title: String? = nil,
        role: String? = nil,
        attributes: [(String, String?)] = []
    ) -> String {
        let parts = elementAttributeParts(
            testID: testID,
            hitTargetKind: hitTargetKind,
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
        hitTargetKind: WorkspaceHTMLHitTargetKind,
        classes: [String],
        ariaLabel: String?,
        title: String?,
        role: String? = nil,
        attributes: [(String, String?)]
    ) -> [String] {
        var parts: [String] = []
        let normalizedClasses = classesWithDefaultHitTarget(classes, defaultKind: hitTargetKind)
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

    private static func classesWithDefaultHitTarget(
        _ classes: [String],
        defaultKind: WorkspaceHTMLHitTargetKind = .text
    ) -> [String] {
        let trimmed = normalizedClasses(classes)
        if trimmed.contains(where: isHitTargetClass) {
            return trimmed
        }
        return trimmed + [defaultKind.className]
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
        if let hitTargetKind = hitTargetKind(forClasses: classes) {
            if !explicitAttributes.contains(where: { $0.0 == hitTargetKindAttributeName }) {
                parts.append(#"\#(hitTargetKindAttributeName)="\#(escape(hitTargetKind.rawValue))""#)
            }
            if !explicitAttributes.contains(where: { $0.0 == hitTargetActionAttributeName }) {
                parts.append(#"\#(hitTargetActionAttributeName)="\#(escape(hitTargetKind.action))""#)
            }
            if !explicitAttributes.contains(where: { $0.0 == hitTargetSourceAttributeName }) {
                parts.append(#"\#(hitTargetSourceAttributeName)="explicit""#)
            }
        }
        return parts
    }

    private static func isHitTargetClass(_ className: String) -> Bool {
        hitTargetKind(forClasses: [className]) != nil
    }

    private static func hitTargetKind(forClasses classes: [String]) -> WorkspaceHTMLHitTargetKind? {
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

    private static let hitTargetKindByClass: [(String, WorkspaceHTMLHitTargetKind)] = [
        (WorkspaceHTMLHitTargetKind.icon.className, .icon),
        (WorkspaceHTMLHitTargetKind.textEntry.className, .textEntry),
        (WorkspaceHTMLHitTargetKind.row.className, .row),
        (WorkspaceHTMLHitTargetKind.capsule.className, .capsule),
        (WorkspaceHTMLHitTargetKind.formAction.className, .formAction),
        (WorkspaceHTMLHitTargetKind.adjustable.className, .adjustable),
        (WorkspaceHTMLHitTargetKind.text.className, .text),
        (WorkspaceHTMLHitTargetKind.link.className, .link),
        (WorkspaceHTMLHitTargetKind.owned.className, .owned)
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
