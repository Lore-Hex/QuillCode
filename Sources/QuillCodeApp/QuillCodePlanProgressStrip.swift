import SwiftUI

/// The always-visible plan-progress rail: a slim band above the composer input showing a progress bar,
/// the "k/N" step counter, and the current step title. It sits where your eyes land when you glance
/// back at an unattended run. The parent gates its presence on a non-nil plan (so a plan-less composer
/// is byte-identical), and this view owns the visibility POLICY — full while running, a dim "ghost"
/// once the run stops (so you still read where it stalled, without shouting; the failure alarm stays
/// the top-bar hairline's job), and a low-key green when complete.
struct QuillCodePlanProgressStrip: View {
    var progress: WorkspacePlanProgress
    var reduceMotion: Bool

    private let trackWidth: CGFloat = 72
    private let trackHeight: CGFloat = 3

    var body: some View {
        HStack(spacing: 8) {
            track
            Text(progress.stepCounterLabel)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(QuillCodePalette.muted)
            Text(progress.currentStepTitle)
                .font(.caption2)
                .foregroundStyle(QuillCodePalette.muted)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .opacity(overallOpacity)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: progress.fraction)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Plan progress")
        .accessibilityValue("Step \(progress.currentStepIndex) of \(progress.totalCount): \(progress.currentStepTitle)")
        .accessibilityIdentifier("quillcode-plan-progress")
    }

    private var track: some View {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(QuillCodePalette.selection)
                .frame(width: trackWidth, height: trackHeight)
            Capsule()
                .fill(fillColor)
                .frame(width: max(0, min(trackWidth, trackWidth * progress.fraction)), height: trackHeight)
        }
        .accessibilityHidden(true)
    }

    private var fillColor: Color {
        if progress.isComplete { return QuillCodePalette.green }
        return progress.isRunning ? QuillCodePalette.blue : QuillCodePalette.muted
    }

    private var overallOpacity: Double {
        if progress.isRunning { return 1.0 }
        return progress.isComplete ? 0.5 : 0.35
    }
}
