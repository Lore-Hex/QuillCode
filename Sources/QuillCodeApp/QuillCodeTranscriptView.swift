import SwiftUI
import QuillCodeCore

struct QuillCodeTranscriptView: View {
    private static let reviewAnchorID = "quillcode-review-pane-anchor"

    var transcript: TranscriptSurface
    /// The currently selected thread, so the "N new turns" watermark is tracked per thread and a
    /// thread that grew in the background shows its pill on return. `nil` for the empty/no-thread
    /// state (no pill).
    var threadID: UUID?
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
    var onCloseReview: () -> Void
    var onReviewScopeChange: (WorkspaceReviewSelection) -> Void
    var onReviewAction: (WorkspaceReviewActionSurface) -> Void
    var onPullRequestReviewThreadAction: (WorkspacePullRequestReviewThreadActionSurface) -> Void
    var onPullRequestReviewThreadReply: (WorkspacePullRequestReviewThreadReplyRequest) -> Void
    var onPullRequestReviewDraftChange: (WorkspacePullRequestReviewDraftSurface) -> Void
    var onCancelPullRequestReviewDraft: () -> Void
    var onSubmitPullRequestReviewDraft: () -> Void
    var onToolCardAction: (ToolCardActionSurface) -> Void
    var onAddReviewComment: (String, Int?, Int?, WorkspaceReviewLineKind?, String) -> Void
    var onCopyTranscriptItem: (String, String) -> Void
    var onRevertTurn: (UUID) -> Void = { _ in }
    var onUseMessageAsDraft: (String) -> Void
    var onSubmitStarterAction: (String) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Per-thread "N new turns" bookkeeping. A `@StateObject` so it survives thread switches within
    /// this view's lifetime — the watermark for a thread you left stays put while it grows in the
    /// background, so the pill can appear when you return. See ``TranscriptNewTurnsTracker``.
    @StateObject private var newTurnsStore = QuillCodeTranscriptNewTurnsStore()
    /// Which anchor jump is currently pending, so the scroll handler can target it once.
    @State private var pendingJumpAnchorID: String?

    private var findMatches: [QuillCodeTranscriptFindMatch] {
        QuillCodeTranscriptFindMatch.matches(in: transcript, query: findQuery)
    }

    private var navigationAnchors: TranscriptNavigationAnchors {
        TranscriptNavigationAnchors.derive(from: transcript)
    }

