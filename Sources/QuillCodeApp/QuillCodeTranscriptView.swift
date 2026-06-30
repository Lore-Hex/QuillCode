import SwiftUI
import QuillCodeCore

struct QuillCodeTranscriptView: View {
    var transcript: TranscriptSurface
    var contextBanner: ContextBannerSurface?
    var runtimeIssue: RuntimeIssueSurface?
    var review: WorkspaceReviewSurface
    var retryLastTurnCommand: WorkspaceCommandSurface?
    @Binding var isFindPresented: Bool
    @Binding var findQuery: String
    @Binding var activeFindIndex: Int
    var copiedTranscriptItemID: String?
    var onContextCommand: (WorkspaceCommandSurface) -> Void
    var onRuntimeIssueAction: (() -> Void)?
    var onReviewAction: (WorkspaceReviewActionSurface) -> Void
    var onPullRequestReviewThreadAction: (WorkspacePullRequestReviewThreadActionSurface) -> Void
    var onPullRequestReviewThreadReply: (WorkspacePullRequestReviewThreadReplyRequest) -> Void
    var onPullRequestReviewDraftChange: (WorkspacePullRequestReviewDraftSurface) -> Void
    var onCancelPullRequestReviewDraft: () -> Void
    var onSubmitPullRequestReviewDraft: () -> Void
    var onToolCardAction: (ToolCardActionSurface) -> Void
    var onAddReviewComment: (String, Int?, Int?, WorkspaceReviewLineKind?, String) -> Void
    var onCopyTranscriptItem: (String, String) -> Void
    var onUseMessageAsDraft: (String) -> Void
    var onSubmitStarterAction: (String) -> Void
    var onMessageFeedback: (UUID, MessageFeedbackValue) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var findMatches: [QuillCodeTranscriptFindMatch] {
        QuillCodeTranscriptFindMatch.matches(in: transcript, query: findQuery)
    }

    private var activeFindMatch: QuillCodeTranscriptFindMatch? {
        guard !findMatches.isEmpty else { return nil }
        let boundedIndex = min(max(activeFindIndex, 0), findMatches.count - 1)
        return findMatches[boundedIndex]
    }

    private var latestAssistantMessageID: UUID? {
        transcript.timelineItems
            .compactMap(\.message)
            .last(where: { $0.role == .assistant })?
            .id
    }

    private var isEmptyStateVisible: Bool {
        transcript.timelineItems.isEmpty && !review.isVisible && contextBanner == nil && runtimeIssue == nil
    }

    private var scrollAnchorID: String? {
        transcript.thinking?.id ?? transcript.timelineItems.last?.id
    }

