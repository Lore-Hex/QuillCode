import SwiftUI
import QuillCodeCore

struct QuillCodeToolCardActionRow: View {
    var actions: [ToolCardActionSurface]
    var onAction: (ToolCardActionSurface) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(actions) { action in
                Button {
                    onAction(action)
                } label: {
                    Label {
                        Text(action.title)
                    } icon: {
                        if let systemImage = action.systemImage {
                            Image(systemName: systemImage)
                        }
                    }
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .padding(.horizontal, 12)
                    .quillCodeTextButtonTarget(
                        minWidth: action.style == .primary ? 118 : 72,
                        radius: QuillCodeMetrics.minimumHitTarget / 2
                    )
                    .frame(
                        maxWidth: action.style == .primary ? .infinity : 92
                    )
                    .foregroundStyle(foregroundColor(for: action.style))
                    .background(backgroundColor(for: action.style))
                    .overlay(
                        Capsule()
                            .stroke(strokeColor(for: action.style), lineWidth: 1)
                    )
                    .clipShape(Capsule())
                }
                .buttonStyle(QuillCodePressableButtonStyle())
                .help(action.title)
                .accessibilityLabel(action.title)
                .layoutPriority(action.style == .primary ? 1 : 0)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 2)
    }

    private func foregroundColor(for style: ToolCardActionStyle) -> Color {
        switch style {
        case .primary:
            return Color.white
        case .secondary:
            return QuillCodePalette.text
        case .destructive:
            return QuillCodePalette.red
        }
    }

    private func backgroundColor(for style: ToolCardActionStyle) -> Color {
        switch style {
        case .primary:
            return QuillCodePalette.blue
        case .secondary:
            return QuillCodePalette.selection.opacity(0.55)
        case .destructive:
            return QuillCodePalette.red.opacity(0.14)
        }
    }

    private func strokeColor(for style: ToolCardActionStyle) -> Color {
        switch style {
        case .primary:
            return Color.white.opacity(0.14)
        case .secondary:
            return Color.white.opacity(0.10)
        case .destructive:
            return QuillCodePalette.red.opacity(0.26)
        }
    }
}

struct QuillCodeToolStatusBadge: View {
    var label: String
    var accessibilityLabel: String
    var tint: Color
    var iconName: String

    var body: some View {
        Label(label, systemImage: iconName)
            .font(.caption.monospacedDigit().weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .foregroundStyle(tint)
            .background(tint.opacity(0.15))
            .overlay(
                Capsule()
                    .stroke(tint.opacity(0.22), lineWidth: 1)
            )
            .clipShape(Capsule())
            .help(label)
            .accessibilityLabel("Tool status \(accessibilityLabel)")
    }
}

struct QuillCodeExecutionContextChip: View {
    var context: ExecutionContextSurface

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: iconName)
                .font(.caption2.weight(.bold))
            Text(title)
                .lineLimit(1)
        }
        .font(.caption2.weight(.bold))
        .foregroundStyle(tint)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(background)
        .overlay(
            Capsule()
                .stroke(tint.opacity(context.kind == .sshRemote ? 0.38 : 0.24), lineWidth: 1)
        )
        .clipShape(Capsule())
        .accessibilityLabel("\(context.label) \(context.detail)")
    }

    private var title: String {
        switch context.kind {
        case .local:
            return context.label
        case .sshRemote:
            return "\(context.label) · \(context.detail)"
        }
    }

    private var iconName: String {
        switch context.kind {
        case .local:
            return "desktopcomputer"
        case .sshRemote:
            return "point.3.connected.trianglepath.dotted"
        }
    }

    private var tint: Color {
        switch context.kind {
        case .local:
            return QuillCodePalette.muted
        case .sshRemote:
            return QuillCodePalette.purple
        }
    }

    private var background: Color {
        switch context.kind {
        case .local:
            return Color.white.opacity(0.07)
        case .sshRemote:
            return QuillCodePalette.purple.opacity(0.16)
        }
    }
}

struct QuillCodeExecutionRail: View {
    var context: ExecutionContextSurface

    var body: some View {
        Rectangle()
            .fill(tint.opacity(context.kind == .sshRemote ? 0.78 : 0.42))
            .frame(width: 3)
            .padding(.vertical, 8)
            .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
            .padding(.leading, 1)
            .accessibilityHidden(true)
    }

    private var tint: Color {
        switch context.kind {
        case .local:
            return QuillCodePalette.muted
        case .sshRemote:
            return QuillCodePalette.purple
        }
    }
}
