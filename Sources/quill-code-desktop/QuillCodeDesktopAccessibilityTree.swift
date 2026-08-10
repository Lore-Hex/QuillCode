import AppKit
import ApplicationServices
import Foundation

struct QuillCodeDesktopAccessibilityElementSnapshot {
    var element: AXUIElement
    var identifier: String
    var role: String
    var title: String
    var accessibilityLabel: String
    var help: String
    var value: String
    var isFocused: Bool
    var frame: CGRect?
    var ancestorIdentifiers: [String]

    var bestLabel: String {
        [title, accessibilityLabel, help, value]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty }) ?? ""
    }

    var frameArea: CGFloat {
        guard let frame else { return 0 }
        return frame.width * frame.height
    }

    var hasUsableHitTestIdentity: Bool {
        !identifier.isEmpty || !ancestorIdentifiers.isEmpty
    }
}

struct QuillCodeDesktopAccessibilityHitTestResult {
    var snapshot: QuillCodeDesktopAccessibilityElementSnapshot?
    var error: AXError

    var isAvailable: Bool {
        error == .success && snapshot?.hasUsableHitTestIdentity == true
    }

    var errorDescription: String {
        if error != .success {
            return String(describing: error)
        }
        guard let snapshot else {
            return "successWithoutElement"
        }
        return snapshot.hasUsableHitTestIdentity ? "" : "unidentifiedElement"
    }
}

struct QuillCodeDesktopAccessibilityElementIdentity: Hashable {
    let element: AXUIElement

    static func == (
        lhs: QuillCodeDesktopAccessibilityElementIdentity,
        rhs: QuillCodeDesktopAccessibilityElementIdentity
    ) -> Bool {
        CFEqual(lhs.element, rhs.element)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(CFHash(element))
    }
}

@MainActor
struct QuillCodeDesktopAccessibilityTree {
    var elements: [QuillCodeDesktopAccessibilityElementSnapshot]

    init(root: NSView) {
        _ = root
        var visited = Set<QuillCodeDesktopAccessibilityElementIdentity>()
        var collected: [QuillCodeDesktopAccessibilityElementSnapshot] = []
        let application = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
        Self.collect(from: application, into: &collected, visited: &visited)
        elements = collected
    }

    init(root: NSView, matchingIdentifiers identifiers: Set<String>) {
        _ = root
        guard !identifiers.isEmpty else {
            elements = []
            return
        }
        var visited = Set<QuillCodeDesktopAccessibilityElementIdentity>()
        var collected: [QuillCodeDesktopAccessibilityElementSnapshot] = []
        var matchedIdentifiers: Set<String> = []
        let application = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
        _ = Self.collect(
            from: application,
            matchingIdentifiers: identifiers,
            into: &collected,
            matchedIdentifiers: &matchedIdentifiers,
            visited: &visited
        )
        elements = collected
    }

    static func hitTest(at point: CGPoint) -> QuillCodeDesktopAccessibilityHitTestResult {
        let application = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
        var hitElement: AXUIElement?
        let result = AXUIElementCopyElementAtPosition(application, Float(point.x), Float(point.y), &hitElement)
        guard result == .success, let hitElement else {
            return QuillCodeDesktopAccessibilityHitTestResult(snapshot: nil, error: result)
        }
        return QuillCodeDesktopAccessibilityHitTestResult(
            snapshot: snapshot(
                for: hitElement,
                ancestorIdentifiers: ancestorIdentifiers(of: hitElement)
            ),
            error: result
        )
    }

    static func performPress(on snapshot: QuillCodeDesktopAccessibilityElementSnapshot) -> AXError {
        AXUIElementPerformAction(snapshot.element, kAXPressAction as CFString)
    }

    static func performSetValue(
        _ value: String,
        on snapshot: QuillCodeDesktopAccessibilityElementSnapshot
    ) -> AXError {
        AXUIElementSetAttributeValue(
            snapshot.element,
            kAXValueAttribute as CFString,
            value as CFTypeRef
        )
    }

    private static func collect(
        from element: AXUIElement,
        into collected: inout [QuillCodeDesktopAccessibilityElementSnapshot],
        visited: inout Set<QuillCodeDesktopAccessibilityElementIdentity>
    ) {
        guard visited.insert(.init(element: element)).inserted else { return }

        if let snapshot = snapshot(for: element),
           !snapshot.identifier.isEmpty || snapshot.role == kAXMenuItemRole as String
        {
            collected.append(snapshot)
        }

        for child in children(of: element) {
            collect(from: child, into: &collected, visited: &visited)
        }
    }

    private static func collect(
        from element: AXUIElement,
        matchingIdentifiers identifiers: Set<String>,
        into collected: inout [QuillCodeDesktopAccessibilityElementSnapshot],
        matchedIdentifiers: inout Set<String>,
        visited: inout Set<QuillCodeDesktopAccessibilityElementIdentity>
    ) -> Bool {
        guard visited.insert(.init(element: element)).inserted else { return false }

        let identifier = stringAttribute(kAXIdentifierAttribute, from: element)
        if identifiers.contains(identifier),
           let snapshot = snapshot(for: element, identifier: identifier),
           snapshot.frameArea > 0
        {
            collected.append(snapshot)
            matchedIdentifiers.insert(snapshot.identifier)
            if matchedIdentifiers == identifiers {
                return true
            }
        }

        for child in children(of: element) {
            if collect(
                from: child,
                matchingIdentifiers: identifiers,
                into: &collected,
                matchedIdentifiers: &matchedIdentifiers,
                visited: &visited
            ) {
                return true
            }
        }
        return false
    }

