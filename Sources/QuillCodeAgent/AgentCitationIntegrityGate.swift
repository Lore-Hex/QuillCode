import Foundation
import QuillCodeCore

/// F29 — citation-integrity enforcement for research-shaped runs.
///
/// Live failures this closes: a speaker-brief run cited a URL lifted from search-result snippets
/// that it never fetched (the fetch log shows a *different* path on the same host), and a re-drive
/// on a second model leaked another unfetched pointer link — both under an explicit prompt rule
/// forbidding exactly that. Prompts are insufficient for this class (same lesson as fabrication);
/// the run loop must check the deliverable against the run's actual evidence.
///
/// The invariant is provenance, not "fetched exactly": a citation is legitimate when the URL is
/// **grounded** — it appeared in the user's request, in prior turns of the thread, in a fetched
/// page's own content, in a file the run read, or is itself a fetched URL (requested or
/// post-redirect spelling). What the gate rejects is a URL whose only provenance is a search-result
/// listing or model memory — precisely the observed leak. Accordingly the provenance harvest
/// covers every successful tool result EXCEPT `host.web.search` output.
///
/// Scope is deliberately narrow to keep false positives inert:
/// - Only markdown-linked `[text](http…)` URLs count as citations; image embeds `![…](…)`,
///   fenced code blocks, and bare URLs in data files are never flagged.
/// - Only the terminal say and task-named `.md` deliverables **this run itself wrote** are
///   scanned — never user-supplied input files.
/// - The gate only arms when the run performed at least one successful `host.web.fetch`.
///
/// Failure mode is honest surfacing, not a hard error: after the bounded corrective budget the
/// run completes with a visible integrity notice naming the ungrounded links (mirroring the
/// run-integrity verdict-in-transcript precedent), so a rare false positive degrades to a note
/// instead of killing a finished task.
enum AgentCitationIntegrityGate {
    /// Normalizes a URL for grounded-vs-cited comparison: lowercases the scheme and host, drops
    /// the fragment, and strips one trailing slash. Port, userinfo, path case, and query survive —
    /// they distinguish origins and pages.
    static func normalize(_ raw: String) -> String {
        var value = raw
        if let hash = value.firstIndex(of: "#") {
            value = String(value[..<hash])
        }
        if value.hasSuffix("/") { value = String(value.dropLast()) }
        guard let components = URLComponents(string: value),
              let scheme = components.scheme,
              let host = components.host
        else {
            return value
        }
        let user = components.user.map { "\($0)@" } ?? ""
        let port = components.port.map { ":\($0)" } ?? ""
        var path = components.percentEncodedPath
        if path.hasSuffix("/") { path = String(path.dropLast()) }
        let query = components.percentEncodedQuery.map { "?\($0)" } ?? ""
        return "\(scheme.lowercased())://\(user)\(host.lowercased())\(port)\(path)\(query)"
    }

    /// Extracts the final URL from a successful `host.web.fetch` result. The executor's summary
    /// line is `Fetched <finalURL> (HTTP …` — the URL after redirects, which is what a model
    /// legitimately cites for a page it reached via a hop (notion.so → notion.com).
    static func finalURL(fromFetchStdout stdout: String) -> String? {
        guard stdout.hasPrefix("Fetched ") else { return nil }
        let rest = stdout.dropFirst("Fetched ".count)
        guard let end = rest.firstIndex(where: { $0 == " " || $0 == "\n" }) else { return nil }
        let url = String(rest[..<end])
        return url.hasPrefix("http") ? url : nil
    }

