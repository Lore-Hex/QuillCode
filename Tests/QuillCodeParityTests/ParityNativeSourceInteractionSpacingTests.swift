import XCTest

final class ParityNativeSourceInteractionSpacingTests: QuillCodeParityTestCase {
    func testNativeSourceAuditRejectsRawNumericControlClusterSpacing() throws {
        try assertNativeSourceAuditViolationCount(
            containing: "interactive control cluster spacing should use a named QuillCodeMetrics spacing token",
            in: """
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
            """,
            equals: 2,
            message: "Button groups should use named spacing metrics so visual changes cannot change collision budgets."
        )
    }

    func testNativeSourceAuditRejectsImplicitControlClusterSpacing() throws {
        try assertNativeSourceAuditViolationCount(
            containing: "interactive control cluster spacing should use a named QuillCodeMetrics spacing token",
            in: """
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
            """,
            equals: 2,
            message: "Interactive clusters should not inherit SwiftUI's default spacing."
        )
    }

    func testNativeSourceAuditAcceptsSingleControlWithImplicitPassiveSpacing() throws {
        try assertNoNativeSourceAuditViolations(for: """
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
    }

    func testNativeSourceAuditAcceptsMultilineNamedControlClusterSpacing() throws {
        try assertNoNativeSourceAuditViolations(for: """
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
    }

    func testNativeSourceAuditAcceptsNamedControlClusterSpacing() throws {
        try assertNoNativeSourceAuditViolations(for: """
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
                    columns: [
                        GridItem(
                            .adaptive(minimum: 96),
                            spacing: QuillCodeMetrics.denseControlClusterSpacing
                        )
                    ],
                    spacing: QuillCodeMetrics.denseControlClusterSpacing
                ) {
                    Button("Read") {}
                        .quillCodeCapsuleButtonTarget(minWidth: 96)
                        .buttonStyle(QuillCodeActionButtonStyle())
                }
            }
        }
        """)
    }
}
