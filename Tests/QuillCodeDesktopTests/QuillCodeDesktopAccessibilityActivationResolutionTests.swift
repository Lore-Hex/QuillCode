import AppKit
import ApplicationServices
import XCTest
import QuillCodeApp
@testable import quill_code_desktop

@MainActor
final class QuillCodeDesktopAccessibilityActivationResolutionTests: XCTestCase {
    func testCommandActivationPrefersVisibleWorkspaceControlOverMenuFallback() {
        let sidebar = element(
            identifier: "quillcode-sidebar-command-toggle-memories",
            frame: CGRect(x: 0, y: 0, width: 40, height: 40)
        )
        let menu = element(
            identifier: "quillcode-menu-command-toggle-memories",
            frame: CGRect(x: 0, y: 0, width: 200, height: 40)
        )

        let resolved = QuillCodeDesktopAccessibilityFrameSampler.resolveElementForActivation(
            commandProbe,
            in: [menu, sidebar]
        )

        XCTAssertEqual(resolved?.identifier, sidebar.identifier)
    }

    func testCommandActivationUsesNativeMenuWhenWorkspaceControlIsNotVisible() {
        let menu = element(
            identifier: "quillcode-menu-command-toggle-memories",
            frame: CGRect(x: 0, y: 0, width: 200, height: 40)
        )

        let resolved = QuillCodeDesktopAccessibilityFrameSampler.resolveElementForActivation(
            commandProbe,
            in: [menu]
        )

        XCTAssertEqual(resolved?.identifier, menu.identifier)
    }

    func testCommandActivationUsesTitledNativeMenuItemWhenSwiftUIDropsIdentifier() {
        let menu = element(
            identifier: "",
            role: kAXMenuItemRole as String,
            title: "Toggle Memories",
            frame: .zero
        )

        let resolved = QuillCodeDesktopAccessibilityFrameSampler.resolveElementForActivation(
            commandProbe,
            in: [menu]
        )

        XCTAssertEqual(resolved?.title, "Toggle Memories")
        XCTAssertEqual(resolved?.role, kAXMenuItemRole as String)
    }

    private var commandProbe: QuillCodeNativeHitTargetProbe {
        QuillCodeNativeHitTargetProbe(
            contractID: "command.toggle-memories",
            family: .sidebar,
            collisionScope: "sidebar:tools",
            label: "Memories",
            kind: .fullRow,
            action: .press,
            allowsNestedInteractiveChildren: false,
            requiresUnblockedInterior: true,
            requiresTactileFeedback: true,
            allowsTextSelection: false,
            selectorKind: .commandID,
            selector: "toggle-memories",
            requiredMinWidth: 40,
            requiredMinHeight: 40,
            samplePoints: []
        )
    }

    private func element(
        identifier: String,
        role: String = "AXButton",
        title: String = "Memories",
        frame: CGRect
    ) -> QuillCodeDesktopAccessibilityElementSnapshot {
        QuillCodeDesktopAccessibilityElementSnapshot(
            element: AXUIElementCreateSystemWide(),
            identifier: identifier,
            role: role,
            title: title,
            accessibilityLabel: "Memories",
            help: "",
            value: "",
            isFocused: false,
            frame: frame,
            ancestorIdentifiers: []
        )
    }
}
