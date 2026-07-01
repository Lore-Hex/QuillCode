import Foundation

struct SwiftSourceInteractionTargetAudit {
    var packageRoot: URL

    private let targetMarkers = [
        "quillCodeTextButtonTarget",
        "quillCodeIconButtonTarget",
        "quillCodeFullRowButtonTarget",
        "quillCodeCapsuleButtonTarget",
        "quillCodeFormActionTarget",
        "quillCodeLinkTarget",
        "quillCodeTextEntryTarget",
        "quillCodeSegmentedControlTarget",
        "quillCodeAdjustableControlTarget",
        "quillCodeSwitchRowTarget",
        "quillCodeOwnedGestureTarget"
    ]

    private let genericTargetMarkers = [
        "quillCodeHitTarget",
        "quillCodeInteractiveTarget"
    ]

    func violations(in sourceFiles: [URL]) throws -> [String] {
        try sourceFiles.flatMap(violations(in:))
    }

    private func violations(in file: URL) throws -> [String] {
        let lines = try String(contentsOf: file, encoding: .utf8)
            .components(separatedBy: .newlines)
        let relativePath = file.path.replacingOccurrences(
            of: packageRoot.path + "/",
            with: ""
        )
        var violations: [String] = []

        for (index, line) in lines.enumerated() {
            let declarationScope = controlScope(in: lines, startingAt: index)
            let owningControlScope = controlScopeForModifier(in: lines, modifierIndex: index)

            if isGestureClick(line),
               !window(in: lines, around: index, radius: 10).contains("quillCodeOwnedGestureTarget") {
                violations.append("\(relativePath):\(index + 1) gesture-based click target should use Button, Link, or quillCodeOwnedGestureTarget")
            }

            if isRawMinimumHitTargetFrame(line),
               !isSharedHitTargetImplementation(relativePath) {
                violations.append("\(relativePath):\(index + 1) raw minimum hit-target frame should use semantic target or decorative helper")
            }

            if line.contains(".contentShape("),
               !isSharedHitTargetImplementation(relativePath) {
                violations.append("\(relativePath):\(index + 1) raw contentShape should live in the shared target helper")
            }

            if line.contains(".allowsHitTesting("),
               !isSharedHitTargetImplementation(relativePath) {
                violations.append("\(relativePath):\(index + 1) hit-testing override should not be used on app chrome")
            }

            if usesGenericTargetHelper(line),
               !isSharedHitTargetImplementation(relativePath) {
                violations.append("\(relativePath):\(index + 1) generic hit-target helper should use a semantic target helper")
            }

            if isCompactPlatformButtonStyle(line),
               !isSystemMenuItemButton(lines: lines, index: index) {
                violations.append("\(relativePath):\(index + 1) compact platform button style should use QuillCodePressableButtonStyle or QuillCodeActionButtonStyle")
            }

            if isRawNumericControlClusterSpacing(line),
               containsInteractiveControl(declarationScope),
               !isSharedHitTargetImplementation(relativePath) {
                violations.append("\(relativePath):\(index + 1) interactive control cluster spacing should use a named QuillCodeMetrics spacing token")
            }

            if isImplicitControlClusterSpacing(line, declarationScope: declarationScope),
               containsInteractiveControlCluster(declarationScope),
               !isSharedHitTargetImplementation(relativePath) {
                violations.append("\(relativePath):\(index + 1) interactive control cluster spacing should use a named QuillCodeMetrics spacing token")
            }

            if line.contains(".buttonStyle(QuillCodePressableButtonStyle())"),
               !hasSharedTarget(in: owningControlScope) {
                violations.append("\(relativePath):\(index + 1) pressable button lacks explicit shared hit target")
            }

            if line.contains(".labelStyle(.iconOnly)"),
               !window(in: lines, around: index, radius: 10).contains("quillCodeIconButtonTarget") {
                violations.append("\(relativePath):\(index + 1) icon-only control lacks icon hit target")
            }

            if line.contains("quillCodeIconButtonTarget"),
               !isSharedHitTargetImplementation(relativePath),
               !hasIconTargetName(in: iconTargetNameScope(
                    in: lines,
                    modifierIndex: index,
                    owningControlScope: owningControlScope
                )) {
                violations.append("\(relativePath):\(index + 1) icon hit target needs a visible label, accessibilityLabel, or help tooltip")
            }

            if isButtonDeclaration(line),
               !isSystemMenuItemButton(lines: lines, index: index),
               !hasSharedTarget(in: declarationScope) {
                violations.append("\(relativePath):\(index + 1) Button lacks shared hit target")
            }

            if isButtonDeclaration(line),
               !isSystemMenuItemButton(lines: lines, index: index),
               hasSharedTarget(in: declarationScope),
               !hasButtonCompatibleTarget(in: declarationScope) {
                violations.append("\(relativePath):\(index + 1) Button uses incompatible shared hit target")
            }

            if isButtonDeclaration(line),
               !isSystemMenuItemButton(lines: lines, index: index),
               !hasButtonStyle(in: declarationScope) {
                violations.append("\(relativePath):\(index + 1) Button lacks explicit press or platform style")
            }

            let menuTriggerScope = isMenuDeclaration(line)
                ? triggerScopeForMenu(in: lines, startingAt: index, declarationScope: declarationScope)
                : declarationScope
            if isMenuDeclaration(line),
               !hasSharedTarget(in: menuTriggerScope) {
                violations.append("\(relativePath):\(index + 1) Menu trigger lacks shared hit target")
            }

            if isMenuDeclaration(line),
               hasSharedTarget(in: menuTriggerScope),
               !hasMenuCompatibleTarget(in: menuTriggerScope) {
                violations.append("\(relativePath):\(index + 1) Menu trigger uses incompatible shared hit target")
            }

            if isMenuDeclaration(line),
               !hasButtonStyle(in: menuTriggerScope) {
                violations.append("\(relativePath):\(index + 1) Menu trigger lacks explicit press or platform style")
            }

            let disclosureTriggerScope = isDisclosureDeclaration(line)
                ? triggerScopeForDisclosure(in: lines, startingAt: index, declarationScope: declarationScope)
                : declarationScope
            if isDisclosureDeclaration(line),
               !hasSharedTarget(in: disclosureTriggerScope) {
                violations.append("\(relativePath):\(index + 1) DisclosureGroup trigger lacks shared hit target")
            }

            if isPickerDeclaration(line),
               !hasSharedTarget(in: declarationScope) {
                violations.append("\(relativePath):\(index + 1) Picker lacks shared hit target")
            }

            if isPickerDeclaration(line),
               hasSharedTarget(in: declarationScope),
               !hasPickerCompatibleTarget(in: declarationScope) {
                violations.append("\(relativePath):\(index + 1) Picker uses incompatible shared hit target")
            }

            if isLinkDeclaration(line),
               !hasSharedTarget(in: declarationScope) {
                violations.append("\(relativePath):\(index + 1) Link lacks shared hit target")
            }

            if isLinkDeclaration(line),
               !declarationScope.contains("quillCodeLinkTarget") {
                violations.append("\(relativePath):\(index + 1) Link should use quillCodeLinkTarget so external navigation is not styled as a button press")
            }

            if isTextEntryDeclaration(line),
               !declarationScope.contains("quillCodeTextEntryTarget") {
                violations.append("\(relativePath):\(index + 1) text-entry control lacks shared text-entry hit target")
            }

            if isToggleDeclaration(line),
               !declarationScope.contains("quillCodeSwitchRowTarget") {
                violations.append("\(relativePath):\(index + 1) toggle control lacks shared switch-row hit target")
            }

            if isAdjustableDeclaration(line),
               !declarationScope.contains("quillCodeAdjustableControlTarget") {
                violations.append("\(relativePath):\(index + 1) adjustable control lacks shared adjustable hit target")
            }

            if line.contains(".pickerStyle(.segmented)"),
               !declarationScope.contains("quillCodeSegmentedControlTarget") {
                violations.append("\(relativePath):\(index + 1) segmented picker lacks shared segmented hit target")
            }
        }

        return violations
    }

