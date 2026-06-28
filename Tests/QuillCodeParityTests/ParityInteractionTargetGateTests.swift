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
                && auditHelperText.contains("label")
                && auditHelperText.contains("textarea"),
            "The rendered click-target audit should cover native controls, ARIA controls, tabs, interactive labels, and text entry."
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
            auditHelperText.contains("targetSampleFractions = [0.2, 0.5, 0.8]")
                && auditHelperText.contains("targetInteriorSamplePoints"),
            "Click-target probes should sample a 3x3 interior grid so edge-blocked controls cannot pass with only the center clickable."
        )
        XCTAssertTrue(
            auditHelperText.contains("pointer_events_none")
                && auditHelperText.contains("isSemanticallyDisabled"),
            "Visible interactive controls with pointer-events disabled should fail unless they are semantically disabled."
        )
        XCTAssertTrue(
            auditHelperText.contains("closestInteractiveAncestor")
                && auditHelperText.contains("nestedIssues")
                && auditHelperText.contains("expectNoNestedInteractiveTargets"),
            "The rendered click-target audit should fail nested interactive controls, not only undersized controls."
        )
        XCTAssertTrue(
            auditHelperText.contains("isAuditableInteractiveElement")
                && auditHelperText.contains("HTMLLabelElement")
                && auditHelperText.contains("associatedLabelControl"),
            "Interactive labels should be audited when they act as checkbox/radio click targets without treating passive form captions as buttons."
        )
        XCTAssertTrue(
            auditHelperText.contains("dialog[open]")
                && auditHelperText.contains(#"[role="dialog"]"#),
            "The active-layer audit should cover generic dialogs in addition to QuillCode-specific popovers and panels."
        )
    }

    func testHTMLButtonPrimitiveDefaultsToSharedHitTargetClass() throws {
        let primitivesText = try Self.appSourceText(named: "WorkspaceHTMLPrimitives.swift")

        XCTAssertTrue(
            primitivesText.contains("classesWithDefaultHitTarget")
                && primitivesText.contains("return trimmed + [textHitTargetClass]"),
            "HTML button attributes should add the shared text hit-target class unless a more specific shared target class is already present."
        )
        XCTAssertTrue(
            primitivesText.contains("static func summary(")
                && primitivesText.contains("<summary\\(elementAttributes("),
            "HTML details summaries should route through the shared primitive so disclosure controls keep named hit targets."
        )
        XCTAssertTrue(
            primitivesText.contains("private static func isHitTargetClass")
                && primitivesText.contains("interactiveHitTargetClass")
                && primitivesText.contains("formActionHitTargetClass"),
            "The defaulting helper should recognize every shared rendered hit-target class instead of duplicating class-name logic at call sites."
        )
    }

    func testHTMLRenderersUseSharedClickTargetPrimitives() throws {
        let rendererFiles = try Self.swiftSourceFiles(in: "Sources/QuillCodeApp")
            .filter {
                $0.lastPathComponent.hasPrefix("WorkspaceHTML")
                    && $0.lastPathComponent != "WorkspaceHTMLPrimitives.swift"
            }
        let violations = try HTMLSourceInteractionTargetAudit(
            packageRoot: Self.packageRoot()
        )
        .violations(in: rendererFiles)

        XCTAssertTrue(
            violations.isEmpty,
            "Generated HTML controls must route through shared click-target primitives or shared hit-target classes:\n\(violations.joined(separator: "\n"))"
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
                && designText.contains("static func capsule(")
                && designText.contains("static func textEntry(")
                && designText.contains("static func segmentedControl(")
                && designText.contains("static func switchRow("),
            "Shared target specs should cover icon, row, form-action, capsule, text-entry, segmented, and switch controls instead of ad hoc sizing."
        )
        XCTAssertTrue(
            designText.contains("quillCodeTextEntryTarget")
                && designText.contains("quillCodeSegmentedControlTarget")
                && designText.contains("quillCodeSwitchRowTarget"),
            "Native text entry, segmented controls, and switches should have semantic hit-target helpers so call sites do not use raw frames."
        )
    }

    func testNativeSourceAuditCoversMenuAndPickerTriggers() throws {
        let file = try makeTemporarySwiftFile("""
        import SwiftUI

        struct BadClickTargets: View {
            @State private var text = ""
            @State private var selected = 0

            var body: some View {
                Menu {
                    Text("One")
                } label: {
                    Image(systemName: "ellipsis")
                }

                Picker("Mode", selection: $selected) {
                    Text("One").tag(1)
                }

                TextEditor(text: $text)
            }
        }
        """)

        let violations = try SwiftSourceInteractionTargetAudit(packageRoot: file.deletingLastPathComponent())
            .violations(in: [file])

        XCTAssertTrue(violations.contains { $0.contains("Menu trigger lacks shared hit target") })
        XCTAssertTrue(violations.contains { $0.contains("Menu trigger lacks explicit press or platform style") })
        XCTAssertTrue(violations.contains { $0.contains("Picker lacks shared hit target") })
        XCTAssertTrue(violations.contains { $0.contains("text-entry control lacks shared text-entry hit target") })
    }

    func testNativeSourceAuditAcceptsMenuPickerAndTextEditorContracts() throws {
        let file = try makeTemporarySwiftFile("""
        import SwiftUI

        struct GoodClickTargets: View {
            @State private var text = ""
            @State private var selected = 0

            var body: some View {
                Menu {
                    Text("One")
                } label: {
                    Image(systemName: "ellipsis")
                        .quillCodeIconButtonTarget()
                }
                .buttonStyle(QuillCodePressableButtonStyle())

                Picker("Mode", selection: $selected) {
                    Text("One").tag(1)
                }
                .pickerStyle(.segmented)
                .quillCodeSegmentedControlTarget()

                TextEditor(text: $text)
                    .quillCodeTextEntryTarget()
            }
        }
        """)

        let violations = try SwiftSourceInteractionTargetAudit(packageRoot: file.deletingLastPathComponent())
            .violations(in: [file])

        XCTAssertEqual(violations, [])
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

    private func makeTemporarySwiftFile(_ source: String) throws -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("quillcode-click-target-audit-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        let fileURL = directory.appendingPathComponent("Fixture.swift")
        try source.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }
}

