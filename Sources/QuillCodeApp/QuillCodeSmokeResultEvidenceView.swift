import SwiftUI
import QuillCodeCore

private enum SmokeResultBubbleAlignment {
    case leading
    case trailing
}

public struct QuillCodeSmokeResultEvidenceView: View {
    private var surface: WorkspaceSurface
    private var createdFilePath: String

    public init(surface: WorkspaceSurface, createdFilePath: String) {
        self.surface = surface
        self.createdFilePath = createdFilePath
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            Divider().overlay(Color.white.opacity(0.12))
            transcriptSummary
            toolSummary
            finalAnswer
            Spacer(minLength: 0)
            footer
        }
        .padding(24)
        .frame(width: 820, height: 720, alignment: .topLeading)
        .background(
            LinearGradient(
                colors: [
                    QuillCodePalette.background,
                    QuillCodePalette.sidebar.opacity(0.96)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .foregroundStyle(QuillCodePalette.text)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "sparkles")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(QuillCodePalette.blue)
                .quillCodeDecorativeIconFrame()
                .background(QuillCodePalette.blue.opacity(0.16))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                Text("Native Smoke Result")
                    .font(.title2.weight(.semibold))
                Text(topBarSummary)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(QuillCodePalette.muted)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            statusPill(label: "Passed", tint: QuillCodePalette.green)
        }
    }

    private var transcriptSummary: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Prompt")
            bubble(
                text: latestUserMessage?.text ?? surface.topBar.primaryTitle,
                alignment: .trailing,
                fill: AnyShapeStyle(LinearGradient(
                    colors: [QuillCodePalette.blue, QuillCodePalette.coral],
                    startPoint: .leading,
                    endPoint: .trailing
                ))
            )
        }
    }

    private var toolSummary: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Tool")
            HStack(alignment: .top, spacing: QuillCodeMetrics.controlClusterSpacing) {
                Image(systemName: toolIconName)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(toolTint)
                    .quillCodeDecorativeIconFrame()
                    .background(toolTint.opacity(0.14))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: QuillCodeMetrics.controlClusterSpacing) {
                        Text(latestToolCard?.title ?? "Tool")
                            .font(.headline.weight(.semibold))
                            .lineLimit(1)
                        statusPill(label: latestToolCard?.statusDisplayLabel ?? "Done", tint: toolTint)
                    }
                    Text(latestToolCard?.subtitle ?? "Completed")
                        .font(.callout)
                        .foregroundStyle(QuillCodePalette.muted)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    if let artifact = latestToolCard?.artifacts.first {
                        Text(artifact.label)
                            .font(.caption.monospaced())
                            .foregroundStyle(QuillCodePalette.blue)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
            .quillCodeSurface(
                fill: QuillCodePalette.panel,
                radius: 20,
                stroke: toolTint.opacity(0.22),
                shadow: true
            )
        }
    }

    private var finalAnswer: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Final Answer")
            bubble(
                text: latestAssistantMessage?.text ?? surface.transcript.messages.last?.text ?? "",
                alignment: .leading,
                fill: AnyShapeStyle(QuillCodePalette.panel)
            )
        }
    }

    private var footer: some View {
        HStack(spacing: QuillCodeMetrics.controlClusterSpacing) {
            Label(fileDisplayName, systemImage: "doc.text")
                .font(.caption.monospaced())
                .foregroundStyle(QuillCodePalette.muted)
                .lineLimit(1)
            Spacer()
            Text("\(surface.transcript.timelineItems.count) timeline items")
                .font(.caption.monospacedDigit())
                .foregroundStyle(QuillCodePalette.muted)
        }
    }

    private func sectionLabel(_ label: String) -> some View {
        Text(label.uppercased())
            .font(.caption.weight(.bold))
            .foregroundStyle(QuillCodePalette.muted)
            .tracking(0.8)
    }

    private func bubble(
        text: String,
        alignment: SmokeResultBubbleAlignment,
        fill: AnyShapeStyle
    ) -> some View {
        HStack {
            if alignment == .trailing {
                Spacer(minLength: 100)
            }
            Text(text)
                .font(.body)
                .foregroundStyle(QuillCodePalette.text)
                .lineLimit(6)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 15)
                .padding(.vertical, 12)
                .background(fill)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            if alignment == .leading {
                Spacer(minLength: 100)
            }
        }
    }

    private func statusPill(label: String, tint: Color) -> some View {
        Text(label)
            .font(.caption.monospacedDigit().weight(.bold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(tint.opacity(0.16))
            .clipShape(Capsule())
    }

    private var latestUserMessage: MessageSurface? {
        surface.transcript.timelineItems
            .compactMap(\.message)
            .last(where: { $0.role == .user })
    }

    private var latestAssistantMessage: MessageSurface? {
        surface.transcript.timelineItems
            .compactMap(\.message)
            .last(where: { $0.role == .assistant })
    }

    private var latestToolCard: ToolCardState? {
        surface.transcript.timelineItems
            .compactMap(\.toolCard)
            .last
    }

    private var toolTint: Color {
        switch latestToolCard?.status {
        case .done:
            return QuillCodePalette.green
        case .failed:
            return QuillCodePalette.red
        case .review:
            return QuillCodePalette.yellow
        case .queued, .running, .none:
            return QuillCodePalette.blue
        }
    }

    private var toolIconName: String {
        switch latestToolCard?.status {
        case .done:
            return "checkmark"
        case .failed:
            return "xmark"
        case .review:
            return "exclamationmark.shield"
        case .queued, .running, .none:
            return "waveform.path.ecg"
        }
    }

    private var fileDisplayName: String {
        URL(fileURLWithPath: createdFilePath).lastPathComponent
    }

    private var topBarSummary: String {
        let subtitle = surface.topBar.subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !subtitle.isEmpty else {
            return surface.topBar.primaryTitle
        }
        return "\(surface.topBar.primaryTitle) - \(subtitle)"
    }
}
