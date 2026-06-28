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
                && auditHelperText.contains("range")
                && auditHelperText.contains("textarea"),
            "The rendered click-target audit should cover native controls, ARIA controls, tabs, interactive labels, and text entry."
        )
        XCTAssertTrue(
            auditHelperText.contains("MINIMUM_HIT_TARGET = 44")
                && auditHelperText.contains("expectHitTarget(locator: Locator"),
            "The rendered click-target audit should keep the same 44 px minimum for whole-screen audits and explicit critical-control probes."
        )
        XCTAssertTrue(
            auditHelperText.contains("export type CriticalTargetProbe")
                && auditHelperText.contains("expectedKind?: string")
                && auditHelperText.contains("expectCriticalTargetRegistry"),
            "High-risk click targets should be declared through a named registry with expected semantic target kinds instead of scattered one-off assertions."
        )
        XCTAssertTrue(
            auditHelperText.contains("target.evaluate")
                && auditHelperText.contains("elementFromPoint")
                && auditHelperText.contains("clickableInteriorIssues"),
            "Explicit critical-control probes should test the clickable interior, not only raw bounding-box dimensions."
        )
        XCTAssertTrue(
            auditHelperText.contains("TARGET_INTERIOR_SAMPLE_FRACTIONS = [0.2, 0.5, 0.8]")
                && auditHelperText.contains("TARGET_EDGE_SAMPLE_FRACTIONS = [0.08, 0.92]")
                && auditHelperText.contains("targetInteriorSamplePoints"),
            "Click-target probes should sample near-edge and interior points so controls cannot pass with only the center or middle band clickable."
        )
        XCTAssertTrue(
            auditHelperText.contains("pointer_events_none")
                && auditHelperText.contains("isSemanticallyDisabled"),
            "Visible interactive controls with pointer-events disabled should fail unless they are semantically disabled."
        )
        XCTAssertTrue(
            auditHelperText.contains("missing_click_affordance")
                && auditHelperText.contains("requiresPointerAffordance"),
            "Visible clickable controls should expose a pointer affordance, not only a large invisible hit box."
        )
        XCTAssertTrue(
            auditHelperText.contains("missing_shared_hit_target_contract")
                && auditHelperText.contains("SHARED_HIT_TARGET_CLASSES")
                && auditHelperText.contains("EXPECTED_KIND_BY_CLASS")
                && auditHelperText.contains("'hit-target-adjustable': 'adjustable'"),
            "Visible interactive controls should declare ownership through a shared hit-target class and semantic kind, not only rely on global geometry."
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
                && primitivesText.contains("defaultKind: WorkspaceHTMLHitTargetKind = .text")
                && primitivesText.contains("return trimmed + [defaultKind.className]"),
            "HTML button attributes should add the default semantic hit-target kind unless a more specific shared target class is already present."
        )
        XCTAssertTrue(
            primitivesText.contains("enum WorkspaceHTMLHitTargetKind")
                && primitivesText.contains("case icon")
                && primitivesText.contains("case textEntry = \"text-entry\"")
                && primitivesText.contains("case formAction = \"form-action\"")
                && primitivesText.contains("case adjustable = \"adjustable\"")
                && primitivesText.contains("var className: String"),
            "Rendered controls should declare hit-target intent through a typed semantic kind instead of passing target CSS classes as the primary API."
        )
        XCTAssertTrue(
            primitivesText.contains(#"static let hitTargetKindAttributeName = "data-hit-target-kind""#)
                && primitivesText.contains("static func hitTargetKindAttribute(forClasses classes: [String])")
                && primitivesText.contains("static func hitTargetAttributes(kind: WorkspaceHTMLHitTargetKind")
                && primitivesText.contains("static func hitTargetAttributes(classes: [String])")
                && primitivesText.contains("hitTargetKindByClass")
                && primitivesText.contains(##"parts.append(#"\#(hitTargetKindAttributeName)="\#(escape(hitTargetKind))""#)"##),
            "HTML primitives should emit an explicit semantic hit-target kind so rendered controls can be audited by contract, not only by geometry."
        )
        XCTAssertTrue(
            primitivesText.contains("static func summary(")
                && primitivesText.contains("<summary\\(elementAttributes("),
            "HTML details summaries should route through the shared primitive so disclosure controls keep named hit targets."
        )
        XCTAssertTrue(
            primitivesText.contains("private static func isHitTargetClass")
                && primitivesText.contains("ownedHitTargetClass")
                && primitivesText.contains("interactiveHitTargetClass")
                && primitivesText.contains("textEntryHitTargetClass")
                && primitivesText.contains("formActionHitTargetClass"),
            "The defaulting helper should recognize every shared rendered hit-target class instead of duplicating class-name logic at call sites."
        )
        XCTAssertTrue(
            primitivesText.contains("adjustableHitTargetClass")
                && primitivesText.contains("hit-target-adjustable"),
            "Rendered adjustable controls such as range inputs should have their own semantic hit-target class instead of falling through to generic ownership."
        )
    }

    func testHarnessAuditsVisibleCommandTargetsForRouting() throws {
        let harnessText = try String(
            contentsOf: Self.packageRoot()
                .appendingPathComponent("E2E/harness/index.html"),
            encoding: .utf8
        )
        let interactionSpecText = try String(
            contentsOf: Self.packageRoot()
                .appendingPathComponent("E2E/playwright/tests/interaction-audit.spec.ts"),
            encoding: .utf8
        )

        XCTAssertTrue(
            harnessText.contains("const harnessStaticCommandIDs = new Set")
                && harnessText.contains("const harnessRoutableCommandPrefixes = ["),
            "The harness should keep an explicit command routing registry for rendered command targets."
        )
        XCTAssertTrue(
            harnessText.contains("function canRouteHarnessCommand(commandID)")
                && harnessText.contains("function commandRoutingAuditReport()")
                && harnessText.contains("unroutableCommands")
                && harnessText.contains("unroutableTargets"),
            "The harness should expose a reusable audit report for command IDs that would silently no-op."
        )
        XCTAssertTrue(
            harnessText.contains("window.__quillCodeCommandRoutingAudit = commandRoutingAuditReport"),
            "Playwright should be able to call the command routing audit after every rendered state."
        )
        XCTAssertTrue(
            harnessText.contains("if (!canRouteHarnessCommand(commandID))")
                && harnessText.contains("state.lastUnroutableCommandID"),
            "The harness command dispatcher should reject unknown command IDs instead of silently rerendering."
        )
        XCTAssertTrue(
            interactionSpecText.contains("expectCommandTargetsRoutable(page, label)")
                && interactionSpecText.contains("command routing audit catches visible dead command targets"),
            "The broad interaction audit should include command routing, with a regression proving dead command targets fail."
        )
    }

    func testRenderedCriticalTargetRegistryCoversPrimarySurfaces() throws {
        let interactionSpecText = try String(
            contentsOf: Self.packageRoot()
                .appendingPathComponent("E2E/playwright/tests/interaction-audit.spec.ts"),
            encoding: .utf8
        )

        for requiredSurface in [
            "primary workspace chrome",
            "top-bar overflow menu",
            "model picker",
            "command palette",
            "settings panel",
            "terminal pane",
            "browser pane",
            "extensions pane",
            "memories pane",
            "automations pane",
            "transcript tool card"
        ] {
            XCTAssertTrue(
                interactionSpecText.contains(requiredSurface),
                "The critical click-target registry should cover \(requiredSurface)."
            )
        }

        XCTAssertTrue(
            interactionSpecText.contains("model-detail-button")
                && interactionSpecText.contains("model-favorite-button")
                && interactionSpecText.contains("settings-sign-in")
                && interactionSpecText.contains("browser-comment-input")
                && interactionSpecText.contains("extension-mcp-resource-action")
                && interactionSpecText.contains("memory-delete")
                && interactionSpecText.contains("automation-primary-action")
                && interactionSpecText.contains("tool-card-details"),
            "The registry should include small/high-risk controls that commonly regress: model row actions, settings auth, browser inputs, and tool disclosures."
        )
        XCTAssertTrue(
            interactionSpecText.contains("secondary pane controls respond from the full interior click target")
                && interactionSpecText.contains("terminal run trailing interior")
                && interactionSpecText.contains("browser new tab leading interior")
                && interactionSpecText.contains("extension start trailing interior")
                && interactionSpecText.contains("memory edit leading interior")
                && interactionSpecText.contains("automation run leading interior"),
            "Secondary pane controls should be edge-clicked in Playwright so non-central hit-area regressions fail before release."
        )
        XCTAssertTrue(
            interactionSpecText.contains("audits narrow viewport click targets across squeezed states")
                && interactionSpecText.contains("width: 320"),
            "Click-target coverage should include a narrow squeezed viewport, not only standard desktop and phone widths."
        )
        XCTAssertTrue(
            interactionSpecText.contains("expectedKind: 'icon'")
                && interactionSpecText.contains("expectedKind: 'text-entry'")
                && interactionSpecText.contains("expectedKind: 'row'")
                && interactionSpecText.contains("expectedKind: 'text'"),
            "Critical click-target probes should assert the intended semantic target kind, not only any shared class."
        )
        XCTAssertTrue(
            interactionSpecText.contains("expectedKind: 'form-action'")
                || interactionSpecText.contains("expectedKind: 'capsule'"),
            "Critical click-target probes should include compact form-action or capsule controls, not only generic row/text/icon controls."
        )
    }

    func testFindBarUsesResponsiveTargetPreservingLayout() throws {
        let findText = try Self.appSourceText(named: "QuillCodeTranscriptFindView.swift")
        let harnessText = try String(
            contentsOf: Self.packageRoot()
                .appendingPathComponent("E2E/harness/index.html"),
            encoding: .utf8
        )

        XCTAssertTrue(
            findText.contains("ViewThatFits(in: .horizontal)")
                && findText.contains("compactLayout")
                && findText.contains("quillCodeTextEntryTarget()"),
            "Native transcript find should switch to a compact layout before the search field can shrink below its text-entry target."
        )
        XCTAssertTrue(
            harnessText.contains(".find-bar input,\n      .find-status")
                && harnessText.contains("grid-column: 1 / -1"),
            "Rendered transcript find should wrap input/status rows on compact widths instead of squeezing the input target."
        )
    }

    func testHarnessNormalizesDynamicClickTargetContracts() throws {
        let harnessText = try String(
            contentsOf: Self.packageRoot()
                .appendingPathComponent("E2E/harness/index.html"),
            encoding: .utf8
        )

        XCTAssertTrue(
            harnessText.contains("function normalizeInteractionTargetContracts")
                && harnessText.contains("sharedHitTargetClasses")
                && harnessText.contains("function fallbackHitTargetContract")
                && harnessText.contains("function existingHitTargetKind")
                && harnessText.contains("element.dataset.hitTargetKind = `auto-${kind}`"),
            "The dynamic HTML harness should attach explicit semantic hit-target contracts after every render instead of relying on global button/input CSS."
        )
        XCTAssertTrue(
            harnessText.contains("['hit-target-icon', 'icon']")
                && harnessText.contains("['hit-target-text-entry', 'text-entry']")
                && harnessText.contains("['hit-target-row', 'row']")
                && harnessText.contains("['hit-target-capsule', 'capsule']")
                && harnessText.contains("['hit-target-adjustable', 'adjustable']")
                && harnessText.contains("['hit-target-text', 'text']"),
            "Dynamic fallback targets should classify controls as icon, text-entry, row, capsule, adjustable, or text before using generic ownership."
        )
        XCTAssertTrue(
            harnessText.contains("normalizeInteractionTargetContracts(document.getElementById('app'))"),
            "The dynamic hit-target normalizer should run immediately after rendering before audits and click handlers observe the DOM."
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

    func testHTMLSourceAuditRequiresSemanticKindForRawSharedTargets() throws {
        let file = try makeTemporarySwiftFile(##"""
        enum BadHTMLRenderer {
            func render() -> String {
                #"<input class="\#(WorkspaceHTMLPrimitives.textEntryHitTargetClass)" aria-label="Search">"#
            }
        }
        """##)

        let violations = try HTMLSourceInteractionTargetAudit(packageRoot: file.deletingLastPathComponent())
            .violations(in: [file])

        XCTAssertTrue(
            violations.contains { $0.contains("shared hit-target class without semantic data-hit-target-kind") },
            "Raw generated HTML that directly uses a shared target class should also declare the semantic hit-target kind."
        )
    }

    func testHTMLSourceAuditAcceptsRawSharedTargetsWithSemanticKind() throws {
        let file = try makeTemporarySwiftFile(##"""
        enum GoodHTMLRenderer {
            func render() -> String {
                #"<input\#(WorkspaceHTMLPrimitives.hitTargetAttributes(kind: .textEntry)) aria-label="Search">"#
            }
        }
        """##)

        let violations = try HTMLSourceInteractionTargetAudit(packageRoot: file.deletingLastPathComponent())
            .violations(in: [file])

        XCTAssertEqual(violations, [])
    }

    func testNativeHitTargetPrimitivesFrameAndShapeEveryTarget() throws {
        let designText = try Self.appSourceText(named: "QuillCodeDesignSystem.swift")

        XCTAssertTrue(
            designText.contains("static let minimumHitTarget: CGFloat = 44"),
            "Native controls should use the same 44 pt target baseline as the rendered harness."
        )
        XCTAssertTrue(
            designText.contains("enum Kind")
                && designText.contains("var kind: Kind"),
            "Native hit-target specs should carry an explicit semantic intent so controls cannot pass with only generic geometry."
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
                && designText.contains("static func adjustableControl(")
                && designText.contains("static func switchRow(")
                && designText.contains("static func ownedGesture("),
            "Shared target specs should cover icon, row, form-action, capsule, text-entry, segmented, adjustable, switch, and owned gesture controls instead of ad hoc sizing."
        )
        XCTAssertTrue(
            designText.contains("quillCodeTextEntryTarget")
                && designText.contains("quillCodeSegmentedControlTarget")
                && designText.contains("quillCodeAdjustableControlTarget")
                && designText.contains("quillCodeSwitchRowTarget")
                && designText.contains("quillCodeOwnedGestureTarget")
                && designText.contains("quillCodeDecorativeIconFrame"),
            "Native text entry, segmented controls, adjustable controls, switches, owned gesture regions, and decorative icon frames should have semantic helpers so call sites do not use raw frames."
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
            designText.contains("static let controlClusterSpacing: CGFloat = 8")
                && designText.contains("static let denseControlClusterSpacing: CGFloat = 6"),
            "Dense control groups should use named spacing metrics so adjacent 44 pt hit targets do not drift into overlap-prone magic numbers."
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

    func testNativeSourceAuditCoversAdjustableControls() throws {
        let file = try makeTemporarySwiftFile("""
        import SwiftUI

        struct BadAdjustableTargets: View {
            @State private var value = 0.5

            var body: some View {
                VStack {
                    Slider(value: $value)
                    Stepper("Amount", value: $value)
                }
            }
        }
        """)

        let violations = try SwiftSourceInteractionTargetAudit(packageRoot: file.deletingLastPathComponent())
            .violations(in: [file])

        XCTAssertEqual(
            violations.filter { $0.contains("adjustable control lacks shared adjustable hit target") }.count,
            2,
            "Sliders and steppers should not pass the native source audit without a semantic adjustable-control target."
        )
    }

    func testNativeSourceAuditAcceptsAdjustableControlContracts() throws {
        let file = try makeTemporarySwiftFile("""
        import SwiftUI

        struct GoodAdjustableTargets: View {
            @State private var value = 0.5

            var body: some View {
                VStack {
                    Slider(value: $value)
                        .quillCodeAdjustableControlTarget()

                    Stepper("Amount", value: $value)
                        .quillCodeAdjustableControlTarget()
                }
            }
        }
        """)

        let violations = try SwiftSourceInteractionTargetAudit(packageRoot: file.deletingLastPathComponent())
            .violations(in: [file])

        XCTAssertEqual(violations, [])
    }

    func testNativeSourceAuditRejectsActionButtonStyleWithoutSemanticTarget() throws {
        let file = try makeTemporarySwiftFile("""
        import SwiftUI

        struct StyledButAmbiguousAction: View {
            var body: some View {
                Button("Save") {}
                    .buttonStyle(QuillCodeActionButtonStyle(.primary))
            }
        }
        """)

        let violations = try SwiftSourceInteractionTargetAudit(packageRoot: file.deletingLastPathComponent())
            .violations(in: [file])

        XCTAssertTrue(
            violations.contains { $0.contains("Button lacks shared hit target") },
            "Action button styling should not satisfy semantic click-target ownership by itself."
        )
    }

    func testNativeHitTargetAuditIsPartOfDesktopSmokeContract() throws {
        let auditText = try Self.appSourceText(named: "QuillCodeNativeHitTargetAudit.swift")
        let smokeSupportText = try Self.desktopSourceText(named: "QuillCodeDesktopSmokeSupport.swift")
        let smokeRunnerText = try Self.desktopSourceText(named: "QuillCodeDesktopSmokeRunner.swift")
        let smokeScriptText = try String(
            contentsOf: Self.packageRoot().appendingPathComponent("scripts/native-desktop-smoke.sh"),
            encoding: .utf8
        )

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
        XCTAssertTrue(
            auditText.contains("requiredCommandIDs")
                && auditText.contains(#""toggle-extensions""#)
                && auditText.contains(#""toggle-memories""#)
                && auditText.contains(#""toggle-automations""#)
                && auditText.contains("conditionalPaneContracts(for surface: WorkspaceSurface)"),
            "Native hit-target audit should cover command surfaces and visible secondary panes."
        )
        XCTAssertTrue(
            smokeSupportText.contains("nativeHitTargets: QuillCodeNativeHitTargetAuditReport")
                && smokeSupportText.contains(#""nativeHitTargets": nativeHitTargets.dictionary"#),
            "The desktop smoke JSON should include the native hit-target audit report."
        )
        XCTAssertTrue(
            smokeRunnerText.contains("QuillCodeNativeHitTargetAudit.report(for: surface)")
                && smokeRunnerText.contains("nativeHitTargets.isValid")
                && smokeRunnerText.contains("nativeHitTargetAuditFailed"),
            "The product executable smoke should fail closed when native hit-target contracts are invalid."
        )
        XCTAssertTrue(
            smokeScriptText.contains(#""nativeHitTargets""#)
                && smokeScriptText.contains("json.load")
                && smokeScriptText.contains(#"native_targets.get("isValid") is not True"#)
                && smokeScriptText.contains(#"native_targets.get("minimumHitTarget") != 44"#)
                && smokeScriptText.contains("math.isclose(press_scale, 0.96")
                && smokeScriptText.contains(#""icon", "textButton", "formAction", "textEntry", "segmentedControl", "adjustableControl", "switchRow", "ownedGesture", "fullRow", "capsule""#),
            "The release smoke wrapper should parse the native hit-target report as JSON and validate every metric and semantic kind."
        )
    }

    func testNativeSourceAuditRejectsAmbiguousMinimumHitTargetFrames() throws {
        let file = try makeTemporarySwiftFile("""
        import SwiftUI

        struct AmbiguousChrome: View {
            var body: some View {
                Image(systemName: "info")
                    .frame(width: QuillCodeMetrics.minimumHitTarget, height: QuillCodeMetrics.minimumHitTarget)
            }
        }
        """)

        let violations = try SwiftSourceInteractionTargetAudit(packageRoot: file.deletingLastPathComponent())
            .violations(in: [file])

        XCTAssertTrue(
            violations.contains { $0.contains("raw minimum hit-target frame should use semantic target or decorative helper") },
            "Raw 44 pt frames hide whether a view is clickable or decorative."
        )
    }

    func testNativeSourceAuditRejectsGenericHitTargetHelpers() throws {
        let file = try makeTemporarySwiftFile("""
        import SwiftUI

        struct GenericChrome: View {
            var body: some View {
                VStack {
                    Button("Generic") {}
                        .quillCodeHitTarget()
                        .buttonStyle(QuillCodePressableButtonStyle())

                    Button("Primitive") {}
                        .quillCodeInteractiveTarget(.icon())
                        .buttonStyle(QuillCodePressableButtonStyle())
                }
            }
        }
        """)

        let violations = try SwiftSourceInteractionTargetAudit(packageRoot: file.deletingLastPathComponent())
            .violations(in: [file])

        XCTAssertEqual(
            violations.filter { $0.contains("generic hit-target helper should use a semantic target helper") }.count,
            2,
            "Generic target helpers should not satisfy visible app controls; choose icon, text, row, capsule, form, switch, segmented, adjustable, or text-entry intent."
        )
        XCTAssertTrue(violations.contains { $0.contains("Button lacks shared hit target") })
    }

    func testNativeSourceAuditRejectsRawShapeAndHitTestingOverrides() throws {
        let file = try makeTemporarySwiftFile("""
        import SwiftUI

        struct RawTargetChrome: View {
            var body: some View {
                Button("Raw") {}
                    .contentShape(Rectangle())
                    .allowsHitTesting(false)
                    .quillCodeTextButtonTarget()
                    .buttonStyle(QuillCodePressableButtonStyle())
            }
        }
        """)

        let violations = try SwiftSourceInteractionTargetAudit(packageRoot: file.deletingLastPathComponent())
            .violations(in: [file])

        XCTAssertTrue(
            violations.contains { $0.contains("raw contentShape should live in the shared target helper") },
            "Raw content shapes let controls invent local hit regions instead of using the design-system contract."
        )
        XCTAssertTrue(
            violations.contains { $0.contains("hit-testing override should not be used on app chrome") },
            "Hit-testing overrides can create visible dead targets and should fail source review."
        )
    }

    func testNativeSourceAuditAllowsNamedOwnedGestureTargets() throws {
        let file = try makeTemporarySwiftFile("""
        import SwiftUI

        struct OwnedGestureChrome: View {
            var body: some View {
                HStack {
                    Text("Open")
                    Image(systemName: "chevron.right")
                }
                .quillCodeOwnedGestureTarget()
                .accessibilityLabel("Open detail")
                .onTapGesture {}
            }
        }
        """)

        let violations = try SwiftSourceInteractionTargetAudit(packageRoot: file.deletingLastPathComponent())
            .violations(in: [file])

        XCTAssertEqual(violations, [])
    }

    func testNativeSourceAuditRejectsUnnamedGestureTargets() throws {
        let file = try makeTemporarySwiftFile("""
        import SwiftUI

        struct RawGestureChrome: View {
            var body: some View {
                Text("Open")
                    .onTapGesture {}
                Text("Press")
                    .onLongPressGesture {}
                Text("Priority")
                    .highPriorityGesture(TapGesture())
            }
        }
        """)

        let violations = try SwiftSourceInteractionTargetAudit(packageRoot: file.deletingLastPathComponent())
            .violations(in: [file])

        XCTAssertGreaterThanOrEqual(
            violations.filter { $0.contains("gesture-based click target should use Button, Link, or quillCodeOwnedGestureTarget") }.count,
            3
        )
    }

    func testNativeSourceAuditAcceptsDecorativeIconFrames() throws {
        let file = try makeTemporarySwiftFile("""
        import SwiftUI

        struct DecorativeChrome: View {
            var body: some View {
                Image(systemName: "info")
                    .quillCodeDecorativeIconFrame()
            }
        }
        """)

        let violations = try SwiftSourceInteractionTargetAudit(packageRoot: file.deletingLastPathComponent())
            .violations(in: [file])

        XCTAssertEqual(violations, [])
    }

    func testNativeSourceAuditDoesNotLetNearbyTargetsSatisfyAnotherControl() throws {
        let file = try makeTemporarySwiftFile("""
        import SwiftUI

        struct MixedClickTargets: View {
            @State private var text = ""

            var body: some View {
                VStack {
                    Button("Ready") {}
                        .quillCodeTextButtonTarget()
                        .buttonStyle(QuillCodePressableButtonStyle())

                    Button("Broken") {}

                    Menu {
                        Button("Nested") {}
                            .quillCodeTextButtonTarget()
                            .buttonStyle(QuillCodePressableButtonStyle())
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .buttonStyle(QuillCodePressableButtonStyle())
                }
            }
        }
        """)

        let violations = try SwiftSourceInteractionTargetAudit(packageRoot: file.deletingLastPathComponent())
            .violations(in: [file])

        XCTAssertTrue(violations.contains { $0.contains("Button lacks shared hit target") })
        XCTAssertTrue(violations.contains { $0.contains("Button lacks explicit press or platform style") })
        XCTAssertTrue(violations.contains { $0.contains("Menu trigger lacks shared hit target") })
        XCTAssertFalse(
            violations.contains { $0.contains("Ready") },
            "A fully styled neighboring button should not be blamed while testing scope extraction."
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
        "WorkspaceHTMLPrimitives.hitTargetAttributes(kind:",
        "WorkspaceHTMLPrimitives.summary("
    ]

    private let hitTargetMarkers = [
        "WorkspaceHTMLPrimitives.ownedHitTargetClass",
        "WorkspaceHTMLPrimitives.interactiveHitTargetClass",
        "WorkspaceHTMLPrimitives.iconHitTargetClass",
        "WorkspaceHTMLPrimitives.textHitTargetClass",
        "WorkspaceHTMLPrimitives.textEntryHitTargetClass",
        "WorkspaceHTMLPrimitives.rowHitTargetClass",
        "WorkspaceHTMLPrimitives.capsuleHitTargetClass",
        "WorkspaceHTMLPrimitives.formActionHitTargetClass",
        "WorkspaceHTMLPrimitives.adjustableHitTargetClass"
    ]

    private let hitTargetKindMarkers = [
        "WorkspaceHTMLPrimitives.hitTargetAttributes",
        "WorkspaceHTMLPrimitives.hitTargetKindAttribute",
        #"data-hit-target-kind"#
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
            guard containsHTMLInteractiveElement(line) else { return nil }
            if lineHasPrimitiveTargetContract(line) {
                return nil
            }
            if lineHasSharedTargetClass(line) {
                guard lineHasSemanticHitTargetKind(line) else {
                    return "\(relativePath):\(index + 1) generated HTML control uses a shared hit-target class without semantic data-hit-target-kind"
                }
                return nil
            }
            return "\(relativePath):\(index + 1) generated HTML control lacks shared hit-target primitive"
        }
    }

    private func containsHTMLInteractiveElement(_ line: String) -> Bool {
        line.contains("<button")
            || line.contains("<summary")
            || line.contains("<a ")
            || line.contains("<input")
            || line.contains("<select")
            || line.contains("<textarea")
    }

    private func lineHasPrimitiveTargetContract(_ line: String) -> Bool {
        primitiveMarkers.contains { line.contains($0) }
    }

    private func lineHasSharedTargetClass(_ line: String) -> Bool {
        hitTargetMarkers.contains { line.contains($0) }
    }

    private func lineHasSemanticHitTargetKind(_ line: String) -> Bool {
        hitTargetKindMarkers.contains { line.contains($0) }
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
               !isSharedDesignSystem(relativePath) {
                violations.append("\(relativePath):\(index + 1) raw minimum hit-target frame should use semantic target or decorative helper")
            }

            if line.contains(".contentShape("),
               !isSharedDesignSystem(relativePath) {
                violations.append("\(relativePath):\(index + 1) raw contentShape should live in the shared target helper")
            }

            if line.contains(".allowsHitTesting("),
               !isSharedDesignSystem(relativePath) {
                violations.append("\(relativePath):\(index + 1) hit-testing override should not be used on app chrome")
            }

            if usesGenericTargetHelper(line),
               !isSharedDesignSystem(relativePath) {
                violations.append("\(relativePath):\(index + 1) generic hit-target helper should use a semantic target helper")
            }

            if isCompactPlatformButtonStyle(line),
               !isSystemMenuItemButton(lines: lines, index: index) {
                violations.append("\(relativePath):\(index + 1) compact platform button style should use QuillCodePressableButtonStyle or QuillCodeActionButtonStyle")
            }

            if line.contains(".buttonStyle(QuillCodePressableButtonStyle())"),
               !hasSharedTarget(in: owningControlScope) {
                violations.append("\(relativePath):\(index + 1) pressable button lacks explicit shared hit target")
            }

            if line.contains(".labelStyle(.iconOnly)"),
               !window(in: lines, around: index, radius: 10).contains("quillCodeIconButtonTarget") {
                violations.append("\(relativePath):\(index + 1) icon-only control lacks icon hit target")
            }

            if isButtonDeclaration(line),
               !isSystemMenuItemButton(lines: lines, index: index),
               !hasSharedTarget(in: declarationScope) {
                violations.append("\(relativePath):\(index + 1) Button lacks shared hit target")
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
               !hasButtonStyle(in: menuTriggerScope) {
                violations.append("\(relativePath):\(index + 1) Menu trigger lacks explicit press or platform style")
            }

            if isPickerDeclaration(line),
               !hasSharedTarget(in: declarationScope) {
                violations.append("\(relativePath):\(index + 1) Picker lacks shared hit target")
            }

            if isLinkDeclaration(line),
               !hasSharedTarget(in: declarationScope) {
                violations.append("\(relativePath):\(index + 1) Link lacks shared hit target")
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

    private func hasButtonStyle(in sourceWindow: String) -> Bool {
        sourceWindow.contains(".buttonStyle(")
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

    private func isRawMinimumHitTargetFrame(_ line: String) -> Bool {
        line.contains(".frame(width: QuillCodeMetrics.minimumHitTarget, height: QuillCodeMetrics.minimumHitTarget)")
    }

    private func isSharedDesignSystem(_ relativePath: String) -> Bool {
        relativePath == "Sources/QuillCodeApp/QuillCodeDesignSystem.swift"
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

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
