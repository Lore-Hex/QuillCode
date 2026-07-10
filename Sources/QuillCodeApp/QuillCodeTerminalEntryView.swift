import SwiftUI
import QuillCodeCore

struct QuillCodeTerminalEntryView: View {
    var entry: TerminalCommandSurface

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                HStack(spacing: QuillCodeMetrics.controlClusterSpacing) {
                    Text("$ \(entry.command)")
                        .font(.caption.monospaced().weight(.semibold))
                        .foregroundStyle(QuillCodePalette.text)
                    if let executionContext = entry.executionContext {
                        QuillCodeExecutionContextChip(context: executionContext)
                    }
                }
                Spacer()
                Text("\(entry.statusLabel) · \(entry.exitCodeLabel)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(statusColor)
            }
            if !entry.stdout.isEmpty {
                Text(QuillCodeTerminalAttributedText.render(
                    runs: entry.stdoutRuns,
                    fallback: entry.stdout,
                    defaultForeground: QuillCodePalette.text
                ))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if !entry.stderr.isEmpty {
                Text(QuillCodeTerminalAttributedText.render(
                    runs: entry.stderrRuns,
                    fallback: entry.stderr,
                    defaultForeground: QuillCodePalette.red
                ))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(10)
        .background(QuillCodePalette.background.opacity(0.7))
        .overlay(alignment: .leading) {
            if let executionContext = entry.executionContext {
                QuillCodeExecutionRail(context: executionContext)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityLabel(accessibilityLabel)
    }

    private var statusColor: Color {
        if entry.isSuccess {
            return QuillCodePalette.green
        }
        if entry.isRunning {
            return QuillCodePalette.blue
        }
        if entry.isStopped {
            return QuillCodePalette.muted
        }
        return QuillCodePalette.red
    }

    private var accessibilityLabel: String {
        let context = entry.executionContext.map {
            ", \($0.label) \($0.detail)"
        } ?? ""
        return "\(entry.command), \(entry.statusLabel), \(entry.exitCodeLabel)\(context)"
    }
}
