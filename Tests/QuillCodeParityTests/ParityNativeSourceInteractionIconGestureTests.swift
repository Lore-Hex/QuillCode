import XCTest

final class ParityNativeSourceInteractionIconGestureTests: QuillCodeParityTestCase {
    func testNativeSourceAuditRejectsUnnamedIconTargets() throws {
        try assertNativeSourceAuditViolationCount(
            containing: "icon hit target needs a visible label, accessibilityLabel, or help tooltip",
            in: """
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
            """,
            equals: 2,
            message: "Icon-sized controls need discoverable names, not only a large hit rectangle."
        )
    }

    func testNativeSourceAuditAcceptsNamedIconTargets() throws {
        try assertNoNativeSourceAuditViolations(for: """
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
    }

    func testNativeSourceAuditAllowsNamedOwnedGestureTargets() throws {
        try assertNoNativeSourceAuditViolations(for: """
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
    }

    func testNativeSourceAuditRejectsUnnamedGestureTargets() throws {
        let violations = try nativeSourceAuditViolations(for: """
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

        XCTAssertGreaterThanOrEqual(
            violations.filter {
                $0.contains("gesture-based click target should use Button, Link, or quillCodeOwnedGestureTarget")
            }.count,
            3
        )
    }

    func testNativeSourceAuditAcceptsDecorativeIconFrames() throws {
        try assertNoNativeSourceAuditViolations(for: """
        import SwiftUI

        struct DecorativeChrome: View {
            var body: some View {
                Image(systemName: "info")
                    .quillCodeDecorativeIconFrame()
            }
        }
        """)
    }
}
