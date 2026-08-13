import SwiftUI
import QuillCodeCore

struct QuillCodeTranscriptView: View {
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
    /// Non-nil only when the app has no TrustedRouter credential yet: the first-run connect gate
    /// replaces the project starter cards so a keyless user never reaches a composer that would
    /// silently fail. See ``TranscriptConnectPrompt``.
    var connectPrompt: TranscriptConnectPrompt? = nil
    var onStartTrustedRouterSignIn: () -> Void = {}
    var onUseDeveloperKey: () -> Void = {}
    var requiresProjectSelection = false
    var onOpenProject: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.quillCodeConfidentialAppearance) private var isConfidentialAppearance

    /// Per-thread "N new turns" bookkeeping. A `@StateObject` so it survives thread switches within
    /// this view's lifetime — the watermark for a thread you left stays put while it grows in the
    /// background, so the pill can appear when you return. See ``TranscriptNewTurnsTracker``.
    @StateObject private var newTurnsStore = QuillCodeTranscriptNewTurnsStore()
    /// Which anchor jump is currently pending, so the scroll handler can target it once.
    @State private var pendingJumpAnchorID: String?
    /// Raw geometry changes many times per trackpad gesture. Keep it outside SwiftUI's publishing
    /// state graph so only an actual pinned/unpinned transition invalidates the transcript rows.
    @StateObject private var scrollMetrics = TranscriptScrollMetrics()
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
    private let bottomPinThreshold: CGFloat = 60
    private static let transcriptScrollSpace = "quillcode.transcript.scroll"
    private static let bottomSentinelID = "quillcode.transcript.bottom-sentinel"
    /// The conversation column's readable measure. Wide enough for tool cards and the review pane's
    /// diffs, narrow enough that assistant prose stays readable (~90-100 chars at body size). The
    /// harness/DOM `.timeline` centers on the same 860px so the three surfaces agree.
    private static let contentColumnMaxWidth: CGFloat = 860

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
        guard transcript.timelineItems.isEmpty,
              !review.isVisible,
              contextBanner == nil
        else {
            return false
        }
        guard requiresProjectSelection || connectPrompt != nil else {
            return runtimeIssue == nil
        }
        return runtimeIssue == nil || runtimeIssueIsSetupRelated
    }

    private var connectPlacement: TranscriptConnectPlacement {
        TranscriptConnectPlacement.resolve(
            hasPrompt: connectPrompt != nil,
            requiresProjectSelection: requiresProjectSelection,
            emptyStateVisible: isEmptyStateVisible
        )
    }

    private var runtimeIssueIsSetupRelated: Bool {
        switch runtimeIssue?.recovery?.reason {
        case .trustedRouterSignInRequired, .developerKeyMissing:
            return true
        case .trustedRouterKeyRejected, .rateLimited, .providerUnavailable,
             .networkUnreachable, .emptyResponse, .malformedModelAction,
             .runInterrupted, .runFailed, .savedChatsUnreadable,
             .savedWorkspaceDataUnreadable, nil:
            return false
        }
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
            if connectPlacement == .banner {
                QuillCodeConnectBannerView(
                    onSignIn: onStartTrustedRouterSignIn,
                    onUseDeveloperKey: onUseDeveloperKey
                )
                .frame(maxWidth: Self.contentColumnMaxWidth)
                .padding(.horizontal, 22)
                .padding(.top, 14)
                .frame(maxWidth: .infinity)
            }
            transcriptBody
        }
        .background(isConfidentialAppearance ? QuillCodePalette.Confidential.background : QuillCodePalette.background)
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
        .onChange(of: review.isVisible) { _, isVisible in
            guard !isVisible else { return }
            // Review is a focused viewport rather than a transcript row. Reopening the transcript
            // therefore starts at its latest turn, matching the previous review-close behavior
            // without laying out every intervening row during a top-to-bottom anchor jump.
            isPinnedToBottom = true
            scrollMetrics.resetContentOffsetBaseline()
        }
    }

    @ViewBuilder
    private var transcriptBody: some View {
        Group {
            if review.isVisible {
                reviewBody
            } else if isEmptyStateVisible {
                // Two spacers CENTER the hero in the transcript void — bottom-anchoring it against
                // the composer left a large dead area above at tall windows.
                Spacer(minLength: 0)
                emptyState
                    .padding(.bottom, 20)
                Spacer(minLength: 0)
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
                            timelineItems
                            if let thinking = transcript.thinking {
                                QuillCodeThinkingView(thinking: thinking)
                                    .id(thinking.id)
                            }
                            bottomSentinel
                        }
                        // Readable measure: cap the conversation column and center it, instead of
                        // letting text run edge-to-edge at wide windows (a ~1200pt line is unreadable
                        // and user bubbles end up a screen-width away from replies). Everything —
                        // messages, tool cards, and banners share one column, so
                        // alignment contexts (trailing user bubbles) pin to the column, not the pane.
                        .frame(maxWidth: Self.contentColumnMaxWidth)
                        .padding(22)
                        .frame(maxWidth: .infinity)
                        .background(contentTopOffsetReader)
                    }
                    .coordinateSpace(.named(Self.transcriptScrollSpace))
                    .background(
                        GeometryReader { geometry in
                            Color.clear
                                .onChange(of: geometry.size.height, initial: true) { _, height in
                                    guard TranscriptScrollFollow.shouldCommitGeometrySample(
                                        height,
                                        current: scrollMetrics.viewportHeight
                                    ) else { return }
                                    scrollMetrics.viewportHeight = height
                                    // A resize is never a scroll gesture: re-pin if the shorter/taller
                                    // viewport put the end back within reach, but never strand an
                                    // at-bottom reader.
                                    applyPinned(unpinBeyondThreshold: false)
                                }
                                .onChange(of: geometry.size.width, initial: true) { oldWidth, width in
                                    guard TranscriptScrollFollow.shouldCommitGeometrySample(
                                        width,
                                        current: scrollMetrics.viewportWidth
                                    ) else { return }
                                    scrollMetrics.viewportWidth = width
                                    // Width is the layout-only input that can rewrap transcript text.
                                    // Follow it directly instead of observing content height, which
                                    // creates a scroll -> layout -> height feedback path while streaming.
                                    if oldWidth > 0 {
                                        scrollToTranscriptEnd(proxy, id: scrollAnchorID)
                                    }
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
                    .onChange(of: threadID) { _, _ in
                        // A different thread opens at ITS latest turn, never inheriting the previous
                        // thread's scroll-pin (codex review): otherwise switching away from a
                        // scrolled-up thread strands the new one at the top behind a Jump chip. Drop
                        // the content-offset baseline too, so the new transcript's opening offset is
                        // re-baselined instead of read as a giant scroll-up.
                        isPinnedToBottom = true
                        scrollMetrics.resetContentOffsetBaseline()
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
                }
            }
        }
        .background(isConfidentialAppearance ? QuillCodePalette.Confidential.background : QuillCodePalette.background)
    }

    private var reviewBody: some View {
        ScrollView {
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
            .frame(maxWidth: Self.contentColumnMaxWidth)
            .padding(22)
            .frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier("quillcode-review-viewport")
    }

    private var timelineItems: some View {
        ForEach(transcript.timelineItems) { item in
            QuillCodeTranscriptTimelineRow(
                item: item,
                isActiveFindItem: activeFindMatch?.timelineItemID == item.id
                    && !findQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                isCopied: copiedTranscriptItemID == item.id,
                retryCommand: item.message?.id == latestAssistantMessageID ? retryLastTurnCommand : nil,
                onContextCommand: onContextCommand,
                onToolCardAction: onToolCardAction,
                onCopyTranscriptItem: onCopyTranscriptItem,
                onRevertTurn: onRevertTurn,
                onUseMessageAsDraft: onUseMessageAsDraft
            )
            .equatable()
            .id(item.id)
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if requiresProjectSelection {
            QuillCodeProjectSetupView(onOpenProject: onOpenProject)
        } else if connectPlacement == .hero, let connectPrompt {
            // Not connected yet: the sign-in gate takes precedence over the starter cards (and even
            // confidential mode) — there is nothing to start until an account is connected.
            QuillCodeConnectView(
                prompt: connectPrompt,
                onSignIn: onStartTrustedRouterSignIn,
                onUseDeveloperKey: onUseDeveloperKey
            )
        } else if isConfidentialAppearance {
            confidentialEmptyState
        } else {
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
    }

    /// The confidential "you've gone private" hero — Chrome-incognito style: a large mode glyph and
    /// the mode's three guarantees, instead of the project starter cards (which would read as an
    /// invitation to share workspace context this mode deliberately withholds).
    private var confidentialEmptyState: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(QuillCodePalette.Confidential.bandFill)
                    .frame(width: 72, height: 72)
                Image(systemName: "eye.slash.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(QuillCodePalette.purple)
            }
            .accessibilityHidden(true)
            Text("This chat is confidential")
                .font(.title3.weight(.semibold))
                .tracking(-0.3)
                .foregroundStyle(QuillCodePalette.text)
            VStack(alignment: .leading, spacing: 8) {
                confidentialGuarantee("internaldrive", "Never saved — destroyed when you leave")
                confidentialGuarantee("lock.shield", "End-to-end encrypted on TrustedRouter")
                confidentialGuarantee("doc.text.magnifyingglass", "No workspace instructions or memories shared")
            }
            .padding(.top, 2)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: 620)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 22)
        .accessibilityIdentifier("quillcode-confidential-empty-state")
    }

    private func confidentialGuarantee(_ systemImage: String, _ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.callout)
                .foregroundStyle(QuillCodePalette.purple)
                .frame(width: 20)
            Text(text)
                .font(.callout)
                .foregroundStyle(QuillCodePalette.muted)
        }
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
        guard let id, !isFindPresented else { return }
        // Only follow the stream when the reader is already at the bottom; `force` lets first-open and
        // the Jump-to-latest tap override. This is what stops a streamed chunk from yanking a
        // scrolled-up reader back down.
        guard force || isPinnedToBottom else { return }
        // NOTE: this deliberately does NOT mark the thread seen. Marking seen here (it fires on
        // appear and on every scroll-anchor change, including on return to a grown thread) would
        // advance the watermark before the pill could ever evaluate — the exact bug that made the
        // pill unreachable. The watermark advances only on leaving the thread or a pill tap.
        if force {
            DispatchQueue.main.async {
                quillCodeWithAnimation(.easeOut(duration: 0.18), reduceMotion: reduceMotion) {
                    proxy.scrollTo(id, anchor: .bottom)
                }
            }
        } else {
            // Stream chunks can arrive faster than an animation completes. Starting a fresh animation
            // for every published chunk grows an unbounded transaction queue on long chats.
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                proxy.scrollTo(id, anchor: .bottom)
            }
        }
    }

    /// A zero-height marker at the very end of the transcript. Its position within the scroll
    /// coordinate space, compared to the viewport height, is how we know whether the reader is at the
    /// bottom (see ``applyPinned(unpinBeyondThreshold:)``). LazyVStack won't lay it out while scrolled far
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
                            guard TranscriptScrollFollow.shouldCommitGeometrySample(
                                maxY,
                                current: scrollMetrics.bottomSentinelMaxY
                            ) else { return }
                            scrollMetrics.bottomSentinelMaxY = maxY
                            // The end-of-content moved (a chunk grew, or the follow-scroll ran). While
                            // follow-scroll is live this may only RE-pin (end back within reach), never
                            // un-pin an at-bottom reader mid-chunk (the content-offset signal owns
                            // scroll-driven un-pinning). But when follow-scroll is SUPPRESSED (Find /
                            // review), the viewport won't catch up, so a beyond-threshold growth must
                            // un-pin here and surface the Jump chip.
                            applyPinned(unpinBeyondThreshold: isFollowScrollSuppressed)
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

    /// Follow-scroll is suppressed (`scrollToTranscriptEnd` early-returns) while Find owns the scroll
    /// position. A chunk that grows past the threshold then will NOT auto-catch-up, so
    /// the bottom-sentinel must un-pin (surface the Jump chip, honest state) rather than preserve a pin
    /// the viewport no longer reflects — otherwise closing Find strands the reader behind with no chip
    /// and the next chunk yanks them down.
    private var isFollowScrollSuppressed: Bool {
        isFindPresented
    }

    /// Resolve the pin against a sentinel/viewport move that is NOT a user scroll (content growth,
    /// follow-scroll, resize). Within threshold re-pins; beyond it, `unpinBeyondThreshold` decides
    /// whether the reader has fallen behind (e.g. growth while follow-scroll is suppressed).
    private func applyPinned(unpinBeyondThreshold: Bool) {
        let pinned = TranscriptScrollFollow.resolvePinned(
            current: isPinnedToBottom,
            bottomSentinelMaxY: scrollMetrics.bottomSentinelMaxY,
            viewportHeight: scrollMetrics.viewportHeight,
            threshold: bottomPinThreshold,
            unpinBeyondThreshold: unpinBeyondThreshold
        )
        guard pinned != isPinnedToBottom else { return }
        quillCodeWithAnimation(.easeInOut(duration: 0.15), reduceMotion: reduceMotion) {
            isPinnedToBottom = pinned
        }
    }

    /// A new content-offset sample. Only a genuine scroll UP (top edge nets down past the epsilon since
    /// the last committed baseline) may un-pin; content growth and the follow-scroll animation never
    /// do. The baseline advances only on a supra-epsilon move, so a slow scroll delivered as many tiny
    /// samples still accumulates to a scroll-up. A nil baseline (first appear / thread switch)
    /// baselines without classifying.
    private func applyContentTopOffsetSample(_ minY: CGFloat) {
        guard let previous = scrollMetrics.lastContentTopMinY else {
            scrollMetrics.lastContentTopMinY = minY
            return
        }
        let outcome = TranscriptScrollFollow.pinnedAfterScrollSample(
            current: isPinnedToBottom,
            bottomSentinelMaxY: scrollMetrics.bottomSentinelMaxY,
            viewportHeight: scrollMetrics.viewportHeight,
            threshold: bottomPinThreshold,
            contentTopMinY: minY,
            previousBaseline: previous
        )
        scrollMetrics.lastContentTopMinY = outcome.baseline
        guard outcome.pinned != isPinnedToBottom else { return }
        quillCodeWithAnimation(.easeInOut(duration: 0.15), reduceMotion: reduceMotion) {
            isPinnedToBottom = outcome.pinned
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

/// A stable, equatable boundary around one expensive transcript row. Scroll pin/geometry changes can
/// rebuild the parent view without reparsing Markdown or rebuilding unchanged tool-card previews.
private struct QuillCodeTranscriptTimelineRow: View, Equatable {
    var item: TranscriptTimelineItemSurface
    var isActiveFindItem: Bool
    var isCopied: Bool
    var retryCommand: WorkspaceCommandSurface?
    var onContextCommand: (WorkspaceCommandSurface) -> Void
    var onToolCardAction: (ToolCardActionSurface) -> Void
    var onCopyTranscriptItem: (String, String) -> Void
    var onRevertTurn: (UUID) -> Void
    var onUseMessageAsDraft: (String) -> Void

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.item == rhs.item
            && lhs.isActiveFindItem == rhs.isActiveFindItem
            && lhs.isCopied == rhs.isCopied
            && lhs.retryCommand == rhs.retryCommand
    }

    var body: some View {
        Group {
            switch item.kind {
            case .message:
                if let message = item.message {
                    QuillCodeMessageBubble(
                        message: message,
                        timelineItemID: item.id,
                        isCopied: isCopied,
                        onCopy: { onCopyTranscriptItem(item.id, message.text) },
                        onUseAsDraft: { onUseMessageAsDraft(message.text) },
                        canRetry: retryCommand != nil,
                        onRetry: {
                            if let retryCommand {
                                onContextCommand(retryCommand)
                            }
                        },
                        onRevertTurn: onRevertTurn
                    )
                }
            case .toolCard:
                if let card = item.toolCard {
                    QuillCodeToolCardView(
                        card: card,
                        isCopied: isCopied,
                        onCopy: {
                            onCopyTranscriptItem(item.id, TranscriptItemTextFormatter.text(for: card))
                        },
                        onAction: onToolCardAction
                    )
                }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(isActiveFindItem ? QuillCodePalette.blue.opacity(0.75) : Color.clear, lineWidth: 2)
        )
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
