import SwiftUI
import QuillCodeCore

struct QuillCodeTerminalPaneView: View {
    var terminal: TerminalSurface
    @Binding var draft: String
    var onRun: () -> Void
    var onStop: () -> Void
    var onClear: () -> Void
    var onHistoryPrevious: () -> Void
    var onHistoryNext: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            entries
            commandLine
        }
        .padding(14)
        .frame(height: 220)
        .background(QuillCodePalette.panel)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "terminal")
                .foregroundStyle(QuillCodePalette.blue)
            Text("Terminal")
                .font(.headline)
            Text(terminal.cwdLabel)
                .font(.caption.monospaced())
                .foregroundStyle(QuillCodePalette.muted)
                .lineLimit(1)
            Spacer()
            Button("Clear", action: onClear)
                .buttonStyle(QuillCodePressableButtonStyle())
                .quillCodeTextButtonTarget(minWidth: 56)
                .disabled(!terminal.canClear)
            if terminal.isRunning {
                ProgressView()
                    .controlSize(.small)
                Button("Stop", action: onStop)
                    .buttonStyle(QuillCodeActionButtonStyle(.destructive, minWidth: 56))
            }
        }
    }

    private var entries: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                if terminal.entries.isEmpty {
                    Text(terminal.emptyTitle)
                        .font(.callout)
                        .foregroundStyle(QuillCodePalette.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 12)
                } else {
                    ForEach(terminal.entries) { entry in
                        QuillCodeTerminalEntryView(entry: entry)
                    }
                }
            }
        }
    }

    private var commandLine: some View {
        HStack(spacing: 8) {
            Text("$")
                .font(.body.monospaced())
                .foregroundStyle(QuillCodePalette.muted)
            TextField("Run command", text: $draft)
                .textFieldStyle(.roundedBorder)
                .onSubmit(onRun)
                .onKeyPress(.upArrow) {
                    guard !terminal.isRunning else { return .ignored }
                    onHistoryPrevious()
                    return .handled
                }
                .onKeyPress(.downArrow) {
                    guard !terminal.isRunning else { return .ignored }
                    onHistoryNext()
                    return .handled
                }
                .quillCodeTextEntryTarget()
                .disabled(terminal.isRunning)
            Button("Run", action: onRun)
                .buttonStyle(QuillCodePressableButtonStyle())
                .quillCodeTextButtonTarget(minWidth: 64)
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || terminal.isRunning)
        }
    }
}
