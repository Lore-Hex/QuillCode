import SwiftUI
import QuillCodeCore

struct QuillCodeBrowserPaneView: View {
    var browser: BrowserSurface
    @Binding var addressDraft: String
    var onOpen: () -> Void
    var onOpenSession: (() -> Void)?
    var onAddComment: (String) -> Void
    var onCommand: (String) -> Void

    @State private var commentDraft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            navigationBar
            pageSummary
            commentInput
            comments
        }
        .padding(14)
        .frame(height: browser.snapshot == nil ? 260 : 300)
        .background(QuillCodePalette.panel)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "globe")
                .foregroundStyle(QuillCodePalette.blue)
            Text("Browser")
                .font(.headline)
            Text(browser.statusLabel)
                .font(.caption)
                .foregroundStyle(QuillCodePalette.muted)
            Spacer()
        }
    }

    private var navigationBar: some View {
        HStack(spacing: 8) {
            browserNavigationButton(
                systemName: "chevron.left",
                label: "Back",
                isEnabled: browser.canGoBack
            ) {
                onCommand("browser-back")
            }
            browserNavigationButton(
                systemName: "chevron.right",
                label: "Forward",
                isEnabled: browser.canGoForward
            ) {
                onCommand("browser-forward")
            }
            browserNavigationButton(
                systemName: "arrow.clockwise",
                label: "Reload",
                isEnabled: browser.canReload
            ) {
                onCommand("browser-reload")
            }
            TextField("localhost:3000, docs/page.html, or https://example.com", text: $addressDraft)
                .textFieldStyle(.roundedBorder)
                .onSubmit(onOpen)
                .frame(minHeight: QuillCodeMetrics.minimumHitTarget)
            Button("Open", action: onOpen)
                .quillCodeTextButtonTarget()
                .disabled(addressDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            if let onOpenSession {
                Button("Session", action: onOpenSession)
                    .quillCodeTextButtonTarget(minWidth: 84)
                    .disabled(!browser.canOpen && browser.currentURL == nil)
                    .help("Open a visible browser session using QuillCode's persistent browser profile.")
            }
        }
    }

    @ViewBuilder
    private var pageSummary: some View {
        if let currentURL = browser.currentURL {
            currentPageSummary(currentURL: currentURL)
        } else {
            emptyPageSummary
        }
    }

    private func currentPageSummary(currentURL: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(browser.title)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                if let snapshot = browser.snapshot {
                    browserBadge(snapshot.sourceLabel, tint: QuillCodePalette.blue)
                    browserBadge(
                        snapshot.inspectionDepthLabel,
                        tint: browserInspectionTint(snapshot.inspectionDepth)
                    )
                }
            }
            Text(currentURL)
                .font(.caption.monospaced())
                .foregroundStyle(QuillCodePalette.muted)
                .lineLimit(1)
            snapshotSummary
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .quillCodeSurface(
            fill: QuillCodePalette.background.opacity(0.7),
            radius: 20,
            stroke: Color.white.opacity(0.08),
            shadow: false
        )
    }

    @ViewBuilder
    private var snapshotSummary: some View {
        if let snapshot = browser.snapshot {
            Text(snapshot.summary)
                .font(.caption)
                .foregroundStyle(QuillCodePalette.text)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 6)], alignment: .leading, spacing: 6) {
                ForEach(snapshot.details, id: \.self) { detail in
                    Text(detail)
                        .font(.caption2.monospaced())
                        .foregroundStyle(QuillCodePalette.muted)
                        .lineLimit(1)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(QuillCodePalette.panel.opacity(0.9))
                        .clipShape(Capsule())
                }
            }
            if !snapshot.outline.isEmpty {
                pageOutline(snapshot.outline)
            }
            if let textSnippet = snapshot.textSnippet {
                Text(textSnippet)
                    .font(.caption2)
                    .foregroundStyle(QuillCodePalette.muted)
                    .lineLimit(4)
            }
        } else {
            Text("Ready for page inspection.")
                .font(.caption)
                .foregroundStyle(QuillCodePalette.muted)
        }
    }

    private func pageOutline(_ outline: [String]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Page outline")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(QuillCodePalette.muted)
            ForEach(outline.prefix(8), id: \.self) { item in
                Text(item)
                    .font(.caption2)
                    .foregroundStyle(QuillCodePalette.text)
                    .lineLimit(1)
            }
        }
    }

    private var emptyPageSummary: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(browser.emptyTitle)
                .font(.callout.weight(.semibold))
            Text(browser.emptySubtitle)
                .font(.caption)
                .foregroundStyle(QuillCodePalette.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var commentInput: some View {
        HStack(spacing: 8) {
            TextField("Add browser comment", text: $commentDraft)
                .textFieldStyle(.roundedBorder)
                .disabled(browser.currentURL == nil)
                .onSubmit(addComment)
                .frame(minHeight: QuillCodeMetrics.minimumHitTarget)
            Button("Comment", action: addComment)
                .quillCodeTextButtonTarget(minWidth: 92)
                .disabled(browser.currentURL == nil || commentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    @ViewBuilder
    private var comments: some View {
        if !browser.comments.isEmpty {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(browser.comments) { comment in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(comment.text)
                                .font(.caption)
                                .lineLimit(2)
                            Text(comment.url)
                                .font(.caption2.monospaced())
                                .foregroundStyle(QuillCodePalette.muted)
                                .lineLimit(1)
                        }
                        .padding(8)
                        .frame(width: 220, alignment: .leading)
                        .quillCodeSurface(
                            fill: QuillCodePalette.background.opacity(0.7),
                            radius: 18,
                            stroke: Color.white.opacity(0.08),
                            shadow: false
                        )
                    }
                }
            }
        }
    }

    private func browserNavigationButton(
        systemName: String,
        label: String,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .quillCodeIconButtonTarget()
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(!isEnabled)
        .accessibilityLabel(label)
    }

    private func addComment() {
        let comment = commentDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !comment.isEmpty else { return }
        onAddComment(comment)
        commentDraft = ""
    }

    private func browserBadge(_ label: String, tint: Color) -> some View {
        Text(label)
            .font(.caption2.monospacedDigit().weight(.bold))
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(tint.opacity(0.14))
            .overlay(
                Capsule()
                    .stroke(tint.opacity(0.22), lineWidth: 1)
            )
            .clipShape(Capsule())
    }

    private func browserInspectionTint(_ depth: BrowserInspectionDepth) -> Color {
        switch depth {
        case .metadataOnly:
            return QuillCodePalette.yellow
        case .fileMetadata:
            return QuillCodePalette.blue
        case .staticHTMLSnapshot:
            return QuillCodePalette.green
        case .networkHTMLSnapshot:
            return QuillCodePalette.green
        case .liveDOMSnapshot:
            return QuillCodePalette.purple
        }
    }
}
