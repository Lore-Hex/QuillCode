import XCTest

final class ParityNativeSourceInteractionAuditGateTests: QuillCodeParityTestCase {
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
                .help("More actions")

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

    func testNativeSourceAuditCoversDisclosureGroupTriggers() throws {
        let file = try makeTemporarySwiftFile("""
        import SwiftUI

        struct BadDisclosureTarget: View {
            @State private var expanded = false

            var body: some View {
                DisclosureGroup(isExpanded: $expanded) {
                    Button("Copy") {}
                        .quillCodeTextButtonTarget()
                        .buttonStyle(QuillCodePressableButtonStyle())
                } label: {
                    Text("Details")
                }
            }
        }
        """)

        let violations = try SwiftSourceInteractionTargetAudit(packageRoot: file.deletingLastPathComponent())
            .violations(in: [file])

        XCTAssertTrue(
            violations.contains { $0.contains("DisclosureGroup trigger lacks shared hit target") },
            "A target inside expanded disclosure content must not satisfy the disclosure toggle label."
        )
    }

    func testNativeSourceAuditAcceptsDisclosureGroupTriggerContracts() throws {
        let file = try makeTemporarySwiftFile("""
        import SwiftUI

        struct GoodDisclosureTarget: View {
            @State private var expanded = false

            var body: some View {
                DisclosureGroup(isExpanded: $expanded) {
                    Text("Raw details")
                } label: {
                    HStack {
                        Text("Details")
                        Spacer()
                    }
                    .quillCodeFullRowButtonTarget()
                }
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

    func testNativeSourceAuditRejectsLinksWithoutLinkSemantics() throws {
        let file = try makeTemporarySwiftFile("""
        import SwiftUI

        struct LinkChrome: View {
            var body: some View {
                VStack {
                    Link(destination: URL(string: "https://quillos.cloud")!) {
                        Text("Docs")
                            .quillCodeTextButtonTarget()
                    }
                    .buttonStyle(QuillCodePressableButtonStyle())

                    Link(destination: URL(string: "https://quillos.cloud")!) {
                        Text("Support")
                            .quillCodeLinkTarget()
                    }
                    .buttonStyle(QuillCodePressableButtonStyle())
                }
            }
        }
        """)

        let violations = try SwiftSourceInteractionTargetAudit(packageRoot: file.deletingLastPathComponent())
            .violations(in: [file])

        XCTAssertEqual(
            violations.filter { $0.contains("Link should use quillCodeLinkTarget so external navigation is not styled as a button press") }.count,
            1,
            "Native links need link semantics; button-sized geometry alone is not enough."
        )
    }

    func testNativeSourceAuditRejectsMismatchedSemanticTargets() throws {
        let file = try makeTemporarySwiftFile("""
        import SwiftUI

        struct MismatchedChrome: View {
            @State private var query = ""
            @State private var selected = 0
            @State private var value = 0.5

            var body: some View {
                VStack {
                    Button("Run") {}
                        .quillCodeTextEntryTarget()
                        .buttonStyle(QuillCodePressableButtonStyle())

                    TextField("Search", text: $query)
                        .quillCodeTextButtonTarget()

                    Picker("Mode", selection: $selected) {
                        Text("Auto").tag(0)
                    }
                    .pickerStyle(.segmented)
                    .quillCodeFullRowButtonTarget()

                    Toggle("Enable", isOn: .constant(true))
                        .quillCodeTextButtonTarget()

                    Slider(value: $value)
                        .quillCodeTextButtonTarget()
                }
            }
        }
        """)

        let violations = try SwiftSourceInteractionTargetAudit(packageRoot: file.deletingLastPathComponent())
            .violations(in: [file])

        XCTAssertTrue(
            violations.contains { $0.contains("Button uses incompatible shared hit target") },
            "Buttons should not pass with text-entry or other non-button semantic targets."
        )
        XCTAssertTrue(
            violations.contains { $0.contains("text-entry control lacks shared text-entry hit target") },
            "Text fields need text-entry semantics, not a visual button helper."
        )
        XCTAssertTrue(
            violations.contains { $0.contains("Picker uses incompatible shared hit target") },
            "Segmented pickers need segmented-control semantics, not row/button geometry."
        )
        XCTAssertTrue(
            violations.contains { $0.contains("toggle control lacks shared switch-row hit target") },
            "Toggles need switch-row semantics so the whole row is intentionally owned."
        )
        XCTAssertTrue(
            violations.contains { $0.contains("adjustable control lacks shared adjustable hit target") },
            "Sliders and other adjustable controls need adjust semantics."
        )
    }

    func testNativeSourceAuditRejectsUnnamedIconTargets() throws {
        let file = try makeTemporarySwiftFile("""
        import SwiftUI

        struct UnnamedIconChrome: View {
            var body: some View {
                VStack {
                    Button {
                    } label: {
                        Image(systemName: "ellipsis")
                            .quillCodeIconButtonTarget()
                    }
                    .buttonStyle(QuillCodePressableButtonStyle())

                    Menu {
                        Button("Rename") {}
                            .help("Rename thread")
                    } label: {
                        Image(systemName: "ellipsis")
                            .quillCodeIconButtonTarget()
                    }
                    .buttonStyle(QuillCodePressableButtonStyle())
                }
            }
        }
        """)

        let violations = try SwiftSourceInteractionTargetAudit(packageRoot: file.deletingLastPathComponent())
            .violations(in: [file])

        XCTAssertEqual(
            violations.filter { $0.contains("icon hit target needs a visible label, accessibilityLabel, or help tooltip") }.count,
            2,
            "Icon-sized controls need discoverable names, not only a large hit rectangle."
        )
    }

    func testNativeSourceAuditAcceptsNamedIconTargets() throws {
        let file = try makeTemporarySwiftFile("""
        import SwiftUI

        struct NamedIconChrome: View {
            var body: some View {
                VStack {
                    Button {
                    } label: {
                        Image(systemName: "xmark")
                            .quillCodeIconButtonTarget()
                    }
                    .buttonStyle(QuillCodePressableButtonStyle())
                    .accessibilityLabel("Close")

                    Button {
                    } label: {
                        Label("Retry", systemImage: "arrow.clockwise")
                            .labelStyle(.iconOnly)
                            .quillCodeIconButtonTarget()
                    }
                    .buttonStyle(QuillCodePressableButtonStyle())

                    Menu {
                        Button("Rename") {}
                    } label: {
                        Image(systemName: "ellipsis")
                            .quillCodeIconButtonTarget()
                    }
                    .buttonStyle(QuillCodePressableButtonStyle())
                    .help("More actions")
                }
            }
        }
        """)

        let violations = try SwiftSourceInteractionTargetAudit(packageRoot: file.deletingLastPathComponent())
            .violations(in: [file])

        XCTAssertEqual(violations, [])
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

    func testNativeSourceAuditRejectsRawNumericControlClusterSpacing() throws {
        let file = try makeTemporarySwiftFile("""
        import SwiftUI

        struct RawNumericClusterChrome: View {
            var body: some View {
                HStack(spacing: 12) {
                    Button("Run") {}
                        .quillCodeFormActionTarget()
                        .buttonStyle(QuillCodeActionButtonStyle(.primary))
                    Button("Cancel") {}
                        .quillCodeFormActionTarget()
                        .buttonStyle(QuillCodeActionButtonStyle())
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 10)], spacing: 10) {
                    Button("Read") {}
                        .quillCodeCapsuleButtonTarget(minWidth: 96)
                        .buttonStyle(QuillCodeActionButtonStyle())
                }
            }
        }
        """)

        let violations = try SwiftSourceInteractionTargetAudit(packageRoot: file.deletingLastPathComponent())
            .violations(in: [file])

        XCTAssertEqual(
            violations.filter { $0.contains("interactive control cluster spacing should use a named QuillCodeMetrics spacing token") }.count,
            2,
            "Button groups should use named spacing metrics so future visual changes cannot silently change the collision budget."
        )
    }

    func testNativeSourceAuditRejectsImplicitControlClusterSpacing() throws {
        let file = try makeTemporarySwiftFile("""
        import SwiftUI

