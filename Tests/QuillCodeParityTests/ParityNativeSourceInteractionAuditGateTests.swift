import XCTest

final class ParityNativeSourceInteractionAuditGateTests: QuillCodeParityTestCase {
    func testNativeSourceAuditAcceptsMenuPickerAndTextEditorContracts() throws {
        try assertNoNativeSourceAuditViolations(for: """
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
    }

    func testNativeSourceAuditFindsOuterMenuLabelAfterGroupedButtonLabels() throws {
        try assertNoNativeSourceAuditViolations(for: """
        import SwiftUI

        struct GroupedMenuTargets: View {
            var body: some View {
                Menu {
                    Section("Actions") {
                        Button {} label: {
                            Label("Bootstrap", systemImage: "hammer")
                        }
                        .quillCodePlatformMenuItemTarget(reason: "AppKit owns menu rows.")
                    }

                    Button {} label: {
                        Text("Settings")
                    }
                    .quillCodePlatformMenuItemTarget(reason: "AppKit owns menu rows.")
                } label: {
                    Image(systemName: "ellipsis")
                        .quillCodeIconButtonTarget()
                }
                .buttonStyle(QuillCodePressableButtonStyle())
                .help("More actions")
            }
        }
        """)
    }

    func testNativeSourceAuditRejectsActionButtonStyleWithoutSemanticTarget() throws {
        try assertNativeSourceAuditContains(
            "Button lacks shared hit target",
            in: """
            import SwiftUI

            struct StyledButAmbiguousAction: View {
                var body: some View {
                    Button("Save") {}
                        .buttonStyle(QuillCodeActionButtonStyle(.primary))
                }
            }
            """,
            message: "Action button styling should not satisfy semantic click-target ownership by itself."
        )
    }

    func testNativeSourceAuditRejectsAmbiguousMinimumHitTargetFrames() throws {
        try assertNativeSourceAuditContains(
            "raw minimum hit-target frame should use semantic target or decorative helper",
            in: """
            import SwiftUI

            struct AmbiguousChrome: View {
                var body: some View {
                    Image(systemName: "info")
                        .frame(width: QuillCodeMetrics.minimumHitTarget, height: QuillCodeMetrics.minimumHitTarget)
                }
            }
            """,
            message: "Raw 44 pt frames hide whether a view is clickable or decorative."
        )
    }

    func testNativeSourceAuditRejectsRawShapeAndHitTestingOverrides() throws {
        let violations = try nativeSourceAuditViolations(for: """
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

        XCTAssertTrue(
            violations.contains { $0.contains("raw contentShape should live in the shared target helper") },
            "Raw content shapes let controls invent local hit regions instead of using the design-system contract."
        )
        XCTAssertTrue(
            violations.contains { $0.contains("hit-testing override should not be used on app chrome") },
            "Hit-testing overrides can create visible dead targets and should fail source review."
        )
    }

    func testNativeSourceAuditDoesNotLetNearbyTargetsSatisfyAnotherControl() throws {
        let violations = try nativeSourceAuditViolations(for: """
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

        XCTAssertTrue(violations.contains { $0.contains("Button lacks shared hit target") })
        XCTAssertTrue(violations.contains { $0.contains("Button lacks explicit press or platform style") })
        XCTAssertTrue(violations.contains { $0.contains("Menu trigger lacks shared hit target") })
        XCTAssertFalse(
            violations.contains { $0.contains("Ready") },
            "A fully styled neighboring button should not be blamed while testing scope extraction."
        )
    }
}
