import XCTest
import QuillCodeTools
@testable import QuillCodePlatformUI

#if canImport(AppKit)
import AppKit
#endif

final class TerminalMouseCoordinateMapperTests: XCTestCase {
    func testMapperUsesOneBasedClampedCells() {
        let metrics = TerminalCellMetrics(width: 10, height: 20)
        let size = CGSize(width: 100, height: 80)

        XCTAssertEqual(
            TerminalMouseCoordinateMapper.position(at: .zero, in: size, metrics: metrics),
            TerminalMousePosition(column: 1, row: 1)
        )
        XCTAssertEqual(
            TerminalMouseCoordinateMapper.position(
                at: CGPoint(x: 10, y: 20),
                in: size,
                metrics: metrics
            ),
            TerminalMousePosition(column: 2, row: 2)
        )
        XCTAssertEqual(
            TerminalMouseCoordinateMapper.position(
                at: CGPoint(x: 10_000, y: 10_000),
                in: size,
                metrics: metrics
            ),
            TerminalMousePosition(column: 10, row: 4)
        )
        XCTAssertEqual(
            TerminalMouseCoordinateMapper.position(
                at: CGPoint(x: -10, y: -10),
                in: size,
                metrics: metrics
            ),
            TerminalMousePosition(column: 1, row: 1)
        )
    }
}

#if canImport(AppKit)
@MainActor
final class TerminalInputCaptureNSViewTests: XCTestCase {
    func testKeyboardCaptureMapsSpecialTextControlAndPasteInput() throws {
        let view = TerminalInputCaptureNSView(frame: NSRect(x: 0, y: 0, width: 100, height: 80))
        let mode = TerminalKeyboardMode(applicationCursorKeys: true, bracketedPaste: true)
        var requests: [TerminalKeyboardInputRequest] = []
        view.update(
            reporting: .disabled,
            keyboardMode: mode,
            metrics: .default,
            onMouseInput: { _ in },
            onKeyboardInput: { requests.append($0) }
        )

        XCTAssertTrue(view.handleKeyboard(try keyEvent(keyCode: 126)))
        XCTAssertTrue(view.handleKeyboard(try keyEvent(
            keyCode: 8,
            characters: "\u{03}",
            charactersIgnoringModifiers: "c",
            modifiers: [.control]
        )))
        XCTAssertTrue(view.handlePaste("hello"))

        XCTAssertEqual(requests.map(\.mode), [mode, mode, mode])
        XCTAssertEqual(requests[0].event.key, .arrowUp)
        XCTAssertEqual(requests[1].event.key, .text("c"))
        XCTAssertEqual(requests[1].event.modifiers, .init(control: true))
        XCTAssertEqual(requests[2].event.key, .paste("hello"))
    }

    func testKeyboardCaptureRejectsCommandShortcutsAndDisabledMode() throws {
        let view = TerminalInputCaptureNSView(frame: .zero)
        var requests: [TerminalKeyboardInputRequest] = []
        view.update(
            reporting: .disabled,
            metrics: .default,
            onMouseInput: { _ in },
            onKeyboardInput: { requests.append($0) }
        )

        XCTAssertFalse(view.handleKeyboard(try keyEvent(keyCode: 126)))
        view.update(
            reporting: .disabled,
            keyboardMode: .standard,
            metrics: .default,
            onMouseInput: { _ in },
            onKeyboardInput: { requests.append($0) }
        )
        XCTAssertFalse(view.handleKeyboard(try keyEvent(
            keyCode: 8,
            characters: "c",
            charactersIgnoringModifiers: "c",
            modifiers: [.command]
        )))
        XCTAssertTrue(requests.isEmpty)
    }

