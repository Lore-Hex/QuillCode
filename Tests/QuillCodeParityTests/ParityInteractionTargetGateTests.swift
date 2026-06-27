import XCTest

final class ParityInteractionTargetGateTests: QuillCodeParityTestCase {
    func testNativeInteractionControlsUseSharedTargetContracts() throws {
        let appFiles = try Self.swiftSourceFiles(in: "Sources/QuillCodeApp")
        let visibleDesktopFiles = try Self.swiftSourceFiles(in: "Sources/quill-code-desktop")
            .filter { $0.lastPathComponent != "DesktopCommands.swift" }
        let violations = try SwiftSourceInteractionTargetAudit(
            packageRoot: Self.packageRoot()
        )
        .violations(in: appFiles + visibleDesktopFiles)

        XCTAssertTrue(
            violations.isEmpty,
            "Interactive controls must use shared click-target contracts:\n\(violations.joined(separator: "\n"))"
        )
    }

    func testHTMLInteractionAuditRequiresNamedClickableTargets() throws {
        let auditHelperText = try String(
            contentsOf: Self.packageRoot()
                .appendingPathComponent("E2E/playwright/tests/interaction-audit-helpers.ts"),
            encoding: .utf8
        )

        XCTAssertTrue(
            auditHelperText.contains("accessibleName(element)")
                && auditHelperText.contains("missing_accessible_name"),
            "The rendered click-target audit should fail visible interactive elements that have no user-facing name."
        )
        XCTAssertTrue(
            auditHelperText.contains("button")
                && auditHelperText.contains("[role=\"button\"]")
                && auditHelperText.contains("[role=\"tab\"]")
                && auditHelperText.contains("textarea"),
            "The rendered click-target audit should cover native controls, ARIA controls, tabs, and text entry."
        )
        XCTAssertTrue(
            auditHelperText.contains("MINIMUM_HIT_TARGET = 44")
                && auditHelperText.contains("expectHitTarget(locator: Locator"),
            "The rendered click-target audit should keep the same 44 px minimum for whole-screen audits and explicit critical-control probes."
        )
        XCTAssertTrue(
            auditHelperText.contains("target.evaluate")
                && auditHelperText.contains("elementFromPoint")
                && auditHelperText.contains("clickableInteriorIssues"),
            "Explicit critical-control probes should test the clickable interior, not only raw bounding-box dimensions."
        )
        XCTAssertTrue(
            auditHelperText.contains("closestInteractiveAncestor")
                && auditHelperText.contains("nestedIssues")
                && auditHelperText.contains("expectNoNestedInteractiveTargets"),
            "The rendered click-target audit should fail nested interactive controls, not only undersized controls."
        )
    }

    func testNativeHitTargetPrimitivesFrameAndShapeEveryTarget() throws {
        let designText = try Self.appSourceText(named: "QuillCodeDesignSystem.swift")

        XCTAssertTrue(
            designText.contains("static let minimumHitTarget: CGFloat = 44"),
            "Native controls should use the same 44 pt target baseline as the rendered harness."
        )
        XCTAssertTrue(
            designText.contains(".frame(\n            minWidth: spec.minWidth")
                && designText.contains("minHeight: spec.minHeight"),
            "Shared native targets should enforce minimum width and height inside the modifier, not rely on per-call padding."
        )
        XCTAssertTrue(
            designText.contains(".contentShape(Rectangle())")
                && designText.contains(".contentShape(RoundedRectangle")
                && designText.contains(".contentShape(Capsule())"),
            "Shared native targets should give each visible shape an explicit tappable content shape."
        )
        XCTAssertTrue(
            designText.contains("static func icon(")
                && designText.contains("static func fullRow(")
                && designText.contains("static func formAction(")
                && designText.contains("static func capsule("),
            "Shared target specs should cover icon, row, form-action, and capsule controls instead of ad hoc sizing."
        )
    }

    func testDesktopMenuBarPopoverUsesSharedFullRowTargets() throws {
        let menuBarText = try Self.desktopSourceText(named: "QuillCodeMenuBarView.swift")

        XCTAssertTrue(
            menuBarText.contains("menuActionButton("),
            "Menu bar popover actions should route through one shared full-row target helper."
        )
        XCTAssertTrue(
            menuBarText.contains(".buttonStyle(QuillCodePressableButtonStyle())")
                && menuBarText.contains(".quillCodeFullRowButtonTarget()"),
            "Menu bar popover buttons should keep 44 pt full-row click targets and press feedback."
        )
        XCTAssertFalse(
            menuBarText.contains(#"Button("Stop All", action: onStopAll)"#),
            "Menu bar popover actions should not regress to raw SwiftUI buttons."
        )
    }

}

private struct SwiftSourceInteractionTargetAudit {
    var packageRoot: URL

    private let targetMarkers = [
        "quillCodeTextButtonTarget",
        "quillCodeIconButtonTarget",
        "quillCodeFullRowButtonTarget",
        "quillCodeCapsuleButtonTarget",
        "quillCodeFormActionTarget",
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
            if isGestureClick(line) {
                violations.append("\(relativePath):\(index + 1) gesture-based click target should be a Button or Link")
            }

            if isCompactPlatformButtonStyle(line),
               !hasSharedTarget(in: window(in: lines, around: index, radius: 18)) {
                violations.append("\(relativePath):\(index + 1) compact platform button style lacks shared hit target")
            }

            if line.contains(".buttonStyle(QuillCodePressableButtonStyle())"),
               !hasSharedTarget(in: window(in: lines, around: index, radius: 28)) {
                violations.append("\(relativePath):\(index + 1) pressable button lacks explicit shared hit target")
            }

            if line.contains(".labelStyle(.iconOnly)"),
               !window(in: lines, around: index, radius: 10).contains("quillCodeIconButtonTarget") {
                violations.append("\(relativePath):\(index + 1) icon-only control lacks icon hit target")
            }

            if isButtonDeclaration(line),
               !isSystemMenuItemButton(lines: lines, index: index),
               !hasSharedTarget(in: window(in: lines, around: index, radius: 56)) {
                violations.append("\(relativePath):\(index + 1) Button lacks shared hit target")
            }

            if isLinkDeclaration(line),
               !hasSharedTarget(in: window(in: lines, around: index, radius: 28)) {
                violations.append("\(relativePath):\(index + 1) Link lacks shared hit target")
            }
        }

        return violations
    }

    private func hasSharedTarget(in sourceWindow: String) -> Bool {
        targetMarkers.contains { sourceWindow.contains($0) }
    }

    private func isButtonDeclaration(_ line: String) -> Bool {
        line.range(
            of: #"^\s*Button(?:\(|\s*\{)"#,
            options: .regularExpression
        ) != nil
    }

    private func isLinkDeclaration(_ line: String) -> Bool {
        line.range(
            of: #"^\s*Link(?:\(|\s*\{)"#,
            options: .regularExpression
        ) != nil
    }

    private func isGestureClick(_ line: String) -> Bool {
        line.contains(".onTapGesture") || line.contains(".gesture(")
    }

    private func isCompactPlatformButtonStyle(_ line: String) -> Bool {
        line.contains(".buttonStyle(.bordered")
            || line.contains(".buttonStyle(.borderedProminent")
            || line.contains(".buttonStyle(.borderless")
            || line.contains(".buttonStyle(.plain")
    }

    private func isSystemMenuItemButton(lines: [String], index: Int) -> Bool {
        let preceding = window(in: lines, from: max(0, index - 24), to: index)
        let following = window(in: lines, from: index, to: min(lines.count, index + 16))
        return preceding.contains("Menu {")
            && !following.contains("} label:")
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
