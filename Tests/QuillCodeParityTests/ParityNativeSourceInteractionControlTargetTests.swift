import XCTest

final class ParityNativeSourceInteractionControlTargetTests: QuillCodeParityTestCase {
    func testNativeSourceAuditCoversDisclosureGroupTriggers() throws {
        try assertNativeSourceAuditContains(
            "DisclosureGroup trigger lacks shared hit target",
            in: """
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
            """,
            message: "A target inside expanded disclosure content must not satisfy the disclosure toggle label."
        )
    }

    func testNativeSourceAuditAcceptsDisclosureGroupTriggerContracts() throws {
        try assertNoNativeSourceAuditViolations(for: """
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
    }

    func testNativeSourceAuditCoversAdjustableControls() throws {
        try assertNativeSourceAuditViolationCount(
            containing: "adjustable control lacks shared adjustable hit target",
            in: """
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
            """,
            equals: 2,
            message: "Sliders and steppers should not pass without a semantic adjustable-control target."
        )
    }

    func testNativeSourceAuditAcceptsAdjustableControlContracts() throws {
        try assertNoNativeSourceAuditViolations(for: """
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
    }

    func testNativeSourceAuditRejectsGenericHitTargetHelpers() throws {
        let violations = try nativeSourceAuditViolations(for: """
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

        XCTAssertEqual(
            violations.filter { $0.contains("generic hit-target helper should use a semantic target helper") }.count,
            2,
            "Generic target helpers should not satisfy visible app controls."
        )
        XCTAssertTrue(violations.contains { $0.contains("Button lacks shared hit target") })
    }

    func testNativeSourceAuditRejectsLinksWithoutLinkSemantics() throws {
        try assertNativeSourceAuditViolationCount(
            containing: "Link should use quillCodeLinkTarget so external navigation is not styled as a button press",
            in: """
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
            """,
            equals: 1,
            message: "Native links need link semantics; button-sized geometry alone is not enough."
        )
    }

    func testNativeSourceAuditRejectsMismatchedSemanticTargets() throws {
        let violations = try nativeSourceAuditViolations(for: """
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

        XCTAssertTrue(violations.contains { $0.contains("Button uses incompatible shared hit target") })
        XCTAssertTrue(violations.contains { $0.contains("text-entry control lacks shared text-entry hit target") })
        XCTAssertTrue(violations.contains { $0.contains("Picker uses incompatible shared hit target") })
        XCTAssertTrue(violations.contains { $0.contains("toggle control lacks shared switch-row hit target") })
        XCTAssertTrue(violations.contains { $0.contains("adjustable control lacks shared adjustable hit target") })
    }
}
