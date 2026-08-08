import SwiftUI

#if canImport(AppKit)
import AppKit
#endif

public struct QuillCodeAutofocusTextField: View {
    private var placeholder: String
    @Binding private var text: String
    private var accessibilityIdentifier: String
    private var isActive: Bool
    private var focusRequest: Int
    private var onSubmit: () -> Void
    private var onMove: (Int) -> Void
    private var onCancel: () -> Void

    public init(
        placeholder: String,
        text: Binding<String>,
        accessibilityIdentifier: String,
        isActive: Bool = true,
        focusRequest: Int = 0,
        onSubmit: @escaping () -> Void = {},
        onMove: @escaping (Int) -> Void = { _ in },
        onCancel: @escaping () -> Void = {}
    ) {
        self.placeholder = placeholder
        self._text = text
        self.accessibilityIdentifier = accessibilityIdentifier
        self.isActive = isActive
        self.focusRequest = focusRequest
        self.onSubmit = onSubmit
        self.onMove = onMove
        self.onCancel = onCancel
    }

    public var body: some View {
        #if canImport(AppKit)
        PlatformAutofocusTextField(
            placeholder: placeholder,
            text: $text,
            accessibilityIdentifier: accessibilityIdentifier,
            isActive: isActive,
            focusRequest: focusRequest,
            onSubmit: onSubmit,
            onMove: onMove,
            onCancel: onCancel
        )
        #else
        TextField(placeholder, text: $text)
            .onSubmit(onSubmit)
        #endif
    }
}

#if canImport(AppKit)
private struct PlatformAutofocusTextField: NSViewRepresentable {
    var placeholder: String
    @Binding var text: String
    var accessibilityIdentifier: String
    var isActive: Bool
    var focusRequest: Int
    var onSubmit: () -> Void
    var onMove: (Int) -> Void
    var onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> QuillCodeAutofocusNativeTextField {
        let textField = QuillCodeAutofocusNativeTextField()
        textField.delegate = context.coordinator
        textField.target = context.coordinator
        textField.action = #selector(Coordinator.submit(_:))
        textField.placeholderString = placeholder
        textField.stringValue = text
        textField.bezelStyle = .roundedBezel
        textField.setAccessibilityIdentifier(accessibilityIdentifier)
        textField.configureAutofocus(isActive: isActive, request: focusRequest)
        return textField
    }

    func updateNSView(_ nsView: QuillCodeAutofocusNativeTextField, context: Context) {
        context.coordinator.parent = self
        nsView.placeholderString = placeholder
        nsView.setAccessibilityIdentifier(accessibilityIdentifier)
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        nsView.configureAutofocus(isActive: isActive, request: focusRequest)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: PlatformAutofocusTextField

        init(_ parent: PlatformAutofocusTextField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let textField = notification.object as? NSTextField else { return }
            parent.text = textField.stringValue
        }

        func control(
            _ control: NSControl,
            textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.moveUp(_:)):
                parent.onMove(-1)
            case #selector(NSResponder.moveDown(_:)):
                parent.onMove(1)
            case #selector(NSResponder.cancelOperation(_:)):
                parent.onCancel()
            default:
                return false
            }
            return true
        }

        @objc func submit(_ sender: NSTextField) {
            parent.onSubmit()
        }
    }
}

@MainActor
private final class QuillCodeAutofocusNativeTextField: NSTextField {
    private static let maximumAttempts = 20
    private static let retryInterval = Duration.milliseconds(50)

    private var autofocusIsActive = false
    private var autofocusRequest = -1
    private var focusTask: Task<Void, Never>?

    deinit {
        focusTask?.cancel()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        scheduleFocus()
    }

    func configureAutofocus(isActive: Bool, request: Int) {
        guard autofocusIsActive != isActive || autofocusRequest != request else { return }
        autofocusIsActive = isActive
        autofocusRequest = request
        scheduleFocus()
    }

    private func scheduleFocus() {
        focusTask?.cancel()
        guard autofocusIsActive, window != nil else { return }
        focusTask = Task { @MainActor [weak self] in
            for _ in 0..<Self.maximumAttempts {
                guard !Task.isCancelled, let self, self.autofocusIsActive else { return }
                guard let window = self.window else { return }
                if window.firstResponder === self || window.firstResponder === self.currentEditor() {
                    return
                }
                if window.makeFirstResponder(self) {
                    return
                }
                try? await Task.sleep(for: Self.retryInterval)
            }
        }
    }
}
#endif
