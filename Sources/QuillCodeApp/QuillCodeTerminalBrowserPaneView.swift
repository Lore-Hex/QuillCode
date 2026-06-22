import SwiftUI
import QuillCodeCore

struct QuillCodeTerminalPaneView: View {
    var terminal: TerminalSurface
    @Binding var draft: String
    var onRun: () -> Void
    var onStop: () -> Void
    var onClear: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            entries
            commandLine
        }
        .padding(14)
        .frame(height: 220)
        .background(QuillCodePalette.panel)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "terminal")
                .foregroundStyle(QuillCodePalette.blue)
            Text("Terminal")
                .font(.headline)
            Text(terminal.cwdLabel)
                .font(.caption.monospaced())
                .foregroundStyle(QuillCodePalette.muted)
                .lineLimit(1)
            Spacer()
            Button("Clear", action: onClear)
                .controlSize(.small)
                .disabled(!terminal.canClear)
            if terminal.isRunning {
                ProgressView()
                    .controlSize(.small)
                Button("Stop", action: onStop)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(QuillCodePalette.red)
            }
        }
    }

    private var entries: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                if terminal.entries.isEmpty {
                    Text(terminal.emptyTitle)
                        .font(.callout)
                        .foregroundStyle(QuillCodePalette.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 12)
                } else {
                    ForEach(terminal.entries) { entry in
                        QuillCodeTerminalEntryView(entry: entry)
                    }
                }
            }
        }
    }

    private var commandLine: some View {
        HStack(spacing: 8) {
            Text("$")
                .font(.body.monospaced())
                .foregroundStyle(QuillCodePalette.muted)
            TextField("Run command", text: $draft)
                .textFieldStyle(.roundedBorder)
                .onSubmit(onRun)
                .disabled(terminal.isRunning)
            Button("Run", action: onRun)
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || terminal.isRunning)
        }
    }
}

struct QuillCodeBrowserPaneView: View {
    var browser: BrowserSurface
    @Binding var addressDraft: String
    var onOpen: () -> Void
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
            Button("Open", action: onOpen)
                .disabled(addressDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
            Button("Comment", action: addComment)
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
                .frame(
                    minWidth: QuillCodeMetrics.minimumHitTarget,
                    minHeight: QuillCodeMetrics.minimumHitTarget
                )
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
        }
    }
}

private struct QuillCodeTerminalEntryView: View {
    var entry: TerminalCommandSurface

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                HStack(spacing: 8) {
                    Text("$ \(entry.command)")
                        .font(.caption.monospaced().weight(.semibold))
                        .foregroundStyle(QuillCodePalette.text)
                    if let executionContext = entry.executionContext {
                        QuillCodeExecutionContextChip(context: executionContext)
                    }
                }
                Spacer()
                Text("\(entry.statusLabel) · \(entry.exitCodeLabel)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(statusColor)
            }
            if !entry.stdout.isEmpty {
                Text(entry.stdout)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if !entry.stderr.isEmpty {
                Text(entry.stderr)
                    .font(.caption.monospaced())
                    .foregroundStyle(QuillCodePalette.red)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(10)
        .background(QuillCodePalette.background.opacity(0.7))
        .overlay(alignment: .leading) {
            if let executionContext = entry.executionContext {
                QuillCodeExecutionRail(context: executionContext)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityLabel(accessibilityLabel)
    }

    private var statusColor: Color {
        if entry.isSuccess {
            return QuillCodePalette.green
        }
        if entry.isRunning {
            return QuillCodePalette.blue
        }
        if entry.isStopped {
            return QuillCodePalette.muted
        }
        return QuillCodePalette.red
    }

    private var accessibilityLabel: String {
        let context = entry.executionContext.map {
            ", \($0.label) \($0.detail)"
        } ?? ""
        return "\(entry.command), \(entry.statusLabel), \(entry.exitCodeLabel)\(context)"
    }
}
