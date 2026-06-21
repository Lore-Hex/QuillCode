import Foundation
import QuillCodeCore

enum BrowserInspector {
    private struct OutlineCandidate {
        var location: Int
        var label: String
    }

    private static let maxSnapshotBytes = 512_000
    private static let outlineLimit = 24
    private static let textSnippetLimit = 800

    static func title(for url: URL) -> String {
        if url.isFileURL {
            return url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent
        }
        return url.host ?? url.absoluteString
    }

    static func snapshot(for url: URL) -> BrowserSnapshotState {
        if url.isFileURL {
            return fileSnapshot(for: url)
        }

        let scheme = (url.scheme ?? "https").uppercased()
        let host = url.host ?? url.absoluteString
        let isLocal = ["localhost", "127.0.0.1", "::1"].contains(host)
        let path = url.path.isEmpty ? "/" : url.path
        return BrowserSnapshotState(
            sourceLabel: isLocal ? "Local web app" : "Web page",
            summary: isLocal
                ? "Ready to inspect a local development page."
                : "Ready to open in the browser preview.",
            details: [
                "Host: \(host)",
                "Scheme: \(scheme)",
                "Path: \(path)"
            ],
            outline: [
                "Page: \(host)",
                "Path: \(path)"
            ]
        )
    }

    static func toolResult(from browser: BrowserState) -> ToolResult {
        guard let currentURL = browser.currentURL else {
            return ToolResult(ok: false, error: "No browser page is open.")
        }
        guard let snapshot = browser.snapshot else {
            return ToolResult(ok: false, error: "Browser page is open but no snapshot is available.")
        }
        let output = BrowserInspectionToolOutput(
            url: currentURL,
            title: browser.title,
            status: browser.status,
            sourceLabel: snapshot.sourceLabel,
            summary: snapshot.summary,
            details: snapshot.details,
            outline: snapshot.outline,
            textSnippet: snapshot.textSnippet,
            comments: browser.comments
                .filter { $0.url == currentURL }
                .map {
                    BrowserInspectionComment(
                        url: $0.url,
                        text: $0.text,
                        createdAt: $0.createdAt
                    )
                }
        )
        return ToolResult(
            ok: true,
            stdout: (try? JSONHelpers.encodePretty(output)) ?? "{}"
        )
    }

    private static func fileSnapshot(for url: URL) -> BrowserSnapshotState {
        let fileName = url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent
        let attributes = (try? FileManager.default.attributesOfItem(atPath: url.path)) ?? [:]
        let byteCount = (attributes[.size] as? NSNumber)?.intValue ?? 0
        let extensionName = url.pathExtension.lowercased()
        let isHTML = ["html", "htm", "xhtml"].contains(extensionName)
        var details = ["File: \(fileName)", "Size: \(byteCount) bytes"]

        guard isHTML else {
            return BrowserSnapshotState(
                sourceLabel: "Local file",
                summary: "File is ready to open in the browser preview.",
                details: details,
                outline: ["File: \(fileName)"]
            )
        }

        details.insert("Type: HTML", at: 1)
        guard byteCount <= maxSnapshotBytes,
              let data = try? Data(contentsOf: url),
              let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii)
        else {
            details.append("Snapshot: skipped because the file is too large or unreadable")
            return BrowserSnapshotState(
                sourceLabel: "Local HTML",
                summary: "HTML file is ready to open; metadata snapshot was skipped.",
                details: details,
                outline: ["File: \(fileName)"]
            )
        }

        if let title = firstHTMLCapture(in: html, pattern: #"<title[^>]*>(.*?)</title>"#) {
            details.append("Title: \(title)")
        }
        if let heading = firstHTMLCapture(in: html, pattern: #"<h[1-2][^>]*>(.*?)</h[1-2]>"#) {
            details.append("Heading: \(heading)")
        }
        details.append("Links: \(htmlTagCount("a", in: html))")
        details.append("Scripts: \(htmlTagCount("script", in: html))")
        details.append("Images: \(htmlTagCount("img", in: html))")
        details.append("Forms: \(htmlTagCount("form", in: html))")

