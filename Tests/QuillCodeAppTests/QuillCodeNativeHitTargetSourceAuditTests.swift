import XCTest
@testable import QuillCodeApp

@MainActor
final class QuillCodeNativeHitTargetSourceAuditTests: QuillCodeNativeHitTargetAuditTestCase {
    func testSwiftInteractiveControlsDeclareHitTargetContractAtSource() throws {
        let packageRoot = packageRoot()
        let appSourceRoot = packageRoot
            .appendingPathComponent("Sources", isDirectory: true)
            .appendingPathComponent("QuillCodeApp", isDirectory: true)
        let desktopSourceRoot = packageRoot
            .appendingPathComponent("Sources", isDirectory: true)
            .appendingPathComponent("quill-code-desktop", isDirectory: true)
        let visibleDesktopFiles = try swiftSourceFiles(in: desktopSourceRoot)
            .filter { $0.lastPathComponent != "DesktopCommands.swift" }
        let issues = try (swiftSourceFiles(in: appSourceRoot) + visibleDesktopFiles)
            .flatMap { try sourceHitTargetContractIssues(in: $0, sourceRoot: packageRoot) }
            .sorted()

        XCTAssertEqual(issues, [])
    }

    func testSwiftGestureTargetsDeclareOwnedGestureTargetAtSource() throws {
        let source = """
        import SwiftUI

        struct RawGestureTargets: View {
            var body: some View {
                Text("Open")
                    .onTapGesture {}
                Text("Hold")
                    .onLongPressGesture {}
                Text("Priority")
                    .highPriorityGesture(TapGesture())
                Text("Custom")
                    .gesture(TapGesture())
            }
        }
        """

        let issues = try sourceAuditIssues(for: source)

        XCTAssertEqual(
            issues.filter { $0.contains("gesture-based click target should use Button, Link, or quillCodeOwnedGestureTarget") }.count,
            4
        )
    }

    func testSwiftOwnedGestureTargetSatisfiesGestureSourceAudit() throws {
        let source = """
        import SwiftUI

        struct OwnedGestureTarget: View {
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
        """

        let issues = try sourceAuditIssues(for: source)

        XCTAssertEqual(issues, [])
    }

    func testSwiftTextEntrySourceAuditRequiresStableAccessibilityIdentifier() throws {
        let source = """
        import SwiftUI

        struct MissingTextEntryIdentifier: View {
            @State private var query = ""

            var body: some View {
                TextField("Search", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .quillCodeTextEntryTarget()
            }
        }
        """

        let issues = try sourceAuditIssues(for: source)

        XCTAssertEqual(
            issues.filter { $0.contains("text-entry target should declare a stable accessibilityIdentifier") }.count,
            1
        )
    }

    func testSwiftTextEntrySourceAuditAcceptsStableAccessibilityIdentifier() throws {
        let source = """
        import SwiftUI

        struct IdentifiedTextEntry: View {
            @State private var query = ""

            var body: some View {
                TextField("Search", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .quillCodeTextEntryTarget()
                    .accessibilityIdentifier("quillcode-search-input")
            }
        }
        """

        let issues = try sourceAuditIssues(for: source)

        XCTAssertEqual(issues, [])
    }

    func testSwiftNavigationLinkSourceAuditRequiresPressSemantics() throws {
        let source = """
        import SwiftUI

        struct NavigationChrome: View {
            var body: some View {
                VStack {
                    NavigationLink(destination: Text("Details")) {
                        Text("Open details")
                    }

                    NavigationLink(destination: Text("Wrong semantics")) {
                        Text("Open")
                            .quillCodeLinkTarget()
                    }
                    .buttonStyle(QuillCodePressableButtonStyle())

                    NavigationLink(destination: Text("No tactile feedback")) {
                        Text("Open")
                            .quillCodeFullRowButtonTarget()
                    }
                }
            }
        }
        """

        let issues = try sourceAuditIssues(for: source)

        XCTAssertEqual(
            issues.filter { $0.contains("missing QuillCode hit-target marker") }.count,
            1
        )
        XCTAssertEqual(
            issues.filter { $0.contains("missing QuillCode press/action button style") }.count,
            1
        )
        XCTAssertEqual(
            issues.filter { $0.contains("NavigationLink should use press-style hit-target semantics") }.count,
            1
        )
    }

    func testSwiftNavigationLinkSourceAuditAcceptsFullRowPressTarget() throws {
        let source = """
        import SwiftUI

        struct NavigationChrome: View {
            var body: some View {
                NavigationLink(destination: Text("Details")) {
                    HStack {
                        Text("Open details")
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                    .quillCodeFullRowButtonTarget()
                }
                .buttonStyle(QuillCodePressableButtonStyle())
            }
        }
        """

        let issues = try sourceAuditIssues(for: source)

        XCTAssertEqual(issues, [])
    }
}