    private var newTurnsPill: TranscriptNewTurnsPill? {
        newTurnsStore.pill(for: threadID, transcript: transcript)
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
            transcriptBody
        }
        .background(QuillCodePalette.background)
        // The "N new turns" watermark bookkeeping lives on this STABLE parent — not inside the
        // empty-state-gated transcript subtree, which SwiftUI tears down (so its .onChange would
        // never fire) whenever the selected thread's transcript is empty, e.g. right after New
        // Chat. Advancing the outgoing thread's watermark on every thread switch (including New
        // Chat, and including when either transcript is empty) is what lets a background-grown
        // thread show its pill on return. Mirrors the harness's newChat()/selectThread() → mark-seen.
        .onAppear {
            newTurnsStore.observe(threadID: threadID, transcript: transcript)
        }
        .onChange(of: threadID) { oldThreadID, newThreadID in
            newTurnsStore.leave(threadID: oldThreadID)
            newTurnsStore.observe(threadID: newThreadID, transcript: transcript)
        }
        .onChange(of: scrollAnchorID) { _, _ in
            // Record the foreground thread's current tail (does not move the acknowledged
            // watermark) as it grows while the user watches.
            newTurnsStore.observe(threadID: threadID, transcript: transcript)
        }
    }

    @ViewBuilder
    private var transcriptBody: some View {
        Group {
            if isEmptyStateVisible {
                Spacer(minLength: 0)
                emptyState
                    .padding(.bottom, 20)
            } else {
                ScrollViewReader { proxy in
                    QuillCodeTranscriptJumpBar(
                        anchors: navigationAnchors,
                        onJumpToLastError: { jump(to: navigationAnchors.lastErrorAnchorID) },
                        onJumpToLastDiff: { jump(to: navigationAnchors.lastDiffAnchorID) }
                    )
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
                                    onClose: onCloseReview,
                                    onReviewScopeChange: onReviewScopeChange,
                                    onReviewAction: onReviewAction,
                                    onPullRequestReviewThreadAction: onPullRequestReviewThreadAction,
                                    onPullRequestReviewThreadReply: onPullRequestReviewThreadReply,
                                    onPullRequestReviewDraftChange: onPullRequestReviewDraftChange,
                                    onCancelPullRequestReviewDraft: onCancelPullRequestReviewDraft,
                                    onSubmitPullRequestReviewDraft: onSubmitPullRequestReviewDraft,
                                    onAddReviewComment: onAddReviewComment
                                )
                                .id(Self.reviewAnchorID)
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
                    .overlay(alignment: .top) {
                        newTurnsPillOverlay(proxy)
                    }
                    .onAppear {
                        scrollForReviewVisibility(review.isVisible, proxy: proxy)
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
                    .onChange(of: pendingJumpAnchorID) { _, id in
                        scrollToPendingJump(proxy, id: id)
                    }
                    .onChange(of: review.isVisible) { _, isVisible in
                        scrollForReviewVisibility(isVisible, proxy: proxy)
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
                        onRevertTurn: onRevertTurn
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
        LazyVGrid(columns: starterActionColumns, spacing: QuillCodeMetrics.controlClusterSpacing) {
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

    @ViewBuilder
    private func newTurnsPillOverlay(_ proxy: ScrollViewProxy) -> some View {
        if let pill = newTurnsPill {
            QuillCodeTranscriptNewTurnsPill(pill: pill) {
                // Tapping the pill acknowledges the new turns (dismisses the pill) and jumps to
                // the first unseen item.
                newTurnsStore.markSeen(threadID: threadID, transcript: transcript)
                jump(to: pill.firstUnseenItemID)
            }
            .padding(.top, 10)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    /// Request a scroll to a specific timeline anchor. A `nil` id (no error/diff turn) is a
    /// graceful no-op so the disabled affordance can still call through safely.
    private func jump(to anchorID: String?) {
        guard let anchorID else { return }
        // Toggle through nil first so repeated jumps to the same anchor still fire onChange.
        pendingJumpAnchorID = nil
        DispatchQueue.main.async {
            pendingJumpAnchorID = anchorID
        }
    }

    private func scrollToPendingJump(_ proxy: ScrollViewProxy, id: String?) {
        guard let id else { return }
        quillCodeWithAnimation(.easeInOut(duration: 0.2), reduceMotion: reduceMotion) {
            proxy.scrollTo(id, anchor: .center)
        }
    }

    private func scrollToTranscriptEnd(_ proxy: ScrollViewProxy, id: String?) {
        guard let id, !isFindPresented, !review.isVisible else { return }
        // NOTE: this deliberately does NOT mark the thread seen. Marking seen here (it fires on
        // appear and on every scroll-anchor change, including on return to a grown thread) would
        // advance the watermark before the pill could ever evaluate — the exact bug that made the
        // pill unreachable. The watermark advances only on leaving the thread or a pill tap.
        DispatchQueue.main.async {
            quillCodeWithAnimation(.easeOut(duration: 0.18), reduceMotion: reduceMotion) {
                proxy.scrollTo(id, anchor: .bottom)
            }
        }
    }

    private func scrollForReviewVisibility(_ isVisible: Bool, proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            quillCodeWithAnimation(.easeOut(duration: 0.18), reduceMotion: reduceMotion) {
                if isVisible {
                    proxy.scrollTo(Self.reviewAnchorID, anchor: .top)
                } else if let scrollAnchorID {
                    proxy.scrollTo(scrollAnchorID, anchor: .bottom)
                }
            }
        }
    }

    private var starterActionColumns: [GridItem] {
        [
            GridItem(
                .adaptive(minimum: 156),
                spacing: QuillCodeMetrics.controlClusterSpacing
            )
        ]
    }
}
