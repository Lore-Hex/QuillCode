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
    var onResize: (TerminalWindowSize) -> Void = { _ in }

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
        HStack(spacing: QuillCodeMetrics.controlClusterSpacing) {
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
                .accessibilityIdentifier("quillcode-terminal-clear")
            if terminal.isRunning {
                ProgressView()
                    .controlSize(.small)
                Button("Stop", action: onStop)
                    .buttonStyle(QuillCodeActionButtonStyle(.destructive, minWidth: 56))
                    .quillCodeFormActionTarget()
                    .accessibilityIdentifier("quillcode-terminal-stop")
            }
        }
        .background(TerminalWindowSizeReporter(onResize: onResize))
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
        HStack(spacing: QuillCodeMetrics.controlClusterSpacing) {
            Text("$")
                .font(.body.monospaced())
                .foregroundStyle(QuillCodePalette.muted)
            TextField(terminal.commandPlaceholder, text: $draft)
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
                .accessibilityIdentifier("quillcode-terminal-command")
            Button(terminal.commandActionTitle, action: onRun)
                .buttonStyle(QuillCodePressableButtonStyle())
                .quillCodeTextButtonTarget(minWidth: 64)
                .disabled(!canSubmitDraft)
                .accessibilityIdentifier("quillcode-terminal-action")
        }
    }

    private var canSubmitDraft: Bool {
        terminal.isRunning ? !draft.isEmpty : !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

enum TerminalWindowSizeEstimator {
    private static let cellWidth: CGFloat = 8.4
    private static let cellHeight: CGFloat = 18

    static func terminalWindowSize(for pointSize: CGSize) -> TerminalWindowSize? {
        guard pointSize.width > 0, pointSize.height > 0 else { return nil }
        return WorkspaceTerminalEngine.normalizedWindowSize(
            rows: max(1, Int(pointSize.height / cellHeight)),
            columns: max(1, Int(pointSize.width / cellWidth))
        )
    }
}

private struct TerminalWindowSizeReporter: View {
    var onResize: (TerminalWindowSize) -> Void
    @State private var lastReportedSize: TerminalWindowSize?

    var body: some View {
        GeometryReader { proxy in
            Color.clear
                .onAppear {
                    report(proxy.size)
                }
                .onChange(of: proxy.size) { _, size in
                    report(size)
                }
        }
    }

    private func report(_ pointSize: CGSize) {
        guard let windowSize = TerminalWindowSizeEstimator.terminalWindowSize(for: pointSize),
              windowSize != lastReportedSize else {
            return
        }
        lastReportedSize = windowSize
        onResize(windowSize)
    }
}
