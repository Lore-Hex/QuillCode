import Foundation
import QuillCodeApp

struct BrowserProcessInvocation: Sendable, Equatable {
    var executable: String
    var arguments: [String]
    var environment: [String: String]?
    var timeout: TimeInterval
}

struct BrowserProcessRenderResult: Sendable, Equatable {
    var stdout: String
    var stderr: String
    var exitCode: Int32
}

protocol BrowserProcessExecutableLocating: Sendable {
    func browserExecutable() -> String?
}

struct BrowserProcessExecutableLocator: BrowserProcessExecutableLocating {
    private let candidates: [String]
    private let environment: [String: String]

    init(
        candidates: [String] = Self.defaultCandidates,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.candidates = candidates
        self.environment = environment
    }

    func browserExecutable() -> String? {
        for candidate in candidates {
            if candidate.contains("/"), FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }

        let directories = (environment["PATH"] ?? "")
            .split(separator: ":", omittingEmptySubsequences: true)
            .map(String.init)
        for directory in directories {
            for candidate in candidates where !candidate.contains("/") {
                let path = URL(fileURLWithPath: directory)
                    .appendingPathComponent(candidate)
                    .path
                if FileManager.default.isExecutableFile(atPath: path) {
                    return path
                }
            }
        }
        return nil
    }

    private static let defaultCandidates = [
        "chromium",
        "chromium-browser",
        "google-chrome",
        "google-chrome-stable",
        "microsoft-edge",
        "brave-browser",
        "/usr/bin/chromium",
        "/usr/bin/chromium-browser",
        "/usr/bin/google-chrome",
        "/usr/bin/google-chrome-stable"
    ]
}

protocol BrowserProcessRunning: Sendable {
    func run(_ invocation: BrowserProcessInvocation) async throws -> BrowserProcessRenderResult
}

struct BrowserProcessRunner: BrowserProcessRunning {
    func run(_ invocation: BrowserProcessInvocation) async throws -> BrowserProcessRenderResult {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        process.executableURL = URL(fileURLWithPath: invocation.executable)
        process.arguments = invocation.arguments
        process.environment = invocation.environment
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()

        let timedOut = wait(for: process, timeout: invocation.timeout)
        if timedOut, process.isRunning {
            process.terminate()
            process.waitUntilExit()
        }

        return BrowserProcessRenderResult(
            stdout: String(
                data: stdout.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? "",
            stderr: String(
                data: stderr.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? "",
            exitCode: timedOut ? 124 : process.terminationStatus
        )
    }

    private func wait(for process: Process, timeout: TimeInterval) -> Bool {
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            process.waitUntilExit()
            group.leave()
        }
        return group.wait(timeout: .now() + max(0, timeout)) == .timedOut
    }
}

final class ChromiumBrowserLiveDOMCapturer: BrowserLiveDOMCapturing, @unchecked Sendable {
    private let executableLocator: any BrowserProcessExecutableLocating
    private let processRunner: any BrowserProcessRunning
    private let timeout: TimeInterval
    private let virtualTimeBudgetMilliseconds: Int
    private let environment: [String: String]?
    private let allowNoSandbox: Bool

    init(
        executableLocator: any BrowserProcessExecutableLocating = BrowserProcessExecutableLocator(),
        processRunner: any BrowserProcessRunning = BrowserProcessRunner(),
        timeout: TimeInterval = 8,
        virtualTimeBudgetMilliseconds: Int = 2_500,
        environment: [String: String]? = nil,
        allowNoSandbox: Bool = ProcessInfo.processInfo.environment["QUILLCODE_BROWSER_NO_SANDBOX"] == "1"
    ) {
        self.executableLocator = executableLocator
        self.processRunner = processRunner
        self.timeout = timeout
        self.virtualTimeBudgetMilliseconds = max(0, virtualTimeBudgetMilliseconds)
        self.environment = environment
        self.allowNoSandbox = allowNoSandbox
    }

    func captureLiveDOM(for url: URL) async throws -> BrowserLiveDOMSnapshot {
        guard Self.supports(url) else {
            throw BrowserLiveDOMCaptureFailure.transport(
                "Rendered browser capture supports http, https, and file URLs."
            )
        }
        guard let executable = executableLocator.browserExecutable() else {
            throw BrowserLiveDOMCaptureFailure.noRenderedSession
        }

        let profileDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuillCodeChromiumLiveDOM-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: profileDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: profileDirectory) }

        let result = try await processRunner.run(BrowserProcessInvocation(
            executable: executable,
            arguments: chromiumArguments(for: url, profileDirectory: profileDirectory),
            environment: environment,
            timeout: timeout
        ))

