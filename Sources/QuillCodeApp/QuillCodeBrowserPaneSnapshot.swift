import SwiftUI
import QuillCodeCore

extension QuillCodeBrowserPaneView {
    @ViewBuilder
    var pageSummary: some View {
        if let currentURL = browser.currentURL {
            currentPageSummary(currentURL: currentURL)
        } else {
            emptyPageSummary
        }
    }

    private func currentPageSummary(currentURL: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: QuillCodeMetrics.controlClusterSpacing) {
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
            snapshotDetails(snapshot.details)
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
}