        struct ImplicitClusterChrome: View {
            var body: some View {
                HStack {
                    Button("Run") {}
                        .quillCodeFormActionTarget()
                        .buttonStyle(QuillCodeActionButtonStyle(.primary))
                    Button("Cancel") {}
                        .quillCodeFormActionTarget()
                        .buttonStyle(QuillCodeActionButtonStyle())
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96))]) {
                    Button("Read") {}
                        .quillCodeCapsuleButtonTarget(minWidth: 96)
                        .buttonStyle(QuillCodeActionButtonStyle())
                    Button("Write") {}
                        .quillCodeCapsuleButtonTarget(minWidth: 96)
                        .buttonStyle(QuillCodeActionButtonStyle())
                }
            }
        }
        """)

        let violations = try SwiftSourceInteractionTargetAudit(packageRoot: file.deletingLastPathComponent())
            .violations(in: [file])

        XCTAssertEqual(
            violations.filter { $0.contains("interactive control cluster spacing should use a named QuillCodeMetrics spacing token") }.count,
            2,
            "Interactive clusters should not inherit SwiftUI's default spacing; default spacing is still an unreviewed click-target clearance choice."
        )
    }

    func testNativeSourceAuditAcceptsSingleControlWithImplicitPassiveSpacing() throws {
        let file = try makeTemporarySwiftFile("""
        import SwiftUI

        struct PassiveClusterChrome: View {
            var body: some View {
                HStack {
                    Text("Status")
                    Spacer()
                    Button("Retry") {}
                        .quillCodeFormActionTarget()
                        .buttonStyle(QuillCodeActionButtonStyle())
                }
            }
        }
        """)

        let violations = try SwiftSourceInteractionTargetAudit(packageRoot: file.deletingLastPathComponent())
            .violations(in: [file])

        XCTAssertEqual(violations, [])
    }

    func testNativeSourceAuditAcceptsMultilineNamedControlClusterSpacing() throws {
        let file = try makeTemporarySwiftFile("""
        import SwiftUI

        struct MultilineClusterChrome: View {
            var body: some View {
                HStack(
                    alignment: .center,
                    spacing: QuillCodeMetrics.controlClusterSpacing
                ) {
                    Button("Run") {}
                        .quillCodeFormActionTarget()
                        .buttonStyle(QuillCodeActionButtonStyle(.primary))
                    Button("Cancel") {}
                        .quillCodeFormActionTarget()
                        .buttonStyle(QuillCodeActionButtonStyle())
                }
            }
        }
        """)

        let violations = try SwiftSourceInteractionTargetAudit(packageRoot: file.deletingLastPathComponent())
            .violations(in: [file])

        XCTAssertEqual(violations, [])
    }

    func testNativeSourceAuditAcceptsNamedControlClusterSpacing() throws {
        let file = try makeTemporarySwiftFile("""
        import SwiftUI

        struct NamedClusterChrome: View {
            var body: some View {
                HStack(spacing: QuillCodeMetrics.denseControlClusterSpacing) {
                    Button("Run") {}
                        .quillCodeFormActionTarget()
                        .buttonStyle(QuillCodeActionButtonStyle(.primary))
                    Button("Cancel") {}
                        .quillCodeFormActionTarget()
                        .buttonStyle(QuillCodeActionButtonStyle())
                }

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 96), spacing: QuillCodeMetrics.denseControlClusterSpacing)],
                    spacing: QuillCodeMetrics.denseControlClusterSpacing
                ) {
                    Button("Read") {}
                        .quillCodeCapsuleButtonTarget(minWidth: 96)
                        .buttonStyle(QuillCodeActionButtonStyle())
                }
            }
        }
        """)

        let violations = try SwiftSourceInteractionTargetAudit(packageRoot: file.deletingLastPathComponent())
            .violations(in: [file])

        XCTAssertEqual(violations, [])
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

}