    private func hasSharedTarget(in sourceWindow: String) -> Bool {
        targetMarkers.contains { sourceWindow.contains($0) }
    }

    private func hasButtonCompatibleTarget(in sourceWindow: String) -> Bool {
        [
            "quillCodeTextButtonTarget",
            "quillCodeIconButtonTarget",
            "quillCodeFullRowButtonTarget",
            "quillCodeCapsuleButtonTarget",
            "quillCodeFormActionTarget"
        ].contains { sourceWindow.contains($0) }
    }

    private func hasMenuCompatibleTarget(in sourceWindow: String) -> Bool {
        [
            "quillCodeTextButtonTarget",
            "quillCodeIconButtonTarget",
            "quillCodeFullRowButtonTarget",
            "quillCodeCapsuleButtonTarget",
            "quillCodeFormActionTarget"
        ].contains { sourceWindow.contains($0) }
    }

    private func hasPickerCompatibleTarget(in sourceWindow: String) -> Bool {
        if sourceWindow.contains(".pickerStyle(.segmented)") {
            return sourceWindow.contains("quillCodeSegmentedControlTarget")
        }
        return [
            "quillCodeFullRowButtonTarget",
            "quillCodeTextButtonTarget",
            "quillCodeCapsuleButtonTarget",
            "quillCodeSegmentedControlTarget"
        ].contains { sourceWindow.contains($0) }
    }

