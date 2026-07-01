import XCTest

final class ParityNativeInteractionContractGateTests: QuillCodeParityTestCase {
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


    func testNativeHitTargetPrimitivesFrameAndShapeEveryTarget() throws {
        let designText = [
            try Self.appSourceText(named: "QuillCodeDesignSystem.swift"),
            try Self.appSourceText(named: "QuillCodeHitTargetSpec.swift"),
            try Self.appSourceText(named: "QuillCodeButtonHitTargetViewModifiers.swift"),
            try Self.appSourceText(named: "QuillCodeControlHitTargetViewModifiers.swift"),
            try Self.appSourceText(named: "QuillCodeHitTargetViewModifiers.swift")
        ].joined(separator: "\n")

        XCTAssertTrue(
            designText.contains("static let minimumHitTarget: CGFloat = 44"),
            "Native controls should use the same 44 pt target baseline as the rendered harness."
        )
        XCTAssertTrue(
            designText.contains("var kind: QuillCodeNativeHitTargetKind")
                && designText.contains("var action: String")
                && designText.contains("var allowsNestedInteractiveChildren: Bool")
                && designText.contains("var requiresUnblockedInterior: Bool")
                && designText.contains("var requiresTactileFeedback: Bool")
                && designText.contains("var allowsTextSelection: Bool"),
            "Native hit-target specs should reuse the audited native semantic vocabulary so controls cannot pass with only generic geometry or a parallel enum."
        )
        XCTAssertTrue(
            designText.contains("minWidth: requiredMinWidth")
                && designText.contains("minHeight: requiredMinHeight")
                && designText.contains("max(spec.requiredMinWidth, QuillCodeMetrics.minimumHitTarget)")
                && designText.contains("max(spec.requiredMinHeight, QuillCodeMetrics.minimumHitTarget)")
                && designText.contains("spec.width.map { max($0, QuillCodeMetrics.minimumHitTarget) }")
                && designText.contains("spec.height.map { max($0, QuillCodeMetrics.minimumHitTarget) }"),
            "Shared native targets should clamp minimum and fixed dimensions inside the modifier, not rely on per-call padding."
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
                && designText.contains("static func adjustableControl(")
                && designText.contains("static func link(")
                && designText.contains("static func switchRow(")
                && designText.contains("static func ownedGesture("),
            "Shared target specs should cover icon, row, form-action, capsule, link, text-entry, segmented, adjustable, switch, and owned gesture controls instead of ad hoc sizing."
        )
        XCTAssertTrue(
            designText.contains("quillCodeTextEntryTarget")
                && designText.contains("quillCodeSegmentedControlTarget")
                && designText.contains("quillCodeAdjustableControlTarget")
                && designText.contains("quillCodeLinkTarget")
                && designText.contains("quillCodeSwitchRowTarget")
                && designText.contains("quillCodeOwnedGestureTarget")
                && designText.contains("quillCodeDecorativeIconFrame"),
            "Native text entry, segmented controls, adjustable controls, links, switches, owned gesture regions, and decorative icon frames should have semantic helpers so call sites do not use raw frames."
        )
        XCTAssertTrue(
            designText.contains(".accessibilityAddTraits(.isButton)"),
            "Owned gesture targets should opt into button semantics so custom gestures remain discoverable and auditable."
        )
        XCTAssertFalse(
            designText.contains("public func quillCodeHitTarget("),
            "The app should not expose a generic hit-target helper; visible controls need icon/text/row/capsule/form/text-entry intent."
        )
        XCTAssertTrue(
            designText.contains("public struct QuillCodeActionButtonStyle: ButtonStyle")
                && designText.contains("public enum Tone")
                && designText.contains("case primary")
                && designText.contains("case destructive")
                && designText.contains("minWidth: CGFloat = QuillCodeMetrics.compactTextButtonMinWidth")
                && designText.contains(".contentShape(RoundedRectangle"),
            "Native action buttons should use one shared tone-aware style that owns the visible surface, 44 pt minimum, press feedback, and tappable shape."
        )
        XCTAssertTrue(
            designText.contains("static let controlClusterSpacing: CGFloat = 10")
                && designText.contains("static let denseControlClusterSpacing: CGFloat = 8"),
            "Dense control groups should use named spacing metrics that still clear adjacent 44 pt hit targets instead of overlap-prone magic numbers."
        )
    }

