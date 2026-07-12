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

public struct TerminalInputCaptureView: View {
    private var reporting: TerminalMouseReporting
    private var keyboardMode: TerminalKeyboardMode?
    private var metrics: TerminalCellMetrics
    private var onMouseInput: (TerminalMouseInputRequest) -> Void
    private var onKeyboardInput: (TerminalKeyboardInputRequest) -> Void

    public init(
        reporting: TerminalMouseReporting,
        keyboardMode: TerminalKeyboardMode? = nil,
        metrics: TerminalCellMetrics = .default,
        onMouseInput: @escaping (TerminalMouseInputRequest) -> Void,
        onKeyboardInput: @escaping (TerminalKeyboardInputRequest) -> Void = { _ in }
    ) {
        self.reporting = reporting
        self.keyboardMode = keyboardMode
        self.metrics = metrics
        self.onMouseInput = onMouseInput
        self.onKeyboardInput = onKeyboardInput
    }

    public var body: some View {
        PlatformTerminalInputCapture(
            reporting: reporting,
            keyboardMode: keyboardMode,
            metrics: metrics,
            onMouseInput: onMouseInput,
            onKeyboardInput: onKeyboardInput
        )
        .accessibilityElement()
        .accessibilityIdentifier("quillcode-terminal-input")
        .accessibilityLabel("Interactive terminal output")
        .accessibilityHint("Click to focus. Keyboard, pointer, and scrolling input go to the terminal program.")
    }
}

#if canImport(AppKit)
private struct PlatformTerminalInputCapture: NSViewRepresentable {
    var reporting: TerminalMouseReporting
    var keyboardMode: TerminalKeyboardMode?
    var metrics: TerminalCellMetrics
    var onMouseInput: (TerminalMouseInputRequest) -> Void
    var onKeyboardInput: (TerminalKeyboardInputRequest) -> Void

    func makeNSView(context: Context) -> TerminalInputCaptureNSView {
        let view = TerminalInputCaptureNSView()
        update(view)
        return view
    }

    func updateNSView(_ view: TerminalInputCaptureNSView, context: Context) {
        update(view)
    }

    private func update(_ view: TerminalInputCaptureNSView) {
        view.update(
            reporting: reporting,
            keyboardMode: keyboardMode,
            metrics: metrics,
            onMouseInput: onMouseInput,
            onKeyboardInput: onKeyboardInput
        )
    }
}
#else
private struct PlatformTerminalInputCapture: View {
    var reporting: TerminalMouseReporting
    var keyboardMode: TerminalKeyboardMode?
    var metrics: TerminalCellMetrics
    var onMouseInput: (TerminalMouseInputRequest) -> Void
    var onKeyboardInput: (TerminalKeyboardInputRequest) -> Void

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
                            send(.press, position: position)
                        } else if position != lastMotion {
                            send(.motion, position: position)
                        }
                        lastMotion = position
                    }
                    .onEnded { value in
                        send(.release, position: mapped(value.location, size: proxy.size))
                        isDragging = false
                        lastMotion = nil
                    })
        }
    }

    private func mapped(_ location: CGPoint, size: CGSize) -> TerminalMousePosition {
        TerminalMouseCoordinateMapper.position(at: location, in: size, metrics: metrics)
    }

    private func send(_ kind: TerminalMouseEventKind, position: TerminalMousePosition) {
        onMouseInput(TerminalMouseInputRequest(
            event: TerminalMouseInputEvent(kind: kind, button: .left, position: position),
            reporting: reporting
        ))
    }
}
#endif