    /// Every http(s) URL appearing anywhere in the text, for building the grounded-provenance
    /// set. Deliberately permissive — over-collecting provenance only ever *allows* citations.
    static func allURLs(in text: String) -> [String] {
        let pattern = #"https?://[^\s<>"'()\]]+(?:\([^\s()]*\)[^\s<>"'()\]]*)*"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard let r = Range(match.range, in: text) else { return nil }
            return String(text[r]).trimmingCharacters(in: CharacterSet(charactersIn: ".,;:"))
        }
    }

    /// Markdown-linked http(s) URLs in the text — the citations the gate audits.
    ///
    /// Handles the forms models actually emit: plain `[t](url)`, parenthesized URLs
    /// (`…/Swift_(programming_language)`) via balanced-paren scanning, optional link titles
    /// (`[t](url "title")`), and angle-bracket destinations (`[t](<url>)`). Image embeds
    /// (`![alt](url)`) are skipped — an embed is not a citation — and fenced code blocks are
    /// stripped first so documentation examples are never flagged.
    static func markdownLinkedURLs(in text: String) -> [String] {
        var urls: [String] = []
        let stripped = withoutFencedCodeBlocks(text)
        var index = stripped.startIndex
        while let open = stripped[index...].firstIndex(of: "[") {
            // `![` is an image embed, not a citation.
            if open > stripped.startIndex, stripped[stripped.index(before: open)] == "!" {
                index = stripped.index(after: open)
                continue
            }
            guard let close = stripped[open...].firstIndex(of: "]"),
                  stripped.index(after: close) < stripped.endIndex,
                  stripped[stripped.index(after: close)] == "("
            else {
                index = stripped.index(after: open)
                continue
            }
            let destinationStart = stripped.index(close, offsetBy: 2)
            guard destinationStart < stripped.endIndex,
                  let (rawDestination, afterDestination) = linkDestination(
                    in: stripped, from: destinationStart
                  )
            else {
                index = stripped.index(after: open)
                continue
            }
            if rawDestination.hasPrefix("http://") || rawDestination.hasPrefix("https://") {
                urls.append(rawDestination)
            }
            index = afterDestination
        }
        return urls
    }

    /// Reads one markdown link destination starting at `start` (just past `](`): either an
    /// `<angle-bracketed>` destination, or a run of non-space characters with balanced
    /// parentheses, optionally followed by a quoted title before the closing `)`.
    private static func linkDestination(
        in text: String,
        from start: String.Index
    ) -> (destination: String, after: String.Index)? {
        var cursor = start
        if text[cursor] == "<" {
            let destinationStart = text.index(after: cursor)
            guard let end = text[destinationStart...].firstIndex(of: ">") else { return nil }
            return (String(text[destinationStart..<end]), text.index(after: end))
        }
        var depth = 0
        var destinationEnd: String.Index?
        while cursor < text.endIndex {
            let character = text[cursor]
            if character == "(" {
                depth += 1
            } else if character == ")" {
                if depth == 0 { destinationEnd = cursor; break }
                depth -= 1
            } else if character == " " || character == "\n" {
                // A space inside the parens starts an optional title; the destination ends here.
                destinationEnd = cursor
                break
            }
            cursor = text.index(after: cursor)
        }
        guard let end = destinationEnd else { return nil }
        return (String(text[start..<end]), text.index(after: end))
    }

    private static func withoutFencedCodeBlocks(_ text: String) -> String {
        var kept: [Substring] = []
        var fenceMarker: Character?
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                let marker = trimmed.first
                if fenceMarker == nil {
                    fenceMarker = marker
                    continue
                }
                if fenceMarker == marker {
                    fenceMarker = nil
                    continue
                }
            }
            if fenceMarker == nil { kept.append(line) }
        }
        return kept.joined(separator: "\n")
    }

    /// The largest deliverable the gate will read. Citations live in prose files; anything
    /// bigger is data and out of scope.
    private static let maxScannedFileBytes = 512 * 1024

    /// Returns the cited-but-ungrounded URLs (original spelling, deduplicated, in order) across
    /// the terminal say and task-named `.md` deliverables this run wrote.
    ///
    /// - Parameters:
    ///   - groundedURLs: normalized URLs with verifiable provenance this run — fetched URLs
    ///     (requested + final), plus every URL appearing in successful non-search tool output,
    ///     in the user message, or in the thread's prior messages.
    ///   - writtenWorkspacePaths: workspace-relative paths this run wrote via file tools; only
    ///     named deliverables among them are scanned, so user input files are never audited.
    static func ungroundedCitations(
        sayText: String,
        userMessage: String,
        workspaceRoot: URL,
        groundedURLs: Set<String>,
        writtenWorkspacePaths: Set<String>
    ) -> [String] {
        var scanned = sayText
        for name in AgentDeliverableGate.requiredDeliverables(in: userMessage)
        where name.lowercased().hasSuffix(".md") && wasWritten(name, in: writtenWorkspacePaths) {
            let url = workspaceRoot.appendingPathComponent(name)
            guard let data = try? Data(contentsOf: url), data.count <= maxScannedFileBytes,
                  let text = String(data: data, encoding: .utf8)
            else { continue }
            scanned += "\n" + text
        }
        var seen = Set<String>()
        var offenders: [String] = []
        for cited in markdownLinkedURLs(in: scanned) {
            let normalized = normalize(cited)
            guard !groundedURLs.contains(normalized),
                  seen.insert(normalized).inserted
            else { continue }
            offenders.append(cited)
        }
        return offenders
    }

    private static func wasWritten(_ deliverableName: String, in writtenPaths: Set<String>) -> Bool {
        let name = deliverableName.hasPrefix("./") ? String(deliverableName.dropFirst(2)) : deliverableName
        return writtenPaths.contains { written in
            let path = written.hasPrefix("./") ? String(written.dropFirst(2)) : written
            return path == name || path.hasSuffix("/" + name)
        }
    }

    static func correctionPrompt(unfetched: [String]) -> String {
        """
        Citation-integrity check: your answer links URLs that have no verifiable source in this \
        run: \(unfetched.joined(separator: ", ")). Each cited URL must come from a page you \
        successfully fetched, a file you read, or the user's request — not from search-result \
        snippets or memory. For each one, either fetch it now (host.web.fetch) and keep the link, \
        or remove the link and mark the claim as 'unverified'. Update the deliverable file if it \
        contains the link, then give your final answer. If something blocks you, write exactly \
        what you did and what blocked you.
        """
    }

    static func integrityNotice(unfetched: [String]) -> String {
        """
        ⚠ Citation integrity: \(unfetched.count) linked URL(s) have no verifiable source in this \
        run and could not be verified: \(unfetched.joined(separator: ", "))
        """
    }
}
