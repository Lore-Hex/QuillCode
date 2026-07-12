#if canImport(AppKit)
import AppKit
import QuillCodeTools

@MainActor
final class TerminalInputCaptureNSView: NSView {
    private var reporting = TerminalMouseReporting.disabled
    private var keyboardMode: TerminalKeyboardMode?
    private var metrics = TerminalCellMetrics.default
    private var onMouseInput: (TerminalMouseInputRequest) -> Void = { _ in }
    private var onKeyboardInput: (TerminalKeyboardInputRequest) -> Void = { _ in }
    private var scrollAccumulator = TerminalScrollWheelAccumulator()
    private var lastMotion: MotionIdentity?
    private var trackingAreaReference: NSTrackingArea?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { keyboardMode != nil }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        needsDisplay = accepted
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        needsDisplay = resigned
        return resigned
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard window?.firstResponder === self else { return }
        NSColor.controlAccentColor.withAlphaComponent(0.8).setStroke()
        let path = NSBezierPath(
            roundedRect: bounds.insetBy(dx: 1, dy: 1),
            xRadius: 4,
            yRadius: 4
        )
        path.lineWidth = 2
        path.stroke()
    }

    func update(
        reporting: TerminalMouseReporting,
        keyboardMode: TerminalKeyboardMode? = nil,
        metrics: TerminalCellMetrics,
        onMouseInput: @escaping (TerminalMouseInputRequest) -> Void,
        onKeyboardInput: @escaping (TerminalKeyboardInputRequest) -> Void = { _ in }
    ) {
        if self.reporting != reporting {
            scrollAccumulator.reset()
            lastMotion = nil
        }
        self.reporting = reporting
        self.keyboardMode = keyboardMode
        self.metrics = metrics
        self.onMouseInput = onMouseInput
        self.onKeyboardInput = onKeyboardInput
    }

    override func updateTrackingAreas() {
        if let trackingAreaReference { removeTrackingArea(trackingAreaReference) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.activeInKeyWindow, .inVisibleRect, .mouseMoved, .mouseEnteredAndExited],
            owner: self
        )
        addTrackingArea(area)
        trackingAreaReference = area
        super.updateTrackingAreas()
    }

    override func mouseDown(with event: NSEvent) {
        focusForKeyboardInput()
        handlePointer(kind: .press, button: .left, event: event)
    }

    override func mouseDragged(with event: NSEvent) {
        handlePointer(kind: .motion, button: .left, event: event)
    }

    override func mouseUp(with event: NSEvent) {
        handlePointer(kind: .release, button: .left, event: event)
        lastMotion = nil
    }

    override func rightMouseDown(with event: NSEvent) {
        focusForKeyboardInput()
        handlePointer(kind: .press, button: .right, event: event)
    }

    override func rightMouseDragged(with event: NSEvent) {
        handlePointer(kind: .motion, button: .right, event: event)
    }

    override func rightMouseUp(with event: NSEvent) {
        handlePointer(kind: .release, button: .right, event: event)
        lastMotion = nil
    }

    override func otherMouseDown(with event: NSEvent) {
        guard event.buttonNumber == 2 else { return }
        focusForKeyboardInput()
        handlePointer(kind: .press, button: .middle, event: event)
    }

    override func otherMouseDragged(with event: NSEvent) {
        guard event.buttonNumber == 2 else { return }
        handlePointer(kind: .motion, button: .middle, event: event)
    }

    override func otherMouseUp(with event: NSEvent) {
        guard event.buttonNumber == 2 else { return }
        handlePointer(kind: .release, button: .middle, event: event)
        lastMotion = nil
    }

    override func mouseMoved(with event: NSEvent) {
        guard reporting.trackingMode == .anyMotion else { return }
        handlePointer(kind: .motion, button: .none, event: event)
    }

    override func mouseExited(with event: NSEvent) {
        lastMotion = nil
        super.mouseExited(with: event)
    }

    override func scrollWheel(with event: NSEvent) {
        guard reporting.isEnabled else {
            super.scrollWheel(with: event)
            return
        }
        _ = handleScroll(
            horizontalDelta: Double(event.scrollingDeltaX),
            verticalDelta: Double(event.scrollingDeltaY),
            isPrecise: event.hasPreciseScrollingDeltas,
            location: localLocation(for: event),
            modifiers: modifiers(for: event)
        )
    }

    override func keyDown(with event: NSEvent) {
        guard handleKeyboard(event) else {
            super.keyDown(with: event)
            return
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "v" else {
            return false
        }
        guard let text = NSPasteboard.general.string(forType: .string) else { return true }
        return handlePaste(text)
    }

    @discardableResult
    func handleKeyboard(_ event: NSEvent) -> Bool {
        guard let keyboardMode,
              let inputEvent = TerminalMacKeyboardMapper.inputEvent(from: event) else {
            return false
        }
        onKeyboardInput(TerminalKeyboardInputRequest(event: inputEvent, mode: keyboardMode))
        return true
    }

    @discardableResult
    func handlePaste(_ text: String) -> Bool {
        guard let keyboardMode, !text.isEmpty else { return false }
        onKeyboardInput(TerminalKeyboardInputRequest(
            event: TerminalKeyboardInputEvent(key: .paste(text)),
            mode: keyboardMode
        ))
        return true
    }

    @discardableResult
    func handleScroll(
        horizontalDelta: Double,
        verticalDelta: Double,
        isPrecise: Bool,
        location: CGPoint,
        modifiers: TerminalMouseModifiers = TerminalMouseModifiers()
    ) -> Bool {
        guard reporting.isEnabled else { return false }
        let kinds = scrollAccumulator.consume(
            horizontalDelta: horizontalDelta,
            verticalDelta: verticalDelta,
            isPrecise: isPrecise
        )
        guard !kinds.isEmpty else { return true }
        let position = mappedPosition(at: location)
        for kind in kinds {
            send(kind: kind, button: .none, position: position, modifiers: modifiers)
        }
        return true
    }

    @discardableResult
    func handlePointer(
        kind: TerminalMouseEventKind,
        button: TerminalMouseButton,
        location: CGPoint,
        modifiers: TerminalMouseModifiers = TerminalMouseModifiers()
    ) -> Bool {
        guard reporting.isEnabled else { return false }
        let position = mappedPosition(at: location)
        let motion = MotionIdentity(position: position, button: button)
        if kind == .motion, motion == lastMotion { return true }
        lastMotion = kind == .motion ? motion : nil
        send(kind: kind, button: button, position: position, modifiers: modifiers)
        return true
    }

    private func handlePointer(
        kind: TerminalMouseEventKind,
        button: TerminalMouseButton,
        event: NSEvent
    ) {
        _ = handlePointer(
            kind: kind,
            button: button,
            location: localLocation(for: event),
            modifiers: modifiers(for: event)
        )
    }

    private func mappedPosition(at location: CGPoint) -> TerminalMousePosition {
        TerminalMouseCoordinateMapper.position(at: location, in: bounds.size, metrics: metrics)
    }

    private func localLocation(for event: NSEvent) -> CGPoint {
        convert(event.locationInWindow, from: nil)
    }

    private func focusForKeyboardInput() {
        guard keyboardMode != nil else { return }
        window?.makeFirstResponder(self)
    }

    private func modifiers(for event: NSEvent) -> TerminalMouseModifiers {
        TerminalMouseModifiers(
            shift: event.modifierFlags.contains(.shift),
            option: event.modifierFlags.contains(.option),
            control: event.modifierFlags.contains(.control)
        )
    }

    private func send(
        kind: TerminalMouseEventKind,
        button: TerminalMouseButton,
        position: TerminalMousePosition,
        modifiers: TerminalMouseModifiers
    ) {
        onMouseInput(TerminalMouseInputRequest(
            event: TerminalMouseInputEvent(
                kind: kind,
                button: button,
                position: position,
                modifiers: modifiers
            ),
            reporting: reporting
        ))
    }

    private struct MotionIdentity: Equatable {
        var position: TerminalMousePosition
        var button: TerminalMouseButton
    }
}
#endif