        return BrowserSnapshotState(
            sourceLabel: "Local HTML",
            summary: "HTML snapshot captured for browser review.",
            details: details,
            outline: htmlOutline(in: html),
            textSnippet: htmlTextSnippet(in: html)
        )
    }

    private static func htmlOutline(in html: String) -> [String] {
        var candidates: [OutlineCandidate] = []
        candidates.append(contentsOf: htmlOutlineMatches(
            in: html,
            pattern: #"<h([1-6])[^>]*>(.*?)</h[1-6]>"#
        ) { match in
            guard let level = htmlCapture(1, in: match, source: html),
                  let text = htmlCapture(2, in: match, source: html).map(cleanHTMLText),
                  !text.isEmpty
            else {
                return nil
            }
            return "H\(level): \(text)"
        })
        candidates.append(contentsOf: htmlOutlineMatches(
            in: html,
            pattern: #"<a\b([^>]*)>(.*?)</a>"#
        ) { match in
            let attributes = htmlCapture(1, in: match, source: html) ?? ""
            let text = htmlCapture(2, in: match, source: html).map(cleanHTMLText) ?? ""
            let href = htmlAttribute("href", in: attributes)
            let label = text.isEmpty ? (href ?? "Link") : text
            return href.map { "Link: \(label) -> \($0)" } ?? "Link: \(label)"
        })
        candidates.append(contentsOf: htmlOutlineMatches(
            in: html,
            pattern: #"<button\b([^>]*)>(.*?)</button>"#
        ) { match in
            let text = htmlCapture(2, in: match, source: html).map(cleanHTMLText) ?? ""
            return text.isEmpty ? "Button" : "Button: \(text)"
        })
        candidates.append(contentsOf: htmlOutlineMatches(
            in: html,
            pattern: #"<input\b([^>]*)>"#
        ) { match in
            let attributes = htmlCapture(1, in: match, source: html) ?? ""
            let label = htmlAttribute("aria-label", in: attributes)
                ?? htmlAttribute("placeholder", in: attributes)
                ?? htmlAttribute("name", in: attributes)
                ?? htmlAttribute("type", in: attributes)
                ?? "input"
            return "Input: \(label)"
        })
        candidates.append(contentsOf: htmlOutlineMatches(
            in: html,
            pattern: #"<form\b([^>]*)>"#
        ) { match in
            let attributes = htmlCapture(1, in: match, source: html) ?? ""
            let label = htmlAttribute("aria-label", in: attributes)
                ?? htmlAttribute("id", in: attributes)
                ?? htmlAttribute("action", in: attributes)
            return label.map { "Form: \($0)" } ?? "Form"
        })
        candidates.append(contentsOf: htmlOutlineMatches(
            in: html,
            pattern: #"<img\b([^>]*)>"#
        ) { match in
            let attributes = htmlCapture(1, in: match, source: html) ?? ""
            let label = htmlAttribute("alt", in: attributes)
                ?? htmlAttribute("src", in: attributes)
                ?? "image"
            return "Image: \(label)"
        })

        let labels = candidates
            .sorted { $0.location < $1.location }
            .map(\.label)
            .filter { !$0.isEmpty }
        return Array(labels.prefix(Self.outlineLimit))
    }

    private static func htmlTextSnippet(in html: String) -> String? {
        let body = firstHTMLCaptureRaw(in: html, pattern: #"<body[^>]*>(.*?)</body>"#) ?? html
        let withoutScripts = body
            .replacingOccurrences(
                of: #"<script\b[^>]*>.*?</script>"#,
                with: " ",
                options: [.regularExpression, .caseInsensitive]
            )
            .replacingOccurrences(
                of: #"<style\b[^>]*>.*?</style>"#,
                with: " ",
                options: [.regularExpression, .caseInsensitive]
            )
        let text = cleanHTMLText(withoutScripts)
        guard !text.isEmpty else { return nil }
        return truncatedText(text)
    }

    private static func htmlOutlineMatches(
        in html: String,
        pattern: String,
        label: (NSTextCheckingResult) -> String?
    ) -> [OutlineCandidate] {
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return []
        }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        return regex.matches(in: html, range: range).compactMap { match in
            guard let label = label(match), !label.isEmpty else { return nil }
            return OutlineCandidate(location: match.range.location, label: label)
        }
    }

    private static func firstHTMLCapture(in html: String, pattern: String) -> String? {
        firstHTMLCaptureRaw(in: html, pattern: pattern).map(cleanHTMLText)
    }

    private static func firstHTMLCaptureRaw(in html: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return nil
        }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        guard let match = regex.firstMatch(in: html, range: range),
              match.numberOfRanges > 1,
              let captureRange = Range(match.range(at: 1), in: html)
        else {
            return nil
        }
        return String(html[captureRange])
    }

    private static func htmlCapture(_ index: Int, in match: NSTextCheckingResult, source: String) -> String? {
        guard match.numberOfRanges > index,
              let range = Range(match.range(at: index), in: source)
        else {
            return nil
        }
        return String(source[range])
    }

    private static func htmlAttribute(_ name: String, in attributes: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: name)
        guard let regex = try? NSRegularExpression(
            pattern: #"\b\#(escaped)\s*=\s*["']([^"']+)["']"#,
            options: [.caseInsensitive]
        ) else {
            return nil
        }
        let range = NSRange(attributes.startIndex..<attributes.endIndex, in: attributes)
        guard let match = regex.firstMatch(in: attributes, range: range),
              let captureRange = Range(match.range(at: 1), in: attributes)
        else {
            return nil
        }
        let value = cleanHTMLText(String(attributes[captureRange]))
        return value.isEmpty ? nil : value
    }

    private static func htmlTagCount(_ tag: String, in html: String) -> Int {
        let escapedTag = NSRegularExpression.escapedPattern(for: tag)
        guard let regex = try? NSRegularExpression(
            pattern: #"<\s*\#(escapedTag)(\s|>|/)"#,
            options: [.caseInsensitive]
        ) else {
            return 0
        }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        return regex.numberOfMatches(in: html, range: range)
    }

    private static func cleanHTMLText(_ raw: String) -> String {
        let withoutTags = raw.replacingOccurrences(
            of: #"<[^>]+>"#,
            with: " ",
            options: .regularExpression
        )
        let decoded = withoutTags
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
        return decoded
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func truncatedText(_ text: String) -> String {
        guard text.count > textSnippetLimit else { return text }
        return String(text.prefix(textSnippetLimit)).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }
}
