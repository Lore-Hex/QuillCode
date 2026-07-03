import SwiftUI

struct QuillCodeThinkingView: View {
    var thinking: TranscriptThinkingSurface

    @State private var isTraceExpanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: QuillCodeMetrics.controlClusterSpacing) {
                    Text(thinking.title)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(QuillCodePalette.text)
                    QuillCodeThinkingDots(reduceMotion: reduceMotion)
                }
                Text(thinking.subtitle)
                    .font(.caption)
                    .foregroundStyle(QuillCodePalette.muted)
                traceDisclosure
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(QuillCodePalette.panel.opacity(0.82))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            Spacer(minLength: 80)
        }
        .frame(maxWidth: 760, alignment: .leading)
        .accessibilityIdentifier("thinking-indicator")
        .accessibilityLabel("\(thinking.title): \(thinking.subtitle)")
    }

    @ViewBuilder
    private var traceDisclosure: some View {
        if !thinking.traceLines.isEmpty {
            Button {
                quillCodeWithAnimation(.easeOut(duration: 0.16), reduceMotion: reduceMotion) {
                    isTraceExpanded.toggle()
                }
            } label: {
                HStack(spacing: QuillCodeMetrics.denseControlClusterSpacing) {
                    Image(systemName: isTraceExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2.weight(.bold))
                    Text(thinking.traceTitle)
                        .font(.caption.weight(.semibold))
                    Text("\(thinking.traceLines.count)")
                        .font(.caption2.monospacedDigit().weight(.semibold))
                        .foregroundStyle(QuillCodePalette.muted)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(QuillCodePalette.selection)
                        .clipShape(Capsule())
                }
                .foregroundStyle(QuillCodePalette.blue)
                .quillCodeCapsuleButtonTarget(minWidth: 96, alignment: .leading)
            }
            .buttonStyle(QuillCodePressableButtonStyle())
            .accessibilityIdentifier("thinking-trace-toggle")
            .accessibilityLabel("\(thinking.traceTitle), \(thinking.traceLines.count) events")
            .accessibilityValue(isTraceExpanded ? "Expanded" : "Collapsed")

            if isTraceExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(thinking.traceLines, id: \.self) { line in
                        Text(line)
                            .font(.caption2.monospaced())
                            .foregroundStyle(QuillCodePalette.muted)
                            .textSelection(.enabled)
                    }
                }
                .padding(.top, 4)
            }
        }
    }
}

private struct QuillCodeThinkingDots: View {
    var reduceMotion: Bool

    @ViewBuilder
    var body: some View {
        if reduceMotion {
            dots(activeIndex: 2)
        } else {
            TimelineView(.animation) { context in
                dots(activeIndex: Int(context.date.timeIntervalSinceReferenceDate * 2.8) % 3)
            }
        }
    }

    private func dots(activeIndex: Int) -> some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(QuillCodePalette.blue)
                    .frame(width: 5, height: 5)
                    .scaleEffect(index == activeIndex ? 1 : 0.72)
                    .opacity(index == activeIndex ? 1 : 0.42)
            }
        }
        .frame(width: 28, height: 12)
        .accessibilityHidden(true)
    }
}
