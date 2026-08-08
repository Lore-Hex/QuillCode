import SwiftUI
import QuillCodeCore

struct QuillCodeToolCardActionRow: View {
    var actions: [ToolCardActionSurface]
    var onAction: (ToolCardActionSurface) -> Void

    var body: some View {
        HStack(spacing: QuillCodeMetrics.controlClusterSpacing) {
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
                        radius: QuillCodeMetrics.compactControlRadius
                    )
                    .frame(
                        maxWidth: action.style == .primary ? .infinity : 92
                    )
                    .foregroundStyle(foregroundColor(for: action.style))
                    .background(backgroundColor(for: action.style))
                    .overlay(
                        RoundedRectangle(cornerRadius: QuillCodeMetrics.compactControlRadius, style: .continuous)
                            .stroke(strokeColor(for: action.style), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: QuillCodeMetrics.compactControlRadius, style: .continuous))
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
            return QuillCodePalette.background
        case .secondary:
            return QuillCodePalette.text
        case .destructive:
            return QuillCodePalette.red
        }
    }

    private func backgroundColor(for style: ToolCardActionStyle) -> Color {
        switch style {
        case .primary:
            return QuillCodePalette.text
        case .secondary:
            return QuillCodePalette.panel3
        case .destructive:
            return QuillCodePalette.red.opacity(0.14)
        }
    }

    private func strokeColor(for style: ToolCardActionStyle) -> Color {
        switch style {
        case .primary:
            return QuillCodePalette.text
        case .secondary:
            return QuillCodePalette.lineStrong
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
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .foregroundStyle(tint)
            .background(tint.opacity(0.15))
            .overlay(
                RoundedRectangle(cornerRadius: QuillCodeMetrics.compactControlRadius, style: .continuous)
                    .stroke(tint.opacity(0.38), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: QuillCodeMetrics.compactControlRadius, style: .continuous))
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
            RoundedRectangle(cornerRadius: QuillCodeMetrics.compactControlRadius, style: .continuous)
                .stroke(tint.opacity(context.kind == .sshRemote ? 0.38 : 0.24), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: QuillCodeMetrics.compactControlRadius, style: .continuous))
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