    func testInteractiveContainersPreserveChildTargets() throws {
        let topBarText = try Self.appSourceText(named: "QuillCodeTopBarView.swift")
        let toolCardText = try Self.appSourceText(named: "QuillCodeToolCardView.swift")
        let composerText = try Self.appSourceText(named: "QuillCodeComposerView.swift")
        let sidebarText = try Self.appSourceText(named: "QuillCodeSidebarView.swift")
        let modelRowsText = try Self.appSourceText(named: "QuillCodeModelPickerRows.swift")

        XCTAssertTrue(
            topBarText.contains(".accessibilityElement(children: .contain)")
                && !topBarText.contains(".accessibilityElement(children: .combine)"),
            "Top bar chrome contains buttons and menus, so it must preserve child targets instead of combining them into one accessibility element."
        )
        XCTAssertTrue(
            toolCardText.contains(".accessibilityElement(children: .contain)")
                && !toolCardText.contains(".accessibilityElement(children: .combine)"),
            "Tool cards contain actions and disclosure controls, so they must preserve child click targets instead of combining the whole card."
        )
        XCTAssertTrue(
            topBarText.contains("HStack(spacing: QuillCodeMetrics.controlClusterSpacing)")
                && composerText.contains("HStack(spacing: QuillCodeMetrics.controlClusterSpacing)")
                && sidebarText.contains("HStack(spacing: QuillCodeMetrics.controlClusterSpacing)")
                && modelRowsText.contains("HStack(spacing: QuillCodeMetrics.denseControlClusterSpacing)"),
            "High-risk adjacent controls should use named hit-target spacing metrics, not local magic numbers."
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


    func testNativeHitTargetAuditIsPartOfDesktopSmokeContract() throws {
        let nativeModelText = try Self.appSourceText(named: "QuillCodeNativeHitTargetModels.swift")
        let auditText = [
            try Self.appSourceText(named: "QuillCodeNativeHitTargetAudit.swift"),
            nativeModelText,
            try Self.appSourceText(named: "QuillCodeNativeHitTargetContract.swift"),
            try Self.appSourceText(named: "QuillCodeNativeHitTargetProbe.swift"),
            try Self.appSourceText(named: "QuillCodeNativeHitTargetAuditReport.swift"),
            try Self.appSourceText(named: "QuillCodeNativeHitTargetCatalog.swift"),
            try Self.appSourceText(named: "QuillCodeNativeHitTargetCanonicalContracts.swift"),
            try Self.appSourceText(named: "QuillCodeNativeHitTargetCommandContracts.swift"),
            try Self.appSourceText(named: "QuillCodeNativeHitTargetContractFactory.swift"),
            try Self.appSourceText(named: "QuillCodeNativeHitTargetDesignContracts.swift"),
            try Self.appSourceText(named: "QuillCodeNativeHitTargetPaneContracts.swift"),
            try Self.appSourceText(named: "QuillCodeNativeSurfaceTargetPolicy.swift"),
            try Self.appSourceText(named: "QuillCodeNativeHitTargetPolicyCatalog.swift")
        ].joined(separator: "\n")
        let smokeSupportText = try Self.desktopSourceText(named: "QuillCodeDesktopSmokeSupport.swift")
        let smokeRunnerText = try Self.desktopSourceText(named: "QuillCodeDesktopSmokeRunner.swift")
        let smokeScriptText = try String(
            contentsOf: Self.packageRoot().appendingPathComponent("scripts/native-desktop-smoke.sh"),
            encoding: .utf8
        )
        let clickProbeValidatorText = try Self.nativeClickProbeValidatorText()

        XCTAssertTrue(
            auditText.contains("public enum QuillCodeNativeHitTargetKind")
                && auditText.contains("case icon")
                && auditText.contains("case textButton")
                && auditText.contains("case formAction")
                && auditText.contains("case textEntry")
                && auditText.contains("case segmentedControl")
                && auditText.contains("case adjustableControl")
                && auditText.contains("case switchRow")
                && auditText.contains("case ownedGesture")
                && auditText.contains("case fullRow")
                && auditText.contains("case capsule"),
            "Native hit-target audit should expose every semantic target kind instead of only a generic minimum-size check."
        )
        XCTAssertFalse(
            nativeModelText.contains("public struct QuillCodeNativeHitTargetContract")
                || nativeModelText.contains("public struct QuillCodeNativeSurfaceTargetPolicy")
                || nativeModelText.contains("public struct QuillCodeNativeHitTargetProbe")
                || nativeModelText.contains("public struct QuillCodeNativeHitTargetAuditReport"),
            "The native hit-target taxonomy file should stay focused; contracts, surface policy, probes, and audit reports belong in focused model-boundary files."
        )
        XCTAssertTrue(
            auditText.contains("public enum QuillCodeNativeHitTargetAction")
                && auditText.contains("case press")
                && auditText.contains("case textInput = \"text-input\"")
                && auditText.contains("case adjust")
                && auditText.contains("case ownedGesture = \"owned-gesture\"")
                && auditText.contains("public var action: QuillCodeNativeHitTargetAction")
                && auditText.contains("public var allowsNestedInteractiveChildren: Bool")
                && auditText.contains("public var requiresUnblockedInterior: Bool")
                && auditText.contains("public var requiresTactileFeedback: Bool")
                && auditText.contains("public var allowsTextSelection: Bool"),
            "Native hit-target audit should report activation semantics, tactile policy, text-selection policy, and interior ownership, not only size and kind."
        )
        XCTAssertTrue(
            auditText.contains("public enum QuillCodeNativeFocusTarget")
                && auditText.contains("case composerMessage = \"composer.message\"")
                && auditText.contains("case searchChats = \"search.chats\"")
                && auditText.contains("case commandPaletteSearch = \"command-palette.search\"")
                && auditText.contains("case modelPickerSearch = \"model-picker.search\"")
                && auditText.contains("case terminalCommand = \"terminal.command\"")
                && auditText.contains("case browserAddress = \"browser.address\"")
                && auditText.contains("focusTarget: QuillCodeNativeFocusTarget?")
                && auditText.contains("missingRequiredFocusTargets"),
            "Native text-entry targets should have named focus contracts so search, command palette, terminal, browser, and composer typing regressions fail product smoke."
        )
        XCTAssertTrue(
            auditText.contains("public var testID: String?")
                && auditText.contains("public var commandID: String?")
                && auditText.contains(#"value["testID"] = testID"#)
                && auditText.contains(#"value["commandID"] = commandID"#)
                && auditText.contains("does not declare a stable test id, command id, or focus target")
                && auditText.contains("commandID: command.id"),
            "Native hit-target contracts should be addressable by a stable test id, routed command id, or focus target so smoke automation can click the same targets users see."
        )
        XCTAssertTrue(
            auditText.contains("public enum QuillCodeInteractionSurfaceFamily")
                && auditText.contains("case sidebarThreadList")
                && auditText.contains("case commandPalette")
                && auditText.contains("case modelPicker")
                && auditText.contains("case contextBanner")
                && auditText.contains("case menuBar")
                && auditText.contains("requiredSurfaceFamilies")
                && auditText.contains("missingSurfaceFamilies"),
            "Native hit-target audit should inventory whole interaction surface families, not only individual button kinds."
        )
        XCTAssertTrue(
            auditText.contains("public struct QuillCodeNativeSurfaceTargetPolicy")
                && auditText.contains("requiredSurfacePolicies")
                && auditText.contains("missingRequiredSurfaceKinds")
                && auditText.contains("requiredActions: [QuillCodeNativeHitTargetAction]")
                && auditText.contains("requiredFocusTargets: [QuillCodeNativeFocusTarget]")
                && auditText.contains("missingRequiredSurfaceActions")
                && auditText.contains("missingRequiredSurfaceFocusTargets")
                && auditText.contains(".composer")
                && auditText.contains("kinds: [.textEntry, .icon, .capsule]")
                && auditText.contains("focusTargets: [.composerMessage]")
                && auditText.contains(".browser")
                && auditText.contains("kinds: [.textEntry, .textButton, .icon]")
                && auditText.contains("focusTargets: [.browserAddress, .browserComment]")
                && auditText.contains(".review")
                && auditText.contains("kinds: [.textEntry, .segmentedControl, .fullRow, .formAction]")
                && auditText.contains("focusTargets: [.reviewBody, .reviewThreadReply]"),
            "Native hit-target audit should define the expected kind, action, and focus mix per surface family, not just prove that each family has one example control."
        )
        XCTAssertTrue(
            auditText.contains("duplicateContractIDs")
                && auditText.contains("duplicateIDs(in:")
                && auditText.contains("has an empty accessible label")
                && auditText.contains("icon target should declare an explicit minimum width"),
            "Native hit-target audit should fail blank labels/sources and duplicate target IDs so release evidence is debuggable."
        )
        XCTAssertTrue(
            auditText.contains("requiredCommandIDs")
                && auditText.contains(#""toggle-extensions""#)
                && auditText.contains(#""toggle-memories""#)
                && auditText.contains(#""toggle-automations""#)
                && auditText.contains("conditionalPaneContracts(for surface: WorkspaceSurface)"),
            "Native hit-target audit should cover command surfaces and visible secondary panes."
        )
        XCTAssertTrue(
            auditText.contains("canonicalTransientSurfaceContracts")
                && auditText.contains(#""command-palette.input""#)
                && auditText.contains(#""search.result""#)
                && auditText.contains(#""settings.action""#)
                && auditText.contains(#""model-picker.option-action""#)
                && auditText.contains(#""menu-bar.action""#),
            "Transient surfaces should have canonical native target contracts even when they are not visible in the current workspace snapshot."
        )
        XCTAssertTrue(
            smokeSupportText.contains("nativeHitTargets: QuillCodeNativeHitTargetAuditReport")
                && smokeSupportText.contains(#""nativeHitTargets": nativeHitTargets.dictionary"#),
            "The desktop smoke JSON should include the native hit-target audit report."
        )
        XCTAssertTrue(
            auditText.contains("public struct QuillCodeNativeHitTargetProbe")
                && auditText.contains("public enum QuillCodeNativeHitTargetProbeSelectorKind")
                && auditText.contains("clickProbes: [QuillCodeNativeHitTargetProbe]")
                && auditText.contains(#""clickProbes": clickProbes.map(\.dictionary)"#)
                && auditText.contains("public var allowsNestedInteractiveChildren: Bool")
                && auditText.contains("public var requiresUnblockedInterior: Bool")
                && auditText.contains("public var requiresTactileFeedback: Bool")
                && auditText.contains("public var allowsTextSelection: Bool")
                && auditText.contains("public var collisionScope: String")
                && auditText.contains(#""allowsNestedInteractiveChildren": allowsNestedInteractiveChildren"#)
                && auditText.contains(#""requiresUnblockedInterior": requiresUnblockedInterior"#)
                && auditText.contains(#""requiresTactileFeedback": requiresTactileFeedback"#)
                && auditText.contains(#""allowsTextSelection": allowsTextSelection"#)
                && auditText.contains(#""collisionScope": collisionScope"#)
                && auditText.contains("missingClickProbeContractIDs")
                && auditText.contains("clickProbeValidationIssues")
                && auditText.contains("validateClickProbes")
                && auditText.contains("click probe nested-child policy does not match contract")
                && auditText.contains("click probe interior-blocking policy does not match contract")
                && auditText.contains("click probe tactile-feedback policy does not match contract")
                && auditText.contains("click probe text-selection policy does not match contract")
                && auditText.contains("click probe collision scope does not match contract")
                && auditText.contains("expectedClickSamplePointsByName")
                && auditText.contains("has unexpected coordinates")
                && auditText.contains("normalizedClickSamplePoints")
                && auditText.contains(#"QuillCodeNativeHitTargetProbePoint(name: "center", x: 0.5, y: 0.5)"#),
            "Native hit-target audit should emit a click-probe plan with selectors, required dimensions, and normalized interior sample points for every addressable target."
        )
        XCTAssertTrue(
            smokeSupportText.contains("enum QuillCodeDesktopNativeHitTargetSmoke")
                && smokeSupportText.contains("QuillCodeNativeHitTargetAudit.report(for: surface)")
                && smokeSupportText.contains("nativeHitTargets.isValid")
                && smokeSupportText.contains("missingRequiredFocusTargets")
                && smokeSupportText.contains("clickProbeValidationIssues")
                && smokeSupportText.contains("nativeHitTargetAuditFailed")
                && smokeRunnerText.contains("QuillCodeDesktopNativeHitTargetSmoke.validatedReport(for: surface)"),
            "The product executable smoke should fail closed through the shared native hit-target validator when contracts are invalid."
        )
        XCTAssertTrue(
            smokeScriptText.contains(#""nativeHitTargets""#)
                && smokeScriptText.contains("json.load")
                && smokeScriptText.contains(#"native_targets.get("isValid") is not True"#)
                && smokeScriptText.contains(#"native_targets.get("minimumHitTarget") != 44"#)
                && smokeScriptText.contains("math.isclose(press_scale, 0.96")
                && smokeScriptText.contains("duplicateContractIDs")
                && smokeScriptText.contains("missingRequiredSurfaceKinds")
                && smokeScriptText.contains("missingRequiredSurfaceActions")
                && smokeScriptText.contains("missingRequiredSurfaceFocusTargets")
                && smokeScriptText.contains("surfacePolicies")
                && smokeScriptText.contains("expected_policy_actions")
                && smokeScriptText.contains("expected_policy_focus_targets")
                && smokeScriptText.contains("surface_test_ids")
                && smokeScriptText.contains("required_test_ids")
                && smokeScriptText.contains("required_command_contract_ids")
                && smokeScriptText.contains(#"for boolean_field in ("allowsNestedInteractiveChildren", "requiresUnblockedInterior", "requiresTactileFeedback", "allowsTextSelection")"#)
                && smokeScriptText.contains("malformed {boolean_field}")
                && smokeScriptText.contains("scripts/native-click-probe-contracts.py")
                && smokeScriptText.contains("validate \"$REPORT_PATH\"")
                && smokeScriptText.contains(#""collisionScope""#)
                && smokeScriptText.contains(#""browser": {"textEntry", "textButton", "icon"}"#)
                && smokeScriptText.contains(#"for field in ("id", "label", "source", "surface", "collisionScope")"#)
                && smokeScriptText.contains(#"for optional_field in ("testID", "commandID")"#)
                && smokeScriptText.contains("unaddressable native hit target")
                && smokeScriptText.contains(#""icon", "textButton", "formAction", "link", "textEntry", "segmentedControl", "adjustableControl", "switchRow", "ownedGesture", "fullRow", "capsule""#),
            "The release smoke wrapper should parse the native hit-target report as JSON and validate every metric, semantic kind/action/focus policy, unique ID, addressable test/command/focus handle, and non-empty metadata field while delegating click probes to the shared validator."
        )
        XCTAssertTrue(
            clickProbeValidatorText.contains("EXPECTED_SAMPLE_POINTS")
                && clickProbeValidatorText.contains(#""leading-edge": (0.08, 0.5)"#)
                && clickProbeValidatorText.contains(#""leading-interior": (0.18, 0.5)"#)
                && clickProbeValidatorText.contains(#""trailing-edge": (0.92, 0.5)"#)
                && clickProbeValidatorText.contains(#""trailing-interior": (0.82, 0.5)"#)
                && clickProbeValidatorText.contains(#""top-edge": (0.5, 0.08)"#)
                && clickProbeValidatorText.contains(#""bottom-edge": (0.5, 0.92)"#)
                && clickProbeValidatorText.contains("unexpected click probe point coordinates")
                && clickProbeValidatorText.contains("missingClickProbeContractIDs")
                && clickProbeValidatorText.contains("clickProbeValidationIssues")
                && clickProbeValidatorText.contains("expected_selector(contract, selector_kind)")
                && clickProbeValidatorText.contains("selector_kind == \"test-id\"")
                && clickProbeValidatorText.contains("selector_kind == \"command-id\"")
                && clickProbeValidatorText.contains("selector_kind == \"focus-target\"")
                && clickProbeValidatorText.contains("allowsNestedInteractiveChildren")
                && clickProbeValidatorText.contains("requiresUnblockedInterior")
                && clickProbeValidatorText.contains("requiresTactileFeedback")
                && clickProbeValidatorText.contains("allowsTextSelection")
                && clickProbeValidatorText.contains("requiredPeerClearance")
                && clickProbeValidatorText.contains("MINIMUM_TARGET_CLEARANCE = 8")
                && clickProbeValidatorText.contains("collisionScope")
                && clickProbeValidatorText.contains("nested-child policy drift")
                && clickProbeValidatorText.contains("interior-blocking policy drift")
                && clickProbeValidatorText.contains("tactile-feedback policy drift")
                && clickProbeValidatorText.contains("text-selection policy drift")
                && clickProbeValidatorText.contains("collision-scope drift")
                && clickProbeValidatorText.contains("clickProbePolicies")
                && clickProbeValidatorText.contains("Accessibility frame samples have ambiguous spacing")
                && clickProbeValidatorText.contains("allows_tight_accessibility_clearance")
                && clickProbeValidatorText.contains("write_comparison_manifest")
                && clickProbeValidatorText.contains("launchServicesMatchesDirect")
                && clickProbeValidatorText.contains("driftingContracts"),
            "The shared native click-probe validator should own exact probe coordinates, selector precedence, typed audit issue checks, and packaged launch-path comparison."
        )
        XCTAssertTrue(
            smokeScriptText.contains("required_focus_targets")
                && smokeScriptText.contains(#""composer.message""#)
                && smokeScriptText.contains(#""search.chats""#)
                && smokeScriptText.contains(#""command-palette.search""#)
                && smokeScriptText.contains(#""model-picker.search""#)
                && smokeScriptText.contains(#""terminal.command""#)
                && smokeScriptText.contains(#""browser.address""#),
            "The release smoke wrapper should validate named native focus targets, not only generic text-entry kind coverage."
        )
        XCTAssertTrue(
            smokeScriptText.contains(#""command-palette""#)
                && smokeScriptText.contains(#""model-picker""#)
                && smokeScriptText.contains(#""context-banner""#)
                && smokeScriptText.contains(#""menu-bar""#),
            "The release smoke wrapper should validate that all named interaction surface families remain covered."
        )
    }

    func testNativePrimaryClickTargetsExposeStableAccessibilityIdentifiers() throws {
        let composerText = try Self.appSourceText(named: "QuillCodeComposerView.swift")
        let modelPickerText = try Self.appSourceText(named: "QuillCodeModelPickerView.swift")
        let topBarText = [
            try Self.appSourceText(named: "QuillCodeModePickerButton.swift"),
            try Self.appSourceText(named: "QuillCodeTopBarActionClusterView.swift")
        ].joined(separator: "\n")
        let sidebarText = try Self.appSourceText(named: "QuillCodeSidebarView.swift")
        let terminalText = try Self.appSourceText(named: "QuillCodeTerminalPaneView.swift")
        let browserText = try Self.appSourceText(named: "QuillCodeBrowserPaneView.swift")
        let browserControlsText = try Self.appSourceText(named: "QuillCodeBrowserPaneControls.swift")
        let automationCreateMenuText = try Self.appSourceText(named: "QuillCodeAutomationCreateMenu.swift")

        XCTAssertTrue(
            composerText.contains(#".accessibilityIdentifier("quillcode-composer-input")"#)
                && composerText.contains(#".accessibilityIdentifier("quillcode-send-button")"#),
            "Composer text entry and send action should expose stable native accessibility IDs."
        )
        XCTAssertTrue(
            modelPickerText.contains(#".accessibilityIdentifier("quillcode-model-picker-button")"#)
                && modelPickerText.contains(#".accessibilityIdentifier("quillcode-model-picker-search")"#)
                && topBarText.contains(#".accessibilityIdentifier("quillcode-mode-picker-button")"#)
                && topBarText.contains(#".accessibilityIdentifier("quillcode-top-bar-overflow")"#),
            "Model, mode, and top-bar overflow controls should expose stable native accessibility IDs."
        )
        XCTAssertTrue(
            sidebarText.contains(#".accessibilityIdentifier("quillcode-sidebar-tools-button")"#)
                && sidebarText.contains(#".accessibilityIdentifier("quillcode-sidebar-command-\(command.id)")"#)
                && sidebarText.contains(#".accessibilityIdentifier("quillcode-sidebar-command-\(settingsCommand.id)")"#),
            "Sidebar commands and bottom tools/settings controls should expose stable native accessibility IDs."
        )
        XCTAssertTrue(
            terminalText.contains(#".accessibilityIdentifier("quillcode-terminal-command")"#)
                && terminalText.contains(#".accessibilityIdentifier("quillcode-terminal-action")"#)
                && browserControlsText.contains(#".accessibilityIdentifier("quillcode-browser-address")"#)
                && browserControlsText.contains(#".accessibilityIdentifier("quillcode-browser-action")"#)
                && browserText.contains(#".accessibilityIdentifier("quillcode-browser-add-comment")"#),
            "Terminal and browser input/action controls should expose stable native accessibility IDs."
        )
        XCTAssertTrue(
            automationCreateMenuText.contains(#".accessibilityIdentifier("quillcode-automation-create")"#),
            "Automation create menu trigger should expose a stable native accessibility ID."
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