private struct HTMLSourceInteractionTargetAudit {
    var packageRoot: URL

    private let primitiveMarkers = [
        "WorkspaceHTMLPrimitives.button(",
        "WorkspaceHTMLPrimitives.commandButton(",
        "WorkspaceHTMLPrimitives.buttonAttributes(",
        "WorkspaceHTMLPrimitives.summary("
    ]

    private let hitTargetMarkers = [
        "WorkspaceHTMLPrimitives.interactiveHitTargetClass",
        "WorkspaceHTMLPrimitives.iconHitTargetClass",
        "WorkspaceHTMLPrimitives.textHitTargetClass",
        "WorkspaceHTMLPrimitives.rowHitTargetClass",
        "WorkspaceHTMLPrimitives.capsuleHitTargetClass",
        "WorkspaceHTMLPrimitives.formActionHitTargetClass"
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
        return lines.enumerated().compactMap { index, line in
            guard containsHTMLInteractiveElement(line),
                  !lineHasSharedTargetContract(line)
            else { return nil }
            return "\(relativePath):\(index + 1) generated HTML control lacks shared hit-target primitive"
        }
    }

    private func containsHTMLInteractiveElement(_ line: String) -> Bool {
        line.contains("<button")
            || line.contains("<summary")
            || line.contains("<a ")
    }

    private func lineHasSharedTargetContract(_ line: String) -> Bool {
        primitiveMarkers.contains { line.contains($0) }
            || hitTargetMarkers.contains { line.contains($0) }
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
        "quillCodeTextEntryTarget",
        "quillCodeSegmentedControlTarget",
        "quillCodeSwitchRowTarget",
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

            if isButtonDeclaration(line),
               !isSystemMenuItemButton(lines: lines, index: index),
               !hasButtonStyle(in: window(in: lines, around: index, radius: 56)) {
                violations.append("\(relativePath):\(index + 1) Button lacks explicit press or platform style")
            }

            if isMenuDeclaration(line),
               !hasSharedTarget(in: window(in: lines, around: index, radius: 56)) {
                violations.append("\(relativePath):\(index + 1) Menu trigger lacks shared hit target")
            }

            if isMenuDeclaration(line),
               !hasButtonStyle(in: window(in: lines, around: index, radius: 56)) {
                violations.append("\(relativePath):\(index + 1) Menu trigger lacks explicit press or platform style")
            }

            if isPickerDeclaration(line),
               !hasSharedTarget(in: window(in: lines, around: index, radius: 28)) {
                violations.append("\(relativePath):\(index + 1) Picker lacks shared hit target")
            }

            if isLinkDeclaration(line),
               !hasSharedTarget(in: window(in: lines, around: index, radius: 28)) {
                violations.append("\(relativePath):\(index + 1) Link lacks shared hit target")
            }

            if isTextEntryDeclaration(line),
               !window(in: lines, around: index, radius: 22).contains("quillCodeTextEntryTarget") {
                violations.append("\(relativePath):\(index + 1) text-entry control lacks shared text-entry hit target")
            }

            if isToggleDeclaration(line),
               !window(in: lines, around: index, radius: 16).contains("quillCodeSwitchRowTarget") {
                violations.append("\(relativePath):\(index + 1) toggle control lacks shared switch-row hit target")
            }

            if line.contains(".pickerStyle(.segmented)"),
               !window(in: lines, around: index, radius: 8).contains("quillCodeSegmentedControlTarget") {
                violations.append("\(relativePath):\(index + 1) segmented picker lacks shared segmented hit target")
            }
        }

        return violations
    }

    private func hasSharedTarget(in sourceWindow: String) -> Bool {
        targetMarkers.contains { sourceWindow.contains($0) }
    }

    private func hasButtonStyle(in sourceWindow: String) -> Bool {
        sourceWindow.contains(".buttonStyle(")
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
