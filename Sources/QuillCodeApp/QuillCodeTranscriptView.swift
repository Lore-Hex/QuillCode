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
    /// Streaming autoscroll only pins to the bottom when the reader is already there; otherwise a
    /// "Jump to latest" chip floats rather than yanking them down. Whether the reader is AT the bottom
    /// comes from the gap between a 1pt bottom sentinel and the viewport bottom; whether a WIDENING gap
    /// was a deliberate scroll-up (vs. a chunk growing below them, or our own follow-scroll animation —
    /// both of which widen that gap identically) comes from an orthogonal signal: the content's top
    /// edge in the scroll space (the negated scroll offset), which only a scroll-up increases. Both are
    /// measured through a named coordinate space (GeometryReader + non-@Sendable `.onChange` — the
    /// macOS 14 floor rules out `.onScrollGeometryChange`, and swift-tools 6.0's @Sendable rule rules
    /// out `.onPreferenceChange`).
    @State private var isPinnedToBottom = true
    @State private var viewportHeight: CGFloat = 0
    @State private var bottomSentinelMaxY: CGFloat = 0
    /// Last sampled content-top offset; nil re-baselines the next sample (first appear + thread switch)
    /// so a fresh transcript's opening offset is never mistaken for a scroll gesture.
    @State private var lastContentTopMinY: CGFloat?
    private let bottomPinThreshold: CGFloat = 60
    private static let transcriptScrollSpace = "quillcode.transcript.scroll"
    private static let bottomSentinelID = "quillcode.transcript.bottom-sentinel"

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

    /// Re-pins the follow-scroll per streamed chunk (see ``TranscriptScrollFollow/contentSignature``).
    private var scrollContentSignature: String {
        TranscriptScrollFollow.contentSignature(for: transcript)
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
                            bottomSentinel
                        }
                        .frame(maxWidth: .infinity)
                        .padding(22)
                        .background(contentTopOffsetReader)
                    }
                    .coordinateSpace(.named(Self.transcriptScrollSpace))
                    .background(
                        GeometryReader { geometry in
                            Color.clear
                                .onChange(of: geometry.size.height, initial: true) { _, height in
                                    viewportHeight = height
                                    // A resize is never a scroll gesture: re-pin if the shorter/taller
                                    // viewport put the end back within reach, but never strand an
                                    // at-bottom reader.
                                    applyPinned(isUserScrollUp: false)
                                }
                        }
                    )
                    .quillCodeInitialBottomAnchor()
                    .overlay(alignment: .top) {
                        newTurnsPillOverlay(proxy)
                    }
                    .overlay(alignment: .bottom) {
                        jumpToLatestOverlay(proxy)
                    }
                    .onAppear {
                        scrollForReviewVisibility(review.isVisible, proxy: proxy)
                    }
                    .onChange(of: threadID) { _, _ in
                        // A different thread opens at ITS latest turn, never inheriting the previous
                        // thread's scroll-pin (codex review): otherwise switching away from a
                        // scrolled-up thread strands the new one at the top behind a Jump chip. Drop
                        // the content-offset baseline too, so the new transcript's opening offset is
                        // re-baselined instead of read as a giant scroll-up.
                        isPinnedToBottom = true
                        lastContentTopMinY = nil
                        scrollForReviewVisibility(review.isVisible, proxy: proxy)
                    }
                    .onChange(of: scrollContentSignature) { _, _ in
                        scrollToTranscriptEnd(proxy, id: scrollAnchorID)
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
                .tracking(-0.3)
                .foregroundStyle(QuillCodePalette.text)
            Text(transcript.emptySubtitle)
                .font(.callout)
                .lineSpacing(3)
                .foregroundStyle(QuillCodePalette.muted)
            starterActions
                .padding(.top, 4)
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
                    .padding(.horizontal, 13)
                    .padding(.vertical, 11)
                    .quillCodeFullRowButtonTarget(
                        minHeight: 72,
                        alignment: .center,
                        radius: QuillCodeMetrics.messageBubbleRadius
                    )
                    .quillCodeSurface(
                        fill: QuillCodePalette.panel2,
                        radius: QuillCodeMetrics.messageBubbleRadius,
                        stroke: QuillCodePalette.line,
                        shadow: false
                    )
                }
                .buttonStyle(QuillCodePressableButtonStyle())
                .accessibilityLabel(Text(action.title))
                .accessibilityHint(Text("Inserts \(action.prompt)"))
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

    private func scrollToTranscriptEnd(_ proxy: ScrollViewProxy, id: String?, force: Bool = false) {
        guard let id, !isFindPresented, !review.isVisible else { return }
        // Only follow the stream when the reader is already at the bottom; `force` lets first-open and
        // the Jump-to-latest tap override. This is what stops a streamed chunk from yanking a
        // scrolled-up reader back down.
        guard force || isPinnedToBottom else { return }
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

    /// A zero-height marker at the very end of the transcript. Its position within the scroll
    /// coordinate space, compared to the viewport height, is how we know whether the reader is at the
    /// bottom (see ``applyPinned(isUserScrollUp:)``). LazyVStack won't lay it out while scrolled far
    /// up, which is fine — `isPinnedToBottom` then correctly stays false until the reader scrolls back
    /// down (the content-offset reader keeps un-pinning live meanwhile).
    private var bottomSentinel: some View {
        Color.clear
            .frame(height: 1)
            .id(Self.bottomSentinelID)
            .background(
                GeometryReader { geometry in
                    Color.clear
                        .onChange(
                            of: geometry.frame(in: .named(Self.transcriptScrollSpace)).maxY,
                            initial: true
                        ) { _, maxY in
                            bottomSentinelMaxY = maxY
                            // The end-of-content moved (a chunk grew, or the follow-scroll ran). That
                            // is never a user scroll, so it may only RE-pin (end back within reach) —
                            // it must never un-pin an at-bottom reader mid-chunk. Un-pinning is owned
                            // solely by the content-offset signal (``contentTopOffsetReader``).
                            applyPinned(isUserScrollUp: false)
                        }
                }
            )
    }

    /// Measures the transcript content's top edge in the scroll coordinate space — the (negated)
    /// scroll offset — as the orthogonal "did the reader scroll up?" signal. Backed onto the CONTENT
    /// (not a lazy child) so it keeps reporting even when the top is scrolled far off-screen: the
    /// signal must be live the instant a reader drags up FROM the bottom, which a LazyVStack child
    /// sentinel (unlaid-out while at the bottom) could not do.
    private var contentTopOffsetReader: some View {
        GeometryReader { geometry in
            Color.clear
                .onChange(
                    of: geometry.frame(in: .named(Self.transcriptScrollSpace)).minY,
                    initial: true
                ) { _, minY in
                    applyContentTopOffsetSample(minY)
                }
        }
    }

    /// Resolve the pin against a sentinel/viewport move that is NOT a user scroll (content growth,
    /// follow-scroll, resize). Within threshold re-pins; otherwise the prior state is preserved.
    private func applyPinned(isUserScrollUp: Bool) {
        let pinned = TranscriptScrollFollow.resolvePinned(
            current: isPinnedToBottom,
            bottomSentinelMaxY: bottomSentinelMaxY,
            viewportHeight: viewportHeight,
            threshold: bottomPinThreshold,
            isUserScrollUp: isUserScrollUp
        )
        guard pinned != isPinnedToBottom else { return }
        quillCodeWithAnimation(.easeInOut(duration: 0.15), reduceMotion: reduceMotion) {
            isPinnedToBottom = pinned
        }
    }

    /// A new content-offset sample. Only a genuine scroll UP (top edge moved down past the epsilon
    /// since the last sample) may un-pin; content growth and the follow-scroll animation never do.
    /// A nil `lastContentTopMinY` (first appear / thread switch) baselines without classifying.
    private func applyContentTopOffsetSample(_ minY: CGFloat) {
        defer { lastContentTopMinY = minY }
        guard let previous = lastContentTopMinY else { return }
        let pinned = TranscriptScrollFollow.pinnedAfterScrollSample(
            current: isPinnedToBottom,
            bottomSentinelMaxY: bottomSentinelMaxY,
            viewportHeight: viewportHeight,
            threshold: bottomPinThreshold,
            contentTopMinY: minY,
            previousContentTopMinY: previous
        )
        guard pinned != isPinnedToBottom else { return }
        quillCodeWithAnimation(.easeInOut(duration: 0.15), reduceMotion: reduceMotion) {
            isPinnedToBottom = pinned
        }
    }

    @ViewBuilder
    private func jumpToLatestOverlay(_ proxy: ScrollViewProxy) -> some View {
        if !isPinnedToBottom {
            QuillCodeTranscriptJumpToLatestChip {
                isPinnedToBottom = true
                scrollToTranscriptEnd(proxy, id: scrollAnchorID, force: true)
            }
            .padding(.bottom, 12)
            .transition(.move(edge: .bottom).combined(with: .opacity))
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

private extension View {
    /// Scope the bottom anchor to the INITIAL offset only (macOS 15+); on the macOS 14 floor this is a
    /// no-op and first-open bottom position comes from the forced `.onAppear` scroll. The plain
    /// `.defaultScrollAnchor(.bottom)` re-pinned to the bottom on EVERY content-size change — one of
    /// the two causes of the streaming yank the conditional-pin logic removes.
    @ViewBuilder
    func quillCodeInitialBottomAnchor() -> some View {
        if #available(macOS 15.0, *) {
            self.defaultScrollAnchor(.bottom, for: .initialOffset)
        } else {
            self
        }
    }
}