    private func hasButtonStyle(in sourceWindow: String) -> Bool {
        sourceWindow.contains(".buttonStyle(")
    }

    private func hasIconTargetName(in sourceWindow: String) -> Bool {
        sourceWindow.contains("Label(")
            || sourceWindow.contains(".accessibilityLabel(")
            || sourceWindow.contains(".help(")
    }

    private func iconTargetNameScope(
        in lines: [String],
        modifierIndex index: Int,
        owningControlScope: String
    ) -> String {
        let lowerBound = max(0, index - 160)
        var lineIndex = index
        while lineIndex >= lowerBound {
            if isMenuDeclaration(lines[lineIndex]) {
                let range = controlRange(in: lines, startingAt: lineIndex)
                guard range.contains(index) else {
                    lineIndex -= 1
                    continue
                }
                let scopeLines = Array(lines[range])
                guard let labelOffset = scopeLines.firstIndex(where: { $0.contains("label:") }) else {
                    return owningControlScope
                }
                let labelStart = range.lowerBound + labelOffset
                if index >= labelStart {
                    return window(in: lines, from: labelStart, to: range.upperBound)
                }
                return owningControlScope
            }
            lineIndex -= 1
        }
        return owningControlScope
    }

    private func usesGenericTargetHelper(_ line: String) -> Bool {
        genericTargetMarkers.contains { line.contains($0) }
    }

    private func controlScope(in lines: [String], startingAt index: Int) -> String {
        let range = controlRange(in: lines, startingAt: index)
        return window(in: lines, from: range.lowerBound, to: range.upperBound)
    }

    private func controlRange(in lines: [String], startingAt index: Int) -> Range<Int> {
        let maxEnd = min(lines.count, index + 160)
        var end = index
        var depth = 0
        var sawOpener = false
        var lineIndex = index

        while lineIndex < maxEnd {
            let balance = delimiterBalance(in: lines[lineIndex])
            depth += balance.delta
            sawOpener = sawOpener || balance.sawOpener
            end = lineIndex

            if lineIndex > index,
               sawOpener,
               depth <= 0,
               !isChainedModifierLine(lines[safe: lineIndex + 1]) {
                break
            }

            lineIndex += 1
        }

        return index..<min(lines.count, end + 1)
    }

    private func controlScopeForModifier(in lines: [String], modifierIndex index: Int) -> String {
        guard isChainedModifierLine(lines[safe: index]) else {
            return controlScope(in: lines, startingAt: index)
        }
        let lowerBound = max(0, index - 160)
        var lineIndex = index
        while lineIndex >= lowerBound {
            let line = lines[lineIndex]
            if isControlDeclaration(line) {
                let range = controlRange(in: lines, startingAt: lineIndex)
                if range.contains(index) {
                    return window(in: lines, from: range.lowerBound, to: range.upperBound)
                }
            }
            if line.contains("var body: some View") || line.contains("var body:") {
                break
            }
            lineIndex -= 1
        }
        return controlScope(in: lines, startingAt: index)
    }