        guard result.exitCode == 0 else {
            throw BrowserLiveDOMCaptureFailure.transport(failureMessage(from: result))
        }
        guard !result.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw BrowserLiveDOMCaptureFailure.pageNotReady
        }

        return RenderedBrowserHTMLSnapshotParser.snapshot(finalURL: url, html: result.stdout)
    }

    private func chromiumArguments(for url: URL, profileDirectory: URL) -> [String] {
        var arguments = [
            "--headless=new",
            "--disable-gpu",
            "--disable-dev-shm-usage",
            "--no-first-run",
            "--no-default-browser-check",
            "--user-data-dir=\(profileDirectory.path)",
            "--virtual-time-budget=\(virtualTimeBudgetMilliseconds)",
            "--dump-dom"
        ]
        if allowNoSandbox {
            arguments.append("--no-sandbox")
        }
        arguments.append(url.absoluteString)
        return arguments
    }

    private static func supports(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return ["http", "https", "file"].contains(scheme)
    }

    private func failureMessage(from result: BrowserProcessRenderResult) -> String {
        let diagnostic = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if diagnostic.isEmpty {
            return "Browser process exited with code \(result.exitCode)."
        }
        return "Browser process exited with code \(result.exitCode): \(diagnostic)"
    }
}

private enum RenderedBrowserHTMLSnapshotParser {
    private struct OutlineCandidate {
        var location: Int
        var label: String
    }

    static func snapshot(finalURL: URL, html: String) -> BrowserLiveDOMSnapshot {
        BrowserLiveDOMSnapshot(
            finalURL: finalURL,
            title: firstHTMLCapture(in: html, pattern: #"<title[^>]*>(.*?)</title>"#),
            visibleText: visibleText(in: html),
            outline: outline(in: html),
            html: limited(html, max: 512_000),
            viewportDescription: "Headless Chromium browser process"
        )
    }

    private static func outline(in html: String) -> [String] {
        var candidates: [OutlineCandidate] = []
        candidates += matches(in: html, pattern: #"<h([1-6])[^>]*>(.*?)</h[1-6]>"#) { match in
            guard let level = capture(1, in: match, source: html),
                  let text = capture(2, in: match, source: html).map(cleanHTMLText),
                  !text.isEmpty
            else { return nil }
            return "H\(level): \(text)"
        }
        candidates += matches(in: html, pattern: #"<a\b([^>]*)>(.*?)</a>"#) { match in
            let attributes = capture(1, in: match, source: html) ?? ""
            let text = capture(2, in: match, source: html).map(cleanHTMLText) ?? ""
            let href = attribute("href", in: attributes)
            let label = text.isEmpty ? (href ?? "Link") : text
            return href.map { "Link: \(label) -> \($0)" } ?? "Link: \(label)"
        }
        candidates += matches(in: html, pattern: #"<button\b([^>]*)>(.*?)</button>"#) { match in
            let text = capture(2, in: match, source: html).map(cleanHTMLText) ?? ""
            return text.isEmpty ? "Button" : "Button: \(text)"
        }
        candidates += matches(in: html, pattern: #"<input\b([^>]*)>"#) { match in
            let attributes = capture(1, in: match, source: html) ?? ""
            let label = attribute("aria-label", in: attributes)
                ?? attribute("placeholder", in: attributes)
                ?? attribute("name", in: attributes)
                ?? attribute("type", in: attributes)
                ?? "input"
            return "Input: \(label)"
        }
        candidates += matches(in: html, pattern: #"<form\b([^>]*)>"#) { match in
            let attributes = capture(1, in: match, source: html) ?? ""
            let label = attribute("aria-label", in: attributes)
                ?? attribute("id", in: attributes)
                ?? attribute("action", in: attributes)
            return label.map { "Form: \($0)" } ?? "Form"
        }
        candidates += matches(in: html, pattern: #"<img\b([^>]*)>"#) { match in
            let attributes = capture(1, in: match, source: html) ?? ""
            let label = attribute("alt", in: attributes)
                ?? attribute("src", in: attributes)
                ?? "image"
            return "Image: \(label)"
        }

        return Array(candidates
            .sorted { $0.location < $1.location }
            .map(\.label)
            .filter { !$0.isEmpty }
            .prefix(48))
    }

    private static func visibleText(in html: String) -> String? {
        let body = firstHTMLCaptureRaw(in: html, pattern: #"<body[^>]*>(.*?)</body>"#) ?? html
        let stripped = body
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
        let text = cleanHTMLText(stripped)
        return text.isEmpty ? nil : limited(text, max: 12_000)
    }

    private static func matches(
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

    private static func capture(_ index: Int, in match: NSTextCheckingResult, source: String) -> String? {
        guard match.numberOfRanges > index,
              let range = Range(match.range(at: index), in: source)
        else {
            return nil
        }
        return String(source[range])
    }

    private static func attribute(_ name: String, in attributes: String) -> String? {
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
            .replacingOccurrences(of: "&nbsp;", with: " ")
        return decoded
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func limited(_ text: String, max: Int) -> String {
        String(text.prefix(max))
    }
}
