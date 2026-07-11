import SwiftUI
import QuillCodeTools

#if canImport(AppKit)
import AppKit
#endif

public struct TerminalCellMetrics: Sendable, Hashable {
    public var width: CGFloat
    public var height: CGFloat

    public init(width: CGFloat = 8.4, height: CGFloat = 18) {
        self.width = width
        self.height = height
    }

    public static let `default` = TerminalCellMetrics()
}

public enum TerminalMouseCoordinateMapper {
    public static func position(
        at location: CGPoint,
        in size: CGSize,
        metrics: TerminalCellMetrics = .default
    ) -> TerminalMousePosition {
        let safeWidth = max(1, metrics.width)
        let safeHeight = max(1, metrics.height)
        let maxColumn = max(1, Int(ceil(size.width / safeWidth)))
        let maxRow = max(1, Int(ceil(size.height / safeHeight)))
        return TerminalMousePosition(
            column: min(maxColumn, max(1, Int(floor(location.x / safeWidth)) + 1)),
            row: min(maxRow, max(1, Int(floor(location.y / safeHeight)) + 1))
        )
    }
}

public struct TerminalPointerInputCaptureView: View {
    private var reporting: TerminalMouseReporting
    private var metrics: TerminalCellMetrics
    private var onMouseInput: (TerminalMouseInputRequest) -> Void

    public init(
        reporting: TerminalMouseReporting,
        metrics: TerminalCellMetrics = .default,
        onMouseInput: @escaping (TerminalMouseInputRequest) -> Void
    ) {
        self.reporting = reporting
        self.metrics = metrics
        self.onMouseInput = onMouseInput
    }

    public var body: some View {
        PlatformTerminalPointerInputCapture(
            reporting: reporting,
            metrics: metrics,
            onMouseInput: onMouseInput
        )
        .accessibilityElement()
        .accessibilityIdentifier("quillcode-terminal-mouse-input")
        .accessibilityLabel("Interactive terminal output")
        .accessibilityHint("Pointer clicks, drags, movement, and scrolling are sent to the running terminal program.")
    }
}

#if canImport(AppKit)
private struct PlatformTerminalPointerInputCapture: NSViewRepresentable {
    var reporting: TerminalMouseReporting
    var metrics: TerminalCellMetrics
    var onMouseInput: (TerminalMouseInputRequest) -> Void

    func makeNSView(context: Context) -> TerminalPointerCaptureNSView {
        let view = TerminalPointerCaptureNSView()
        view.update(reporting: reporting, metrics: metrics, onMouseInput: onMouseInput)
        return view
    }

    func updateNSView(_ view: TerminalPointerCaptureNSView, context: Context) {
        view.update(reporting: reporting, metrics: metrics, onMouseInput: onMouseInput)
    }
}

@MainActor
final class TerminalPointerCaptureNSView: NSView {
    private var reporting = TerminalMouseReporting.disabled
    private var metrics = TerminalCellMetrics.default
    private var onMouseInput: (TerminalMouseInputRequest) -> Void = { _ in }
    private var scrollAccumulator = TerminalScrollWheelAccumulator()
    private var lastMotion: MotionIdentity?
    private var trackingAreaReference: NSTrackingArea?

    override var isFlipped: Bool { true }

    func update(
        reporting: TerminalMouseReporting,
        metrics: TerminalCellMetrics,
        onMouseInput: @escaping (TerminalMouseInputRequest) -> Void
    ) {
        if self.reporting != reporting {
            scrollAccumulator.reset()
            lastMotion = nil
        }
        self.reporting = reporting
        self.metrics = metrics
        self.onMouseInput = onMouseInput
    }

    override func updateTrackingAreas() {
        if let trackingAreaReference {
            removeTrackingArea(trackingAreaReference)
        }
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
        let position = TerminalMouseCoordinateMapper.position(
            at: location,
            in: bounds.size,
            metrics: metrics
        )
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
        let position = TerminalMouseCoordinateMapper.position(
            at: location,
            in: bounds.size,
            metrics: metrics
        )
        let motion = MotionIdentity(position: position, button: button)
        if kind == .motion, motion == lastMotion {
            return true
        }
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

    private func localLocation(for event: NSEvent) -> CGPoint {
        convert(event.locationInWindow, from: nil)
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
#else
private struct PlatformTerminalPointerInputCapture: View {
    var reporting: TerminalMouseReporting
    var metrics: TerminalCellMetrics
    var onMouseInput: (TerminalMouseInputRequest) -> Void

    @State private var isDragging = false
    @State private var lastMotion: TerminalMousePosition?

    var body: some View {
        GeometryReader { proxy in
            Color.clear
                .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        let position = mapped(value.location, size: proxy.size)
                        if !isDragging {
                            isDragging = true
                            send(.press, button: .left, position: position)
                        } else if position != lastMotion {
                            send(.motion, button: .left, position: position)
                        }
                        lastMotion = position
                    }
                    .onEnded { value in
                        send(.release, button: .left, position: mapped(value.location, size: proxy.size))
                        isDragging = false
                        lastMotion = nil
                    })
        }
    }

    private func mapped(_ location: CGPoint, size: CGSize) -> TerminalMousePosition {
        TerminalMouseCoordinateMapper.position(at: location, in: size, metrics: metrics)
    }

    private func send(
        _ kind: TerminalMouseEventKind,
        button: TerminalMouseButton,
        position: TerminalMousePosition
    ) {
        onMouseInput(TerminalMouseInputRequest(
            event: TerminalMouseInputEvent(kind: kind, button: button, position: position),
            reporting: reporting
        ))
    }
}
#endif
