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
    var onToolCardAction: (ToolCardActionSurface) -> Void
    var onAddReviewComment: (String, Int?, Int?, WorkspaceReviewLineKind?, String) -> Void
    var onCopyTranscriptItem: (String, String) -> Void
    var onUseMessageAsDraft: (String) -> Void
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
        VStack(spacing: 8) {
            Text(transcript.emptyTitle)
                .font(.title3.weight(.semibold))
                .foregroundStyle(QuillCodePalette.text)
            Text(transcript.emptySubtitle)
                .font(.callout)
                .foregroundStyle(QuillCodePalette.muted)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: 540)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 22)
    }

    private func copyText(for card: ToolCardState) -> String {
        if let outputJSON = card.outputJSON,
           !outputJSON.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return outputJSON
        }
        if let inputJSON = card.inputJSON,
           !inputJSON.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return inputJSON
        }
        return [card.title, card.subtitle]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
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
                HStack(spacing: 8) {
                    Text(thinking.title)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(QuillCodePalette.text)
                    QuillCodeThinkingDots(reduceMotion: reduceMotion)
                }
                Text(thinking.subtitle)
                    .font(.caption)
                    .foregroundStyle(QuillCodePalette.muted)
                if !thinking.traceLines.isEmpty {
                    DisclosureGroup(isExpanded: $isTraceExpanded) {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(thinking.traceLines, id: \.self) { line in
                                Text(line)
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(QuillCodePalette.muted)
                                    .textSelection(.enabled)
                            }
                        }
                        .padding(.top, 4)
                    } label: {
                        Text(thinking.traceTitle)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(QuillCodePalette.blue)
                    }
                    .tint(QuillCodePalette.blue)
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
