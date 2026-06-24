import SwiftUI
import QuillCodeCore

struct QuillCodeTerminalPaneView: View {
    var terminal: TerminalSurface
    @Binding var draft: String
    var onRun: () -> Void
    var onStop: () -> Void
    var onClear: () -> Void

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
                .controlSize(.small)
                .disabled(!terminal.canClear)
            if terminal.isRunning {
                ProgressView()
                    .controlSize(.small)
                Button("Stop", action: onStop)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(QuillCodePalette.red)
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
                .disabled(terminal.isRunning)
            Button("Run", action: onRun)
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || terminal.isRunning)
        }
    }
}
