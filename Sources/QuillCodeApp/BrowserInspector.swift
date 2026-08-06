import Foundation
import QuillCodeCore

enum BrowserInspector {
    static func title(for url: URL) -> String {
        if url.isFileURL {
            return url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent
        }
        return url.host ?? url.absoluteString
    }

    static func snapshot(
        for url: URL,
        inspectLocalFileContents: Bool = true
    ) -> BrowserSnapshotState {
        if url.isFileURL {
            return fileSnapshot(for: url, inspectContents: inspectLocalFileContents)
        }

        let scheme = (url.scheme ?? "https").uppercased()
        let host = url.host ?? url.absoluteString
        let isLocal = ["localhost", "127.0.0.1", "::1"].contains(host)
        let path = url.path.isEmpty ? "/" : url.path
        return BrowserSnapshotState(
            sourceLabel: isLocal ? "Local web app" : "Web page",
            inspectionDepth: .metadataOnly,
            summary: isLocal
                ? "Live DOM capture is not attached yet; \(QuillCodeProduct.displayName) has URL metadata for this local page."
                : "Live DOM capture is not attached yet; \(QuillCodeProduct.displayName) has URL metadata for this web page.",
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

    static func snapshot(for fetchedPage: BrowserFetchedPage, originalURL: URL) -> BrowserSnapshotState {
        let url = fetchedPage.finalURL
        let sourceLabel = sourceLabel(for: originalURL)
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
        if let statusCode = fetchedPage.statusCode {
            details.append("HTTP: \(statusCode)")
        }
        if let contentType = fetchedPage.contentType, !contentType.isEmpty {
            details.append("Content-Type: \(contentType)")
        }
        details.append(
            fetchedPage.wasTruncated
                ? "Size: \(fetchedPage.byteCount) bytes (truncated)"
                : "Size: \(fetchedPage.byteCount) bytes"
        )

        return BrowserHTMLSnapshotBuilder.snapshot(
            sourceLabel: sourceLabel,
            summary: sourceLabel == "Local web app"
                ? "Fetched a network HTML snapshot for this local page."
                : "Fetched a network HTML snapshot for browser review.",
            details: details,
            html: fetchedPage.html,
            inspectionDepth: .networkHTMLSnapshot
        )
    }

    static func snapshot(for liveDOMSnapshot: BrowserLiveDOMSnapshot, originalURL: URL) -> BrowserSnapshotState {
        BrowserLiveDOMSnapshotBuilder.snapshot(
            liveDOMSnapshot,
            originalURL: originalURL,
            sourceLabel: sourceLabel(for: originalURL)
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
            inspectionDepth: snapshot.inspectionDepth,
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

    private static func fileSnapshot(
        for url: URL,
        inspectContents: Bool
    ) -> BrowserSnapshotState {
        let fileName = url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent
        let extensionName = url.pathExtension.lowercased()
        let isHTML = ["html", "htm", "xhtml"].contains(extensionName)
        var details = ["File: \(fileName)"]

        guard isHTML, inspectContents else {
            if isHTML {
                details.append("Type: HTML")
            }
            return BrowserSnapshotState(
                sourceLabel: isHTML ? "Local HTML" : "Local file",
                inspectionDepth: .fileMetadata,
                summary: isHTML
                    ? "HTML file is ready to open in the visible browser."
                    : "File is ready to open in the browser preview.",
                details: details,
                outline: ["File: \(fileName)"]
            )
        }

        details.append("Type: HTML")
        guard let data = boundedFileContents(
            at: url,
            maximumByteCount: BrowserFetchedPage.defaultMaxHTMLBytes
        ) else {
            details.append("Snapshot: skipped because the file is too large or unreadable")
            return BrowserSnapshotState(
                sourceLabel: "Local HTML",
                inspectionDepth: .fileMetadata,
                summary: "HTML file is ready to open; metadata snapshot was skipped.",
                details: details,
                outline: ["File: \(fileName)"]
            )
        }
        details.append("Size: \(data.count) bytes")
        guard let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii)
        else {
            details.append("Snapshot: skipped because the file is not decodable text")
            return BrowserSnapshotState(
                sourceLabel: "Local HTML",
                inspectionDepth: .fileMetadata,
                summary: "HTML file is ready to open; metadata snapshot was skipped.",
                details: details,
                outline: ["File: \(fileName)"]
            )
        }

        return BrowserHTMLSnapshotBuilder.snapshot(
            sourceLabel: "Local HTML",
            summary: "HTML snapshot captured for browser review.",
            details: details,
            html: html
        )
    }

    private static func boundedFileContents(at url: URL, maximumByteCount: Int) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: maximumByteCount + 1),
              data.count <= maximumByteCount
        else {
            return nil
        }
        return data
    }

    private static func sourceLabel(for url: URL) -> String {
        let host = url.host ?? url.absoluteString
        return ["localhost", "127.0.0.1", "::1"].contains(host) ? "Local web app" : "Web page"
    }
}
