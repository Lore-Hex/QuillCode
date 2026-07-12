import SwiftUI

struct QuillCodeTopBarActionClusterView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var topBar: TopBarSurface
    var commands: [WorkspaceCommandSurface]
    var onCommand: (WorkspaceCommandSurface) -> Void

    var body: some View {
        HStack(spacing: QuillCodeMetrics.controlClusterSpacing) {
            if let handoffCommand {
                handoffButton(handoffCommand)
            }
            if let activeStopCommand {
                stopButton(activeStopCommand)
                    .transition(reduceMotion ? .identity : .opacity.combined(with: .scale(scale: 0.96)))
            }
            commandMenu
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: activeStopCommand?.id)
    }

    private var overflowCommands: [WorkspaceCommandSurface] {
        TopBarOverflowCommandCatalog.commands(
            from: commands,
            showsComputerUseSetup: topBar.showsComputerUseSetup
        )
    }

    private var activeStopCommand: WorkspaceCommandSurface? {
        commands.first { $0.id == "stop-all" && $0.isEnabled }
    }

    private var handoffCommand: WorkspaceCommandSurface? {
        commands.first { $0.id == WorkspaceCommandAction.threadHandoff.rawValue && $0.isEnabled }
    }

    private func handoffButton(_ command: WorkspaceCommandSurface) -> some View {
        Button {
            onCommand(command)
        } label: {
            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(QuillCodePalette.muted)
                .quillCodeIconButtonTarget()
        }
        .buttonStyle(QuillCodePressableButtonStyle())
        .help(command.title)
        .accessibilityLabel(command.title)
        .accessibilityIdentifier("quillcode-top-bar-handoff")
    }

    private func stopButton(_ command: WorkspaceCommandSurface) -> some View {
        Button {
            onCommand(command)
        } label: {
            HStack(spacing: QuillCodeMetrics.denseControlClusterSpacing) {
                Image(systemName: "stop.fill")
                    .font(.caption.weight(.bold))
                    .accessibilityHidden(true)
                Text("Stop")
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(Color.white)
            .padding(.horizontal, 12)
            .quillCodeTextButtonTarget(minWidth: 64, radius: QuillCodeMetrics.minimumHitTarget / 2)
            .background(QuillCodePalette.red.opacity(0.90))
            .overlay {
                Capsule().stroke(Color.white.opacity(0.16), lineWidth: 1)
            }
            .clipShape(Capsule())
        }
        .buttonStyle(QuillCodePressableButtonStyle())
        .help("Stop active work")
        .accessibilityLabel("Stop active work")
        .accessibilityIdentifier("quillcode-top-bar-stop")
    }

    private var commandMenu: some View {
        Menu {
            ForEach(overflowCommands) { command in
                Button {
                    onCommand(command)
                } label: {
                    if let shortcut = command.shortcut {
                        Text("\(command.title)  \(shortcut)")
                    } else {
                        Text(command.title)
                    }
                }
                .quillCodePlatformMenuItemTarget(reason: Self.menuItemTargetReason)
                .disabled(!command.isEnabled)
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(QuillCodePalette.muted)
                .quillCodeIconButtonTarget()
        }
        .buttonStyle(QuillCodePressableButtonStyle())
        .help("More")
        .accessibilityLabel("More workspace actions")
        .accessibilityIdentifier("quillcode-top-bar-overflow")
    }

    private static let menuItemTargetReason =
        "AppKit owns top-bar overflow menu row geometry; the overflow trigger carries the custom hit-target contract."
}
