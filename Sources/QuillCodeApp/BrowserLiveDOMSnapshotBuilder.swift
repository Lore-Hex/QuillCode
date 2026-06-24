import Foundation
import QuillCodeCore

enum BrowserLiveDOMSnapshotBuilder {
    private static let outlineLimit = 24
    private static let textSnippetLimit = 800

    static func snapshot(
        _ capture: BrowserLiveDOMSnapshot,
        originalURL: URL,
        sourceLabel: String
    ) -> BrowserSnapshotState {
        var details = baseDetails(for: capture, originalURL: originalURL)
        if let title = nonEmpty(capture.title) {
            details.append("Title: \(title)")
        }
        if let viewportDescription = nonEmpty(capture.viewportDescription) {
            details.append("Viewport: \(viewportDescription)")
        }

        var snapshot = capture.html.map {
            BrowserHTMLSnapshotBuilder.snapshot(
                sourceLabel: sourceLabel,
                summary: "Captured a live DOM snapshot from the rendered browser session.",
                details: details,
                html: $0,
                inspectionDepth: .liveDOMSnapshot
            )
        } ?? BrowserSnapshotState(
            sourceLabel: sourceLabel,
            inspectionDepth: .liveDOMSnapshot,
            summary: "Captured a live DOM snapshot from the rendered browser session.",
            details: details,
            outline: [],
            textSnippet: nil
        )

        let capturedOutline = capture.outline
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if !capturedOutline.isEmpty {
            snapshot.outline = Array(capturedOutline.prefix(outlineLimit))
        }
        if let visibleText = nonEmpty(capture.visibleText) {
            snapshot.textSnippet = truncated(visibleText)
        }
        return snapshot
    }

    private static func baseDetails(for capture: BrowserLiveDOMSnapshot, originalURL: URL) -> [String] {
        let url = capture.finalURL
        let host = url.host ?? originalURL.host ?? url.absoluteString
        let path = url.path.isEmpty ? "/" : url.path
        var details = [
            "Host: \(host)",
            "Scheme: \((url.scheme ?? originalURL.scheme ?? "https").uppercased())",
            "Path: \(path)"
        ]
        if originalURL.absoluteString != url.absoluteString {
            details.append("Final URL: \(url.absoluteString)")
        }
        return details
    }

    private static func nonEmpty(_ text: String?) -> String? {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func truncated(_ text: String) -> String {
        let compact = text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard compact.count > textSnippetLimit else { return compact }
        return String(compact.prefix(textSnippetLimit)).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }
}