    private static func snapshot(
        for element: AXUIElement,
        identifier suppliedIdentifier: String? = nil,
        ancestorIdentifiers: [String] = []
    ) -> QuillCodeDesktopAccessibilityElementSnapshot? {
        let identifier = suppliedIdentifier ?? stringAttribute(kAXIdentifierAttribute, from: element)
        let role = stringAttribute(kAXRoleAttribute, from: element)
        let title = stringAttribute(kAXTitleAttribute, from: element)
        let description = stringAttribute(kAXDescriptionAttribute, from: element)
        let help = stringAttribute(kAXHelpAttribute, from: element)
        let value = stringAttribute(kAXValueAttribute, from: element)
        let isFocused = boolAttribute(kAXFocusedAttribute, from: element)
        let frame = frame(from: element)
        let isTitledMenuItem = role == kAXMenuItemRole as String && !title.isEmpty
        guard !identifier.isEmpty || frame != nil || isTitledMenuItem else { return nil }
        return QuillCodeDesktopAccessibilityElementSnapshot(
            element: element,
            identifier: identifier,
            role: role,
            title: title,
            accessibilityLabel: description,
            help: help,
            value: value,
            isFocused: isFocused,
            frame: frame,
            ancestorIdentifiers: ancestorIdentifiers
        )
    }

    private static func ancestorIdentifiers(of element: AXUIElement) -> [String] {
        var identifiers: [String] = []
        var visited = Set<QuillCodeDesktopAccessibilityElementIdentity>()
        var current: AXUIElement? = element
        while let parent = current.flatMap(parentElement) {
            guard visited.insert(.init(element: parent)).inserted else { break }
            let identifier = stringAttribute(kAXIdentifierAttribute, from: parent)
            if !identifier.isEmpty {
                identifiers.append(identifier)
            }
            current = parent
        }
        return identifiers
    }

    private static func parentElement(of element: AXUIElement) -> AXUIElement? {
        guard let value = axAttribute(kAXParentAttribute, from: element) else { return nil }
        let cfValue = value as CFTypeRef
        guard CFGetTypeID(cfValue) == AXUIElementGetTypeID() else { return nil }
        return unsafeDowncast(cfValue, to: AXUIElement.self)
    }

    private static func children(of element: AXUIElement) -> [AXUIElement] {
        var values: [AXUIElement] = []
        for attribute in [
            kAXMenuBarAttribute as String,
            kAXWindowsAttribute as String,
            kAXChildrenAttribute as String,
            "AXVisibleChildren",
            "AXContents"
        ] {
            guard let value = axAttribute(attribute, from: element) else { continue }
            if let children = value as? [AXUIElement] {
                values.append(contentsOf: children)
                continue
            }
            let cfValue = value as CFTypeRef
            if CFGetTypeID(cfValue) == AXUIElementGetTypeID() {
                values.append(unsafeDowncast(cfValue, to: AXUIElement.self))
            }
        }
        return values
    }

    private static func stringAttribute(_ attribute: String, from element: AXUIElement) -> String {
        guard let value = axAttribute(attribute, from: element) else { return "" }
        if let string = value as? String {
            return string
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        return ""
    }

    private static func boolAttribute(_ attribute: String, from element: AXUIElement) -> Bool {
        guard let value = axAttribute(attribute, from: element) else { return false }
        if let bool = value as? Bool {
            return bool
        }
        if let number = value as? NSNumber {
            return number.boolValue
        }
        return false
    }

    private static func frame(from element: AXUIElement) -> CGRect? {
        guard let position = pointAttribute(kAXPositionAttribute, from: element),
              let size = sizeAttribute(kAXSizeAttribute, from: element)
        else { return nil }
        let frame = CGRect(origin: position, size: size)
        guard frame.width > 0, frame.height > 0 else { return nil }
        return frame
    }

    private static func axAttribute(_ attribute: String, from element: AXUIElement) -> Any? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success else { return nil }
        return value
    }

    private static func pointAttribute(_ attribute: String, from element: AXUIElement) -> CGPoint? {
        guard let axValue = axValueAttribute(attribute, expectedType: .cgPoint, from: element) else { return nil }
        var point = CGPoint.zero
        guard AXValueGetValue(axValue, .cgPoint, &point) else { return nil }
        return point
    }

    private static func sizeAttribute(_ attribute: String, from element: AXUIElement) -> CGSize? {
        guard let axValue = axValueAttribute(attribute, expectedType: .cgSize, from: element) else { return nil }
        var size = CGSize.zero
        guard AXValueGetValue(axValue, .cgSize, &size) else { return nil }
        return size
    }

    private static func axValueAttribute(
        _ attribute: String,
        expectedType: AXValueType,
        from element: AXUIElement
    ) -> AXValue? {
        guard let value = axAttribute(attribute, from: element) else { return nil }
        let cfValue = value as CFTypeRef
        guard CFGetTypeID(cfValue) == AXValueGetTypeID() else { return nil }
        let axValue = unsafeDowncast(cfValue, to: AXValue.self)
        guard AXValueGetType(axValue) == expectedType else { return nil }
        return axValue
    }
}
