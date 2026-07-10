import SwiftUI
import QuillCodeTools

struct QuillCodeTerminalInteractiveOutput: View {
    var text: AttributedString
    var reporting: TerminalMouseReporting?
    var onMouseInput: (TerminalMouseInputRequest) -> Void

    var body: some View {
        Text(text)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay {
                if let reporting, reporting.isEnabled {
                    TerminalMouseCaptureOverlay(
                        reporting: reporting,
                        onMouseInput: onMouseInput
                    )
                }
            }
    }
}

enum TerminalCellMetrics {
    static let width: CGFloat = 8.4
    static let height: CGFloat = 18
}

enum TerminalMouseCoordinateMapper {
    static func position(at location: CGPoint, in size: CGSize) -> TerminalMousePosition {
        let maxColumn = max(1, Int(ceil(size.width / TerminalCellMetrics.width)))
        let maxRow = max(1, Int(ceil(size.height / TerminalCellMetrics.height)))
        return TerminalMousePosition(
            column: min(maxColumn, max(1, Int(floor(location.x / TerminalCellMetrics.width)) + 1)),
            row: min(maxRow, max(1, Int(floor(location.y / TerminalCellMetrics.height)) + 1))
        )
    }
}

private struct TerminalMouseCaptureOverlay: View {
    var reporting: TerminalMouseReporting
    var onMouseInput: (TerminalMouseInputRequest) -> Void

    @State private var isDragging = false
    @State private var lastDragPosition: TerminalMousePosition?
    @State private var lastHoverPosition: TerminalMousePosition?

    var body: some View {
        GeometryReader { proxy in
            Color.clear
                .gesture(dragGesture(in: proxy.size))
                .quillCodeOwnedGestureTarget(minHeight: TerminalCellMetrics.height, radius: 0)
                .onContinuousHover(coordinateSpace: .local) { phase in
                    handleHover(phase, size: proxy.size)
                }
                .accessibilityElement()
                .accessibilityIdentifier("quillcode-terminal-mouse-input")
                .accessibilityLabel("Interactive terminal output")
                .accessibilityHint("Pointer input is being sent to the running terminal program.")
        }
    }

    private func dragGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                let position = TerminalMouseCoordinateMapper.position(at: value.location, in: size)
                if !isDragging {
                    isDragging = true
                    send(.press, button: .left, position: position)
                } else if position != lastDragPosition {
                    send(.motion, button: .left, position: position)
                }
                lastDragPosition = position
            }
            .onEnded { value in
                let position = TerminalMouseCoordinateMapper.position(at: value.location, in: size)
                send(.release, button: .left, position: position)
                isDragging = false
                lastDragPosition = nil
            }
    }

    private func handleHover(_ phase: HoverPhase, size: CGSize) {
        guard !isDragging, reporting.trackingMode == .anyMotion else { return }
        switch phase {
        case let .active(location):
            let position = TerminalMouseCoordinateMapper.position(at: location, in: size)
            guard position != lastHoverPosition else { return }
            lastHoverPosition = position
            send(.motion, button: .none, position: position)
        case .ended:
            lastHoverPosition = nil
        }
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
