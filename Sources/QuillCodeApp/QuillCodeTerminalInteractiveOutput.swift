import SwiftUI
import QuillCodePlatformUI
import QuillCodeTools

struct QuillCodeTerminalInteractiveOutput: View {
    var text: AttributedString
    var reporting: TerminalMouseReporting?
    var keyboardMode: TerminalKeyboardMode?
    var onMouseInput: (TerminalMouseInputRequest) -> Void
    var onKeyboardInput: (TerminalKeyboardInputRequest) -> Void

    var body: some View {
        Text(text)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay {
                if keyboardMode != nil || reporting?.isEnabled == true {
                    TerminalInputCaptureView(
                        reporting: reporting ?? .disabled,
                        keyboardMode: keyboardMode,
                        onMouseInput: onMouseInput,
                        onKeyboardInput: onKeyboardInput
                    )
                    .quillCodeOwnedGestureTarget(minHeight: TerminalCellMetrics.default.height, radius: 0)
                }
            }
    }
}