    private func triggerScopeForMenu(
        in lines: [String],
        startingAt index: Int,
        declarationScope: String
    ) -> String {
        let scopeLines = declarationScope.components(separatedBy: .newlines)
        guard let labelLine = scopeLines.firstIndex(where: { $0.contains("label:") }) else {
            return declarationScope
        }
        return scopeLines[labelLine...].joined(separator: "\n")
    }

    private func triggerScopeForDisclosure(
        in lines: [String],
        startingAt index: Int,
        declarationScope: String
    ) -> String {
        let scopeLines = declarationScope.components(separatedBy: .newlines)
        guard let labelLine = scopeLines.firstIndex(where: { $0.contains("label:") }) else {
            return lines[safe: index] ?? declarationScope
        }
        return scopeLines[labelLine...].joined(separator: "\n")
    }

    private func isChainedModifierLine(_ line: String?) -> Bool {
        guard let line else { return false }
        return line.range(
            of: #"^\s*\."#,
            options: .regularExpression
        ) != nil
    }

    private func delimiterBalance(in line: String) -> (delta: Int, sawOpener: Bool) {
        var delta = 0
        var sawOpener = false
        var isEscaped = false
        var isInsideString = false
        for character in line {
            if isInsideString {
                if isEscaped {
                    isEscaped = false
                } else if character == "\\" {
                    isEscaped = true
                } else if character == "\"" {
                    isInsideString = false
                }
                continue
            }

            if character == "\"" {
                isInsideString = true
                continue
            }

            switch character {
            case "(", "{", "[":
                delta += 1
                sawOpener = true
            case ")", "}", "]":
                delta -= 1
            default:
                continue
            }
        }
        return (delta, sawOpener)
    }

    private func isButtonDeclaration(_ line: String) -> Bool {
        line.range(
            of: #"^\s*Button(?:\(|\s*\{)"#,
            options: .regularExpression
        ) != nil
    }

    private func isMenuDeclaration(_ line: String) -> Bool {
        line.range(
            of: #"^\s*Menu(?:\(|\s*\{)"#,
            options: .regularExpression
        ) != nil
    }

    private func isPickerDeclaration(_ line: String) -> Bool {
        line.range(
            of: #"^\s*Picker(?:\(|\s*\{)"#,
            options: .regularExpression
        ) != nil
    }

    private func isLinkDeclaration(_ line: String) -> Bool {
        line.range(
            of: #"^\s*Link(?:\(|\s*\{)"#,
            options: .regularExpression
        ) != nil
    }

    private func isDisclosureDeclaration(_ line: String) -> Bool {
        line.range(
            of: #"^\s*DisclosureGroup(?:\(|\s*\{)"#,
            options: .regularExpression
        ) != nil
    }

    private func isTextEntryDeclaration(_ line: String) -> Bool {
        line.range(
            of: #"^\s*(TextField|SecureField|TextEditor)\("#,
            options: .regularExpression
        ) != nil
    }

    private func isToggleDeclaration(_ line: String) -> Bool {
        line.range(
            of: #"^\s*Toggle\("#,
            options: .regularExpression
        ) != nil
    }

    private func isAdjustableDeclaration(_ line: String) -> Bool {
        line.range(
            of: #"^\s*(Slider|Stepper|DatePicker|ColorPicker)\("#,
            options: .regularExpression
        ) != nil
    }

    private func isControlDeclaration(_ line: String) -> Bool {
        isButtonDeclaration(line)
            || isMenuDeclaration(line)
            || isPickerDeclaration(line)
            || isLinkDeclaration(line)
            || isDisclosureDeclaration(line)
            || isTextEntryDeclaration(line)
            || isToggleDeclaration(line)
            || isAdjustableDeclaration(line)
    }

    private func isGestureClick(_ line: String) -> Bool {
        line.contains(".onTapGesture")
            || line.contains(".onLongPressGesture")
            || line.contains(".gesture(")
            || line.contains(".simultaneousGesture(")
            || line.contains(".highPriorityGesture(")
            || line.contains("TapGesture(")
            || line.contains("LongPressGesture(")
    }

    private func isCompactPlatformButtonStyle(_ line: String) -> Bool {
        line.contains(".buttonStyle(.bordered")
            || line.contains(".buttonStyle(.borderedProminent")
            || line.contains(".buttonStyle(.borderless")
            || line.contains(".buttonStyle(.plain")
    }

