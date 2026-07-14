import SwiftUI
import QuillCodeTools
import QuillComputerUseKit

struct QuillCodeExtensionsPaneView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var extensions: WorkspaceExtensionsSurface
    var onClose: () -> Void
    var onCommand: (WorkspaceCommandSurface) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if let recording = extensions.workflowRecording, recording.isRecording {
                recordingStatus(recording)
            }

            if extensions.items.isEmpty && extensions.hookItems.isEmpty {
                QuillCodePaneEmptyStateView(
                    title: extensions.emptyTitle,
                    subtitle: extensions.emptySubtitle
                )
            } else {
                extensionCards
            }
        }
        .padding(14)
        .frame(height: paneHeight)
        .background(QuillCodePalette.panel)
    }

    private var header: some View {
        HStack(spacing: QuillCodeMetrics.controlClusterSpacing) {
            Image(systemName: "puzzlepiece.extension")
                .foregroundStyle(QuillCodePalette.blue)
            VStack(alignment: .leading, spacing: 2) {
                Text(extensions.title)
                    .font(.headline)
                    .accessibilityIdentifier("quillcode-extensions-title")
                Text(extensions.subtitle)
                    .font(.caption)
                    .foregroundStyle(QuillCodePalette.muted)
            }
            Spacer()
            HStack(spacing: QuillCodeMetrics.denseControlClusterSpacing) {
                QuillCodePaneCountPill(label: "Plugins", count: extensions.pluginCount)
                QuillCodePaneCountPill(label: "Skills", count: extensions.skillCount)
                QuillCodePaneCountPill(label: "MCP", count: extensions.mcpServerCount)
                QuillCodePaneCountPill(label: "Hooks", count: extensions.hookCount)
                if extensions.availableCount > 0 {
                    QuillCodePaneCountPill(label: "Available", count: extensions.availableCount)
                }
                Menu {
                    Button("Record a skill", systemImage: "record.circle") {
                        onCommand(recordSkillCommand)
                    }
                    .quillCodePlatformMenuItemTarget(reason: Self.menuItemTargetReason)
                    .disabled(!recordSkillCommand.isEnabled)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .semibold))
                        .quillCodeIconButtonTarget()
                }
                .buttonStyle(QuillCodePressableButtonStyle())
                .menuIndicator(.hidden)
                .help("Add an extension")
                .accessibilityLabel("Add an extension")
                .accessibilityIdentifier("quillcode-extensions-add")
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .quillCodeIconButtonTarget()
                }
                .buttonStyle(QuillCodePressableButtonStyle())
                .help("Close Extensions")
                .accessibilityLabel("Close Extensions")
                .accessibilityIdentifier("quillcode-extensions-close")
            }
        }
    }

    private func recordingStatus(_ status: WorkflowRecordingStatus) -> some View {
        HStack(spacing: QuillCodeMetrics.controlClusterSpacing) {
            recordingIndicator
            VStack(alignment: .leading, spacing: 2) {
                Text(status.hasReachedDurationLimit ? "Recording limit reached" : "Recording workflow")
                    .font(.subheadline.weight(.semibold))
                Text(recordingDetail(status))
                    .font(.caption)
                    .foregroundStyle(QuillCodePalette.muted)
                    .lineLimit(2)
            }
            Spacer(minLength: 12)
            Button("Stop") {
                onCommand(stopRecordingCommand)
            }
            .buttonStyle(QuillCodeActionButtonStyle(.secondary, minWidth: 56))
            .quillCodeFormActionTarget(minWidth: 56)
            .accessibilityLabel("Stop workflow recording")
        }
        .padding(12)
        .background(QuillCodePalette.red.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(QuillCodePalette.red.opacity(0.24), lineWidth: 1)
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private func recordingDetail(_ status: WorkflowRecordingStatus) -> String {
        if status.hasReachedDurationLimit {
            return "The 30-minute capture is complete. Stop to create the skill."
        }
        return status.goal ?? "Demonstrate the workflow, then stop recording."
    }

    @ViewBuilder
    private var recordingIndicator: some View {
        let image = Image(systemName: "record.circle.fill")
            .foregroundStyle(QuillCodePalette.red)
        if reduceMotion {
            image
        } else {
            image.symbolEffect(.pulse, options: .repeating)
        }
    }

    private var paneHeight: CGFloat {
        let isEmpty = extensions.items.isEmpty && extensions.hookItems.isEmpty
        let base: CGFloat = isEmpty ? 170 : 292
        return base + (extensions.workflowRecording?.isRecording == true ? 88 : 0)
    }

    private var recordSkillCommand: WorkspaceCommandSurface {
        .workflowRecordSkill(
            isEnabled: extensions.workflowRecording != nil
                && extensions.workflowRecording?.isRecording != true
        )
    }

    private var stopRecordingCommand: WorkspaceCommandSurface {
        .workflowStopRecording(isEnabled: extensions.workflowRecording?.isRecording == true)
    }

    private static let menuItemTargetReason =
        "AppKit owns extension menu row geometry; the Add trigger carries the custom hit-target contract."
}
