import SwiftUI
import QuillCodePlatformUI
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
                    TerminalPointerInputCaptureView(
                        reporting: reporting,
                        onMouseInput: onMouseInput
                    )
                    .quillCodeOwnedGestureTarget(minHeight: TerminalCellMetrics.default.height, radius: 0)
                }
            }
    }
}
