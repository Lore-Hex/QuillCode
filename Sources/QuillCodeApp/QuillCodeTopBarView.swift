import SwiftUI

struct QuillCodeTopBarView: View {
    var topBar: TopBarSurface
    var commands: [WorkspaceCommandSurface]
    var leadingInset: CGFloat = 0
    var onCommand: (WorkspaceCommandSurface) -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            HStack(spacing: QuillCodeMetrics.controlClusterSpacing) {
                leadingNavigationSlot

                identityGroup
                    .layoutPriority(3)

                Spacer(minLength: 6)

                QuillCodeTopBarActionClusterView(
                    topBar: topBar,
                    commands: commands,
                    onCommand: onCommand
                )
                    .layoutPriority(2)
            }
            .padding(.horizontal, QuillCodeMetrics.topBarHorizontalPadding)
            .frame(minHeight: QuillCodeMetrics.topBarHeight)

            if showsActivityHairline {
                Rectangle()
                    .fill(TopBarToneColor.activityHairline(for: topBar))
                    .frame(height: 1)
                    .accessibilityHidden(true)
            }
        }
        .background(QuillCodePalette.background)
        .help(topBar.topBarHelpText)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(topBar.topBarAccessibilityLabel)
    }

    @ViewBuilder
    private var leadingNavigationSlot: some View {
        if leadingInset > 0 {
            navigationControls
                .padding(.leading, leadingNavigationPadding)
                .frame(width: leadingInset, alignment: .leading)
        } else {
            navigationControls
        }
    }

    private var identityGroup: some View {
        QuillCodeTopBarIdentityView(topBar: topBar)
    }

    private var showsActivityHairline: Bool {
        topBar.showsActivityHairline
    }

    private var leadingNavigationPadding: CGFloat {
        max(
            0,
            min(
                QuillCodeMetrics.topBarNavigationLeadingPadding,
                leadingInset - QuillCodeMetrics.minimumHitTarget * 2
            )
        )
    }

    private var navigationControls: some View {
        QuillCodeTopBarNavigationView(
            topBar: topBar,
            commands: commands,
            onCommand: onCommand
        )
    }
}