    func testPointerCaptureMapsButtonsModifiersAndDeduplicatesMotion() {
        let view = TerminalInputCaptureNSView(frame: NSRect(x: 0, y: 0, width: 100, height: 80))
        var requests: [TerminalMouseInputRequest] = []
        view.update(
            reporting: TerminalMouseReporting(trackingMode: .anyMotion, encoding: .sgr),
            metrics: TerminalCellMetrics(width: 10, height: 20),
            onMouseInput: { requests.append($0) }
        )
        let modifiers = TerminalMouseModifiers(shift: true, option: true, control: false)

        XCTAssertTrue(view.handlePointer(
            kind: .press,
            button: .right,
            location: CGPoint(x: 15, y: 25),
            modifiers: modifiers
        ))
        XCTAssertTrue(view.handlePointer(
            kind: .motion,
            button: .middle,
            location: CGPoint(x: 25, y: 45)
        ))
        XCTAssertTrue(view.handlePointer(
            kind: .motion,
            button: .middle,
            location: CGPoint(x: 25, y: 45)
        ))

        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests[0].event.button, .right)
        XCTAssertEqual(requests[0].event.position, TerminalMousePosition(column: 2, row: 2))
        XCTAssertEqual(requests[0].event.modifiers, modifiers)
        XCTAssertEqual(requests[1].event.kind, .motion)
        XCTAssertEqual(requests[1].event.button, .middle)
        XCTAssertEqual(requests[1].event.position, TerminalMousePosition(column: 3, row: 3))
    }

    func testPointerCaptureAccumulatesPreciseScrollAndEmitsCellPosition() {
        let view = TerminalInputCaptureNSView(frame: NSRect(x: 0, y: 0, width: 100, height: 80))
        var requests: [TerminalMouseInputRequest] = []
        view.update(
            reporting: TerminalMouseReporting(trackingMode: .button, encoding: .sgr),
            metrics: TerminalCellMetrics(width: 10, height: 20),
            onMouseInput: { requests.append($0) }
        )

        XCTAssertTrue(view.handleScroll(
            horizontalDelta: 0,
            verticalDelta: 4,
            isPrecise: true,
            location: CGPoint(x: 15, y: 25)
        ))
        XCTAssertTrue(requests.isEmpty)
        XCTAssertTrue(view.handleScroll(
            horizontalDelta: 0,
            verticalDelta: 4,
            isPrecise: true,
            location: CGPoint(x: 15, y: 25)
        ))

        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests[0].event.kind, .scrollUp)
        XCTAssertEqual(requests[0].event.position, TerminalMousePosition(column: 2, row: 2))

        XCTAssertTrue(view.handleScroll(
            horizontalDelta: -1,
            verticalDelta: 0,
            isPrecise: false,
            location: CGPoint(x: 99, y: 79)
        ))
        XCTAssertEqual(requests.last?.event.kind, .scrollRight)
        XCTAssertEqual(requests.last?.event.position, TerminalMousePosition(column: 10, row: 4))
    }

    func testDisabledPointerCaptureLetsInputPassThrough() {
        let view = TerminalInputCaptureNSView(frame: NSRect(x: 0, y: 0, width: 100, height: 80))
        var requests: [TerminalMouseInputRequest] = []
        view.update(
            reporting: .disabled,
            metrics: .default,
            onMouseInput: { requests.append($0) }
        )

        XCTAssertFalse(view.handlePointer(
            kind: .press,
            button: .left,
            location: CGPoint(x: 1, y: 1)
        ))
        XCTAssertFalse(view.handleScroll(
            horizontalDelta: 0,
            verticalDelta: 1,
            isPrecise: false,
            location: CGPoint(x: 1, y: 1)
        ))
        XCTAssertTrue(requests.isEmpty)
    }

    private func keyEvent(
        keyCode: UInt16,
        characters: String = "",
        charactersIgnoringModifiers: String = "",
        modifiers: NSEvent.ModifierFlags = []
    ) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: charactersIgnoringModifiers,
            isARepeat: false,
            keyCode: keyCode
        ))
    }
}
#endif