    private func isRawNumericControlClusterSpacing(_ line: String) -> Bool {
        line.range(
            of: #"(HStack|LazyHGrid|LazyVGrid)\([^\n]*spacing:\s*[0-9]+(?:\.[0-9]+)?(?=[,\)\]])"#,
            options: .regularExpression
        ) != nil
            || line.range(
                of: #"GridItem\([^\n]*spacing:\s*[0-9]+(?:\.[0-9]+)?(?=[,\)\]])"#,
                options: .regularExpression
            ) != nil
    }

    private func isImplicitControlClusterSpacing(_ line: String, declarationScope: String) -> Bool {
        guard line.range(
            of: #"^\s*(HStack|LazyHGrid|LazyVGrid)(?:\s*\{|\()"#,
            options: .regularExpression
        ) != nil else {
            return false
        }
        return !declarationScope.contains("spacing:")
    }

    private func containsInteractiveControl(_ sourceWindow: String) -> Bool {
        [
            "Button(",
            "Button {",
            "Menu(",
            "Menu {",
            "Picker(",
            "DisclosureGroup(",
            "DisclosureGroup {",
            "Toggle(",
            "Link(",
            "TextField(",
            "SecureField(",
            "TextEditor(",
            "QuillCodeReviewActionButton("
        ].contains { sourceWindow.contains($0) }
    }

    private func containsInteractiveControlCluster(_ sourceWindow: String) -> Bool {
        interactiveControlOccurrences(in: sourceWindow) >= 2
    }

    private func interactiveControlOccurrences(in sourceWindow: String) -> Int {
        [
            "Button(",
            "Button {",
            "Menu(",
            "Menu {",
            "Picker(",
            "DisclosureGroup(",
            "DisclosureGroup {",
            "Toggle(",
            "Link(",
            "TextField(",
            "SecureField(",
            "TextEditor(",
            "QuillCodeReviewActionButton("
        ].reduce(0) { partialResult, marker in
            partialResult + sourceWindow.components(separatedBy: marker).count - 1
        }
    }

    private func isRawMinimumHitTargetFrame(_ line: String) -> Bool {
        line.contains(".frame(width: QuillCodeMetrics.minimumHitTarget, height: QuillCodeMetrics.minimumHitTarget)")
    }

    private func isSharedHitTargetImplementation(_ relativePath: String) -> Bool {
        [
            "Sources/QuillCodeApp/QuillCodeDesignSystem.swift",
            "Sources/QuillCodeApp/QuillCodeHitTargetSpec.swift",
            "Sources/QuillCodeApp/QuillCodeButtonHitTargetViewModifiers.swift",
            "Sources/QuillCodeApp/QuillCodeControlHitTargetViewModifiers.swift",
            "Sources/QuillCodeApp/QuillCodeHitTargetViewModifiers.swift"
        ].contains(relativePath)
    }

    private func isSystemMenuItemButton(lines: [String], index: Int) -> Bool {
        let lowerBound = max(0, index - 160)
        var lineIndex = index
        while lineIndex >= lowerBound {
            if isMenuDeclaration(lines[lineIndex]) {
                let range = controlRange(in: lines, startingAt: lineIndex)
                guard range.contains(index) else {
                    lineIndex -= 1
                    continue
                }
                let scopeLines = Array(lines[range])
                guard let labelOffset = scopeLines.firstIndex(where: { $0.contains("label:") }) else {
                    return true
                }
                return index < range.lowerBound + labelOffset
            }
            if lineIndex < index, isControlDeclaration(lines[lineIndex]) {
                let range = controlRange(in: lines, startingAt: lineIndex)
                if range.contains(index) {
                    return false
                }
            }
            lineIndex -= 1
        }
        return false
    }

    private func window(in lines: [String], around index: Int, radius: Int) -> String {
        let lowerBound = max(0, index - radius)
        let upperBound = min(lines.count, index + radius + 1)
        return lines[lowerBound..<upperBound].joined(separator: "\n")
    }

    private func window(in lines: [String], from lowerBound: Int, to upperBound: Int) -> String {
        guard lowerBound < upperBound else { return "" }
        return lines[lowerBound..<upperBound].joined(separator: "\n")
    }
}

extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
