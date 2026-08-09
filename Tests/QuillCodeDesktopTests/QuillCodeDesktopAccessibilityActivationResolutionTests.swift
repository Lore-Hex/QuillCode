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

    func testReviewActivationUsesNormalizedToggleMenuTitle() {
        let menu = element(
            identifier: "",
            role: kAXMenuItemRole as String,
            title: "Toggle Review",
            frame: .zero
        )
        let probe = QuillCodeNativeHitTargetProbe(
            contractID: "command.toggle-review-panel",
            family: .sidebar,
            collisionScope: "sidebar:tools",
            label: "Review",
            kind: .fullRow,
            action: .press,
            allowsNestedInteractiveChildren: false,
            requiresUnblockedInterior: true,
            requiresTactileFeedback: true,
            allowsTextSelection: false,
            selectorKind: .commandID,
            selector: "toggle-review-panel",
            requiredMinWidth: 40,
            requiredMinHeight: 40,
            samplePoints: []
        )

        let resolved = QuillCodeDesktopAccessibilityFrameSampler.resolveElementForActivation(
            probe,
            in: [menu]
        )

        XCTAssertEqual(resolved?.title, "Toggle Review")
    }

    func testSettingsActivationUsesEllipsisNativeMenuTitleWhenSidebarControlIsNotVisible() {
        let probe = QuillCodeNativeHitTargetProbe(
            contractID: "command.settings",
            family: .sidebar,
            collisionScope: "sidebar:tools",
            label: "Settings",
            kind: .fullRow,
            action: .press,
            allowsNestedInteractiveChildren: false,
            requiresUnblockedInterior: true,
            requiresTactileFeedback: true,
            allowsTextSelection: false,
            selectorKind: .commandID,
            selector: "settings",
            requiredMinWidth: 40,
            requiredMinHeight: 40,
            samplePoints: []
        )

        for title in ["Settings...", "Settings…"] {
            let menu = element(
                identifier: "",
                role: kAXMenuItemRole as String,
                title: title,
                frame: .zero
            )
            let resolved = QuillCodeDesktopAccessibilityFrameSampler.resolveElementForActivation(
                probe,
                in: [menu]
            )

            XCTAssertEqual(resolved?.title, title)
            XCTAssertEqual(resolved?.role, kAXMenuItemRole as String)
        }
    }

    func testNewChatActivationMatchesNativeMenuTitleCaseInsensitively() {
        let probe = QuillCodeNativeHitTargetProbe(
            contractID: "command.new-chat",
            family: .sidebar,
            collisionScope: "sidebar:primary",
            label: "New chat",
            kind: .fullRow,
            action: .press,
            allowsNestedInteractiveChildren: false,
            requiresUnblockedInterior: true,
            requiresTactileFeedback: true,
            allowsTextSelection: false,
            selectorKind: .commandID,
            selector: "new-chat",
            requiredMinWidth: 40,
            requiredMinHeight: 40,
            samplePoints: []
        )
        let menu = element(
            identifier: "",
            role: kAXMenuItemRole as String,
            title: "New Chat",
            frame: .zero
        )

        let resolved = QuillCodeDesktopAccessibilityFrameSampler.resolveElementForActivation(
            probe,
            in: [menu]
        )

        XCTAssertEqual(resolved?.title, "New Chat")
        XCTAssertEqual(resolved?.role, kAXMenuItemRole as String)
    }

    func testActivationResolutionResnapshotsUntilDelayedTargetAppears() async {
        let delayedTarget = element(
            identifier: "quillcode-sidebar-command-toggle-memories",
            frame: CGRect(x: 0, y: 0, width: 40, height: 40)
        )
        var snapshotCount = 0

        let resolved = await QuillCodeDesktopAccessibilityActivationSampler.waitForResolvableElement(
            commandProbe,
            maximumAttempts: 4,
            retryIntervalNanoseconds: 0
        ) {
            snapshotCount += 1
            return snapshotCount == 3 ? [delayedTarget] : []
        }

        XCTAssertEqual(resolved?.identifier, delayedTarget.identifier)
        XCTAssertEqual(snapshotCount, 3)
    }

    func testActivationResolutionStopsAtBoundWhenTargetNeverAppears() async {
        var snapshotCount = 0

        let resolved = await QuillCodeDesktopAccessibilityActivationSampler.waitForResolvableElement(
            commandProbe,
            maximumAttempts: 3,
            retryIntervalNanoseconds: 0
        ) {
            snapshotCount += 1
            return []
        }

        XCTAssertNil(resolved)
        XCTAssertEqual(snapshotCount, 3)
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