    var body: some View {
        VStack(spacing: 0) {
            if isFindPresented {
                QuillCodeTranscriptFindBar(
                    query: $findQuery,
                    activeIndex: activeFindIndex,
                    matchCount: findMatches.count,
                    onPrevious: selectPreviousFindMatch,
                    onNext: selectNextFindMatch,
                    onClose: closeFind
                )
                Divider()
            }
            if isEmptyStateVisible {
                Spacer(minLength: 0)
                emptyState
                    .padding(.bottom, 20)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 14) {
                            if let contextBanner {
                                QuillCodeContextBannerView(
                                    banner: contextBanner,
                                    onCommand: onContextCommand
                                )
                            }
                            if let runtimeIssue {
                                QuillCodeRuntimeIssueView(
                                    issue: runtimeIssue,
                                    onAction: onRuntimeIssueAction
                                )
                                .frame(maxWidth: 760, alignment: .leading)
                            }
                            if review.isVisible {
                                QuillCodeReviewPaneView(
                                    review: review,
                                    onReviewAction: onReviewAction,
                                    onPullRequestReviewThreadAction: onPullRequestReviewThreadAction,
                                    onPullRequestReviewThreadReply: onPullRequestReviewThreadReply,
                                    onPullRequestReviewDraftChange: onPullRequestReviewDraftChange,
                                    onCancelPullRequestReviewDraft: onCancelPullRequestReviewDraft,
                                    onSubmitPullRequestReviewDraft: onSubmitPullRequestReviewDraft,
                                    onAddReviewComment: onAddReviewComment
                                )
                            }
                            timelineItems
                            if let thinking = transcript.thinking {
                                QuillCodeThinkingView(thinking: thinking)
                                    .id(thinking.id)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(22)
                    }
                    .defaultScrollAnchor(.bottom)
                    .onAppear {
                        scrollToTranscriptEnd(proxy, id: scrollAnchorID)
                    }
                    .onChange(of: scrollAnchorID) { _, id in
                        scrollToTranscriptEnd(proxy, id: id)
                    }
                    .onChange(of: activeFindIndex) { _, _ in
                        scrollToActiveFindMatch(proxy)
                    }
                    .onChange(of: findQuery) { _, _ in
                        activeFindIndex = 0
                        scrollToActiveFindMatch(proxy)
                    }
                    .onChange(of: isFindPresented) { _, isPresented in
                        if isPresented {
                            scrollToActiveFindMatch(proxy)
                        }
                    }
                }
            }
        }
        .background(QuillCodePalette.background)
    }

    private var timelineItems: some View {
        ForEach(transcript.timelineItems) { item in
            timelineItem(item)
        }
    }

    @ViewBuilder
    private func timelineItem(_ item: TranscriptTimelineItemSurface) -> some View {
        let isActiveFindItem = activeFindMatch?.timelineItemID == item.id
            && !findQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        Group {
            switch item.kind {
            case .message:
                if let message = item.message {
                    QuillCodeMessageBubble(
                        message: message,
                        timelineItemID: item.id,
                        isCopied: copiedTranscriptItemID == item.id,
                        onCopy: {
                            onCopyTranscriptItem(item.id, message.text)
                        },
                        onUseAsDraft: {
                            onUseMessageAsDraft(message.text)
                        },
                        canRetry: message.id == latestAssistantMessageID && retryLastTurnCommand != nil,
                        onRetry: {
                            if let retryLastTurnCommand {
                                onContextCommand(retryLastTurnCommand)
                            }
                        },
                        onFeedback: { value in
                            onMessageFeedback(message.id, value)
                        }
                    )
                }
            case .toolCard:
                if let card = item.toolCard {
                    QuillCodeToolCardView(
                        card: card,
                        isCopied: copiedTranscriptItemID == item.id,
                        onCopy: {
                            onCopyTranscriptItem(item.id, copyText(for: card))
                        },
                        onAction: { action in
                            onToolCardAction(action)
                        }
                    )
                }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(isActiveFindItem ? QuillCodePalette.blue.opacity(0.75) : Color.clear, lineWidth: 2)
        )
        .id(item.id)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Text(transcript.emptyTitle)
                .font(.title3.weight(.semibold))
                .foregroundStyle(QuillCodePalette.text)
            Text(transcript.emptySubtitle)
                .font(.callout)
                .foregroundStyle(QuillCodePalette.muted)
            starterActions
                .padding(.top, 2)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: 620)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 22)
    }

    private var starterActions: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 156), spacing: QuillCodeMetrics.controlClusterSpacing)], spacing: QuillCodeMetrics.controlClusterSpacing) {
            ForEach(transcript.emptyStarterActions) { action in
                Button {
                    onSubmitStarterAction(action.prompt)
                } label: {
                    VStack(spacing: 3) {
                        Text(action.title)
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(QuillCodePalette.text)
                        Text(action.subtitle)
                            .font(.caption)
                            .foregroundStyle(QuillCodePalette.muted)
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .quillCodeFullRowButtonTarget(
                        minHeight: 72,
                        alignment: .center,
                        radius: 14
                    )
                    .quillCodeSurface(
                        fill: QuillCodePalette.panel.opacity(0.62),
                        radius: 14,
                        stroke: Color.white.opacity(0.08),
                        shadow: false
                    )
                }
                .buttonStyle(QuillCodePressableButtonStyle())
                .accessibilityLabel(Text(action.title))
                .accessibilityHint(Text("Runs \(action.prompt)"))
            }
        }
        .frame(maxWidth: 620)
    }

    private func copyText(for card: ToolCardState) -> String {
        TranscriptItemTextFormatter.text(for: card)
    }

    private func selectPreviousFindMatch() {
        guard !findMatches.isEmpty else { return }
        activeFindIndex = (activeFindIndex - 1 + findMatches.count) % findMatches.count
    }

    private func selectNextFindMatch() {
        guard !findMatches.isEmpty else { return }
        activeFindIndex = (activeFindIndex + 1) % findMatches.count
    }

    private func closeFind() {
        isFindPresented = false
        findQuery = ""
        activeFindIndex = 0
    }

    private func scrollToActiveFindMatch(_ proxy: ScrollViewProxy) {
        guard isFindPresented, let activeFindMatch else { return }
        DispatchQueue.main.async {
            quillCodeWithAnimation(.easeInOut(duration: 0.18), reduceMotion: reduceMotion) {
                proxy.scrollTo(activeFindMatch.timelineItemID, anchor: .center)
            }
        }
    }

    private func scrollToTranscriptEnd(_ proxy: ScrollViewProxy, id: String?) {
        guard let id, !isFindPresented else { return }
        DispatchQueue.main.async {
            quillCodeWithAnimation(.easeOut(duration: 0.18), reduceMotion: reduceMotion) {
                proxy.scrollTo(id, anchor: .bottom)
            }
        }
    }
}

private struct QuillCodeThinkingView: View {
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
