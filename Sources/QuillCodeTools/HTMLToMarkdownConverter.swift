import Foundation

public struct HTMLToMarkdownOptions: Sendable {
    /// Base URL used to resolve relative link and image targets (usually the fetched page URL).
    public var baseURL: URL?
    /// Hard ceiling on produced markdown; conversion stops (and reports truncation) beyond it.
    public var maxOutputBytes: Int
    /// Element depth beyond which structure is ignored (text still flows) — bounds the cost of
    /// pathologically nested documents.
    public var maxElementDepth: Int

    public init(baseURL: URL? = nil, maxOutputBytes: Int = 262_144, maxElementDepth: Int = 48) {
        self.baseURL = baseURL
        self.maxOutputBytes = maxOutputBytes
        self.maxElementDepth = maxElementDepth
    }
}

/// Hand-rolled HTML→markdown conversion for `host.web.fetch` — no parser dependency, no
/// recursion, every buffer bounded. Covers the constructs that matter for reading docs pages
/// (headings, paragraphs, links, lists, code, emphasis, blockquotes, images, best-effort
/// tables) and deliberately drops page chrome (`script`/`style`/`nav`/`head`/…). Malformed
/// HTML degrades to text instead of failing: the tokenizer treats anything unrecognizable as
/// character data, and unclosed constructs are flushed at end of input.
public enum HTMLToMarkdown {
    public static func convert(
        _ html: String,
        options: HTMLToMarkdownOptions = HTMLToMarkdownOptions()
    ) -> (markdown: String, truncated: Bool) {
        var converter = Converter(html: html, options: options)
        return converter.run()
    }

    // MARK: - Converter

    private struct Converter {
        private var tokenizer: HTMLTokenizer
        private let options: HTMLToMarkdownOptions
        private let writer: HTMLMarkdownWriter

        private var elementDepth = 0
        private var emphasisStack: [String] = []
        private var listStack: [ListContext] = []
        private var quoteDepth = 0
        private var inlineCaptures: [InlineCapture] = []
        private var preContext: PreContext?
        private var table: TableContext?
        private var skip: SkipContext?

        /// Inline constructs whose text is buffered in the writer before they can be emitted.
        /// The stack mirrors the writer's capture stack (cell/caption captures sit below).
        private enum InlineCapture {
            case link(href: String)
            case code
        }

        private struct ListContext {
            var ordered: Bool
            var nextIndex: Int
        }

        private struct PreContext {
            var language: String
        }

        private struct TableContext {
            var rows: [[String]] = []
            var currentRow: [String]?
            var cellOpen = false
            var captionOpen = false
            var caption: String?
            var nestedTables = 0
        }

        private struct SkipContext {
            var name: String
            var depth: Int
        }

        init(html: String, options: HTMLToMarkdownOptions) {
            self.tokenizer = HTMLTokenizer(html)
            self.options = options
            self.writer = HTMLMarkdownWriter(maxOutputBytes: max(1024, options.maxOutputBytes))
        }

        mutating func run() -> (markdown: String, truncated: Bool) {
            while let token = tokenizer.next() {
                if writer.truncated {
                    break
                }
                switch token {
                case .text(let text):
                    handleText(text)
                case .openTag(let name, let attributes, let selfClosing):
                    handleOpenTag(name, attributes: attributes, selfClosing: selfClosing)
                case .closeTag(let name):
                    handleCloseTag(name)
                }
            }
            finishOpenConstructs()
            return (writer.finalizedMarkdown(), writer.truncated)
        }

        // MARK: - Text

        private mutating func handleText(_ text: String) {
            guard skip == nil, !text.isEmpty else {
                return
            }
            if isBetweenTableCells {
                return // Inter-cell filler inside a table ("\n  " between <tr>s) is noise.
            }
            writer.writeText(text)
        }

        /// True while inside a `<table>` but not inside a cell or caption capture — the region
        /// where text and inline markup have no representable place in a pipe table.
        private var isBetweenTableCells: Bool {
            guard let table else {
                return false
            }
            return !table.cellOpen && !table.captionOpen
        }

        // MARK: - Open tags

        private mutating func handleOpenTag(_ name: String, attributes: [String: String], selfClosing: Bool) {
            if skip != nil {
                handleOpenTagWhileSkipping(name, selfClosing: selfClosing)
                return
            }
            if Self.rawTextElements.contains(name) {
                if !selfClosing {
                    _ = tokenizer.consumeRawText(until: name)
                }
                return
            }
            if Self.skippedSubtreeElements.contains(name), !selfClosing {
                skip = SkipContext(name: name, depth: 1)
                return
            }
            let isVoid = Self.voidElements.contains(name)
            if !isVoid, !selfClosing {
                elementDepth += 1
            }
            let structural = elementDepth <= options.maxElementDepth

            // Between a table's cells only table structure matters; letting markers (emphasis,
            // headings, list bullets) through would strand markdown syntax in the output while
            // the corresponding text is being dropped.
            if isBetweenTableCells, !Self.tableStructureElements.contains(name) {
                return
            }

            if preContext != nil {
                // Inside <pre>, tags (highlighter <span>s) contribute nothing themselves —
                // except <br> (a literal line break) and <code>, which usually carries the
                // `language-…` class in the common `<pre><code class="language-x">` pattern.
                if name == "br" {
                    writer.writeText("\n")
                } else if name == "code", let context = preContext, context.language.isEmpty {
                    preContext = PreContext(language: Self.codeLanguage(fromClass: attributes["class"]))
                }
                return
            }

            // Block-level elements implicitly terminate open inline constructs, the way
            // browsers auto-close an unclosed <a> or <code> at a block boundary — otherwise a
            // page missing one </a> would swallow everything after it into the link's
            // (bounded) capture buffer.
            if Self.blockBoundaryElements.contains(name) {
                flushInlineCaptures()
            }

            switch name {
            case "br":
                requestLineBreak()
            case "hr":
                writer.writeBlockLines(["---"])
            case "p", "div", "section", "article", "main", "header", "footer", "figure",
                 "figcaption", "fieldset", "form", "details", "address", "dl", "dd", "center",
                 "summary", "dt":
                requestBlockBreak()
            case "h1", "h2", "h3", "h4", "h5", "h6":
                requestBlockBreak()
                let level = Int(name.dropFirst()) ?? 1
                writer.writeMarker(String(repeating: "#", count: min(max(level, 1), 6)) + " ", flushingSpace: true)
            case "ul", "ol":
                guard structural, listStack.count < Self.maxListDepth else {
                    break
                }
                if listStack.isEmpty {
                    requestBlockBreak()
                }
                listStack.append(ListContext(ordered: name == "ol", nextIndex: 1))
            case "li":
                startListItem()
            case "blockquote":
                guard structural, quoteDepth < Self.maxQuoteDepth else {
                    break
                }
                requestBlockBreak()
                quoteDepth += 1
                writer.quoteDepth = quoteDepth
                requestBlockBreak()
            case "pre":
                guard structural else {
                    break
                }
                startPre(attributes: attributes)
            case "code", "kbd", "samp", "tt":
                guard structural, preContext == nil else {
                    break
                }
                if writer.pushCapture(byteLimit: Self.inlineCodeByteLimit) {
                    inlineCaptures.append(.code)
                }
            case "strong", "b":
                openEmphasis("**")
            case "em", "i", "cite", "dfn", "var":
                openEmphasis("*")
            case "del", "s", "strike":
                openEmphasis("~~")
            case "a":
                guard structural else {
                    break
                }
                if writer.pushCapture(byteLimit: Self.linkTextByteLimit) {
                    inlineCaptures.append(.link(href: attributes["href"] ?? ""))
                }
            case "img":
                writeImage(attributes)
            case "table":
                handleTableOpen()
            case "tr":
                handleTableRowOpen()
            case "td", "th":
                handleTableCellOpen()
            case "caption":
                handleTableCaptionOpen()
            case "thead", "tbody", "tfoot", "colgroup":
                break
            default:
                break // Unknown/inline elements are transparent.
            }
        }

        private mutating func handleOpenTagWhileSkipping(_ name: String, selfClosing: Bool) {
            guard var context = skip else {
                return
            }
            // A raw-text element inside a skipped subtree must still be consumed as raw text —
            // otherwise a literal "</head>" inside an inline script would end the skip early.
            if Self.rawTextElements.contains(name) {
                if !selfClosing {
                    _ = tokenizer.consumeRawText(until: name)
                }
                return
            }
            if name == context.name, !selfClosing, !Self.voidElements.contains(name) {
                context.depth += 1
                skip = context
            }
            // Browsers auto-close <head> when <body> starts; honor that so a page missing
            // </head> does not lose its entire body.
            if context.name == "head", name == "body" {
                skip = nil
            }
        }

        // MARK: - Close tags

        private mutating func handleCloseTag(_ name: String) {
            if var context = skip {
                if name == context.name {
                    context.depth -= 1
                    skip = context.depth > 0 ? context : nil
                }
                return
            }
            if Self.skippedSubtreeElements.contains(name) || Self.rawTextElements.contains(name) {
                return // Stray close without a tracked open.
            }
            if !Self.voidElements.contains(name) {
                elementDepth = max(0, elementDepth - 1)
            }
            if isBetweenTableCells, !Self.tableStructureElements.contains(name) {
                return
            }
            if preContext != nil {
                if name == "pre" {
                    finishPre()
                }
                return
            }

            if Self.blockBoundaryElements.contains(name) {
                flushInlineCaptures()
            }

            switch name {
            case "p", "div", "section", "article", "main", "header", "footer", "figure",
                 "figcaption", "fieldset", "form", "details", "summary", "dl", "dt", "dd",
                 "center", "h1", "h2", "h3", "h4", "h5", "h6", "li":
                requestBlockBreakAfterBlock(name)
            case "ul", "ol":
                if !listStack.isEmpty {
                    listStack.removeLast()
                }
                if listStack.isEmpty {
                    requestBlockBreak()
                }
            case "blockquote":
                if quoteDepth > 0 {
                    quoteDepth -= 1
                    writer.quoteDepth = quoteDepth
                }
                requestBlockBreak()
            case "code", "kbd", "samp", "tt":
                finishInlineCode()
            case "strong", "b":
                closeEmphasis("**")
            case "em", "i", "cite", "dfn", "var":
                closeEmphasis("*")
            case "del", "s", "strike":
                closeEmphasis("~~")
            case "a":
                finishLink()
            case "table":
                handleTableClose()
            case "tr":
                handleTableRowClose()
            case "td", "th":
                handleTableCellClose()
            case "caption":
                handleTableCaptionClose()
            default:
                break
            }
        }

        private mutating func requestBlockBreakAfterBlock(_ name: String) {
            if name == "li" {
                return // The next <li> or the list close provides the break.
            }
            requestBlockBreak()
        }

        // MARK: - Breaks and lists

        private mutating func requestLineBreak() {
            writer.requestLineBreak()
        }

        private mutating func requestBlockBreak() {
            // Inside a list, paragraph breaks degrade to line breaks so items stay items.
            if listStack.isEmpty {
                writer.requestBlockBreak()
            } else {
                writer.requestLineBreak()
            }
        }

        private mutating func startListItem() {
            writer.requestLineBreak()
            let depth = max(listStack.count, 1)
            let indent = String(repeating: "  ", count: depth - 1)
            let marker: String
            if let index = listStack.indices.last, listStack[index].ordered {
                marker = "\(listStack[index].nextIndex). "
                listStack[index].nextIndex += 1
            } else {
                marker = "- "
            }
            writer.writeMarker(indent + marker, flushingSpace: false)
        }

        // MARK: - Emphasis

        private mutating func openEmphasis(_ marker: String) {
            guard preContext == nil, emphasisStack.count < Self.maxEmphasisDepth else {
                return
            }
            emphasisStack.append(marker)
            writer.writeMarker(marker, flushingSpace: true)
        }

        private mutating func closeEmphasis(_ marker: String) {
            guard emphasisStack.last == marker else {
                return // Mis-nested close; leave it rather than corrupt the stack.
            }
            emphasisStack.removeLast()
            writer.writeMarker(marker, flushingSpace: false)
        }

        // MARK: - Inline captures (links and code)

        /// Closes the innermost inline capture. Only pops when the top of the stack matches
        /// the requested kind, so a stray close tag cannot desync captures.
        private mutating func finishLink() {
            guard case .link(let href)? = inlineCaptures.last else {
                return
            }
            inlineCaptures.removeLast()
            emitLink(href: href, text: writer.popCapture() ?? "")
        }

        private mutating func finishInlineCode() {
            guard case .code? = inlineCaptures.last else {
                return
            }
            inlineCaptures.removeLast()
            emitInlineCode(writer.popCapture() ?? "")
        }

        /// Emits and clears every open inline capture, innermost first — called at block
        /// boundaries (browsers auto-close inline elements there) and at end of input, so an
        /// unclosed `<a>`/`<code>` cannot swallow the rest of the page into its buffer.
        private mutating func flushInlineCaptures() {
            while let capture = inlineCaptures.popLast() {
                switch capture {
                case .link(let href):
                    emitLink(href: href, text: writer.popCapture() ?? "")
                case .code:
                    emitInlineCode(writer.popCapture() ?? "")
                }
            }
        }

        private mutating func emitLink(href: String, text: String) {
            let label = escapedLinkLabel(text.trimmingCharacters(in: .whitespacesAndNewlines))
            guard let destination = resolvedLinkDestination(href) else {
                writer.writeMarker(label, flushingSpace: true)
                return
            }
            guard !label.isEmpty else {
                return
            }
            writer.writeMarker("[\(label)](\(destination))", flushingSpace: true)
        }

        private mutating func emitInlineCode(_ content: String) {
            let text = content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                return
            }
            if text.contains("`") {
                writer.writeMarker("`` \(text) ``", flushingSpace: true)
            } else {
                writer.writeMarker("`\(text)`", flushingSpace: true)
            }
        }

        // MARK: - Images

        private mutating func writeImage(_ attributes: [String: String]) {
            let alt = (attributes["alt"] ?? "")
                .components(separatedBy: .whitespacesAndNewlines)
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            let source = attributes["src"] ?? ""
            if source.lowercased().hasPrefix("data:") {
                // Inline base64 images: keep small ones (they render fine in markdown), and
                // summarize big ones instead of flooding the context with base64.
                if source.utf8.count <= Self.maxInlineDataURIBytes {
                    writer.writeMarker("![\(escapedLinkLabel(alt))](\(source))", flushingSpace: true)
                } else {
                    let kilobytes = source.utf8.count / 1024
                    writer.writeText("[inline image\(alt.isEmpty ? "" : " \"\(alt)\"") omitted — \(kilobytes) KB data URI]")
                }
                return
            }
            guard let destination = resolvedLinkDestination(source) else {
                if !alt.isEmpty {
                    writer.writeText(alt)
                }
                return
            }
            writer.writeMarker("![\(escapedLinkLabel(alt))](\(destination))", flushingSpace: true)
        }

        /// Resolves a href/src against the page URL and sanitizes it for a markdown
        /// destination. Returns nil for empty, scripting, or unresolvable targets — the caller
        /// then falls back to plain text.
        private func resolvedLinkDestination(_ raw: String) -> String? {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                return nil
            }
            let lowered = trimmed.lowercased()
            for scheme in ["javascript:", "vbscript:", "data:", "blob:", "about:"] where lowered.hasPrefix(scheme) {
                return nil
            }
            let resolved = URL(string: trimmed, relativeTo: options.baseURL)?.absoluteString ?? trimmed
            // Parentheses, spaces, and control characters break the (…) destination syntax.
            var sanitized = ""
            for scalar in resolved.unicodeScalars {
                switch scalar {
                case "(":
                    sanitized += "%28"
                case ")":
                    sanitized += "%29"
                case " ":
                    sanitized += "%20"
                default:
                    if scalar.value >= 0x20, scalar.value != 0x7F {
                        sanitized.unicodeScalars.append(scalar)
                    }
                }
            }
            return sanitized.isEmpty ? nil : sanitized
        }

        private func escapedLinkLabel(_ label: String) -> String {
            label
                .replacingOccurrences(of: "[", with: "\\[")
                .replacingOccurrences(of: "]", with: "\\]")
        }

        // MARK: - Preformatted blocks

        private mutating func startPre(attributes: [String: String]) {
            guard writer.pushCapture(byteLimit: Self.preByteLimit, preservesWhitespace: true) else {
                return
            }
            preContext = PreContext(language: Self.codeLanguage(fromClass: attributes["class"]))
        }

        private mutating func finishPre() {
            guard let context = preContext, let content = writer.popCapture() else {
                preContext = nil
                return
            }
            preContext = nil
            var body = content
            while body.hasSuffix("\n") {
                body.removeLast()
            }
            while body.hasPrefix("\n") {
                body.removeFirst()
            }
            guard !body.isEmpty else {
                return
            }
            // The fence must be longer than any backtick run in the body — capped, so a
            // hostile block of thousands of backticks cannot inflate the fence itself.
            var longestRun = 0
            var currentRun = 0
            for character in body {
                currentRun = character == "`" ? currentRun + 1 : 0
                longestRun = max(longestRun, currentRun)
            }
            let fence = String(repeating: "`", count: min(max(3, longestRun + 1), Self.maxCodeFenceLength))
            writer.writeBlockLines([fence + context.language] + body.components(separatedBy: "\n") + [fence])
        }

        private static func codeLanguage(fromClass classAttribute: String?) -> String {
            guard let classAttribute else {
                return ""
            }
            for token in classAttribute.split(separator: " ") {
                for prefix in ["language-", "lang-"] where token.hasPrefix(prefix) {
                    let language = token.dropFirst(prefix.count).prefix(24)
                    if !language.isEmpty, language.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "+" || $0 == "-" || $0 == "#" }) {
                        return String(language)
                    }
                }
            }
            return ""
        }

        // MARK: - Tables

        private mutating func handleTableOpen() {
            if table != nil {
                table?.nestedTables += 1
                return
            }
            table = TableContext()
        }

        private mutating func handleTableClose() {
            guard var context = table else {
                return
            }
            if context.nestedTables > 0 {
                context.nestedTables -= 1
                table = context
                return
            }
            closeCellIfOpen()
            flushRowIfOpen()
            renderTable()
        }

        private mutating func handleTableRowOpen() {
            guard table != nil, table?.nestedTables == 0 else {
                return
            }
            closeCellIfOpen()
            flushRowIfOpen()
            table?.currentRow = []
        }

        private mutating func handleTableRowClose() {
            guard table != nil, table?.nestedTables == 0 else {
                return
            }
            closeCellIfOpen()
            flushRowIfOpen()
        }

        private mutating func handleTableCellOpen() {
            guard var context = table, context.nestedTables == 0 else {
                return
            }
            closeCellIfOpen()
            if context.currentRow == nil {
                context.currentRow = []
            }
            context.cellOpen = writer.pushCapture(byteLimit: Self.tableCellByteLimit)
            table = context
        }

        private mutating func handleTableCellClose() {
            closeCellIfOpen()
        }

        private mutating func closeCellIfOpen() {
            guard var context = table, context.cellOpen else {
                return
            }
            context.cellOpen = false
            let text = writer.popCapture() ?? ""
            if var row = context.currentRow {
                if row.count < Self.maxTableColumns {
                    row.append(text.trimmingCharacters(in: .whitespacesAndNewlines))
                }
                context.currentRow = row
            }
            table = context
        }

        private mutating func flushRowIfOpen() {
            guard var context = table, let row = context.currentRow else {
                return
            }
            context.currentRow = nil
            if !row.isEmpty, context.rows.count < Self.maxTableRows {
                context.rows.append(row)
            }
            table = context
        }

        private mutating func handleTableCaptionOpen() {
            guard var context = table, context.nestedTables == 0, !context.captionOpen else {
                return
            }
            context.captionOpen = writer.pushCapture(byteLimit: Self.tableCellByteLimit)
            table = context
        }

        private mutating func handleTableCaptionClose() {
            guard var context = table, context.captionOpen else {
                return
            }
            context.captionOpen = false
            context.caption = writer.popCapture()?.trimmingCharacters(in: .whitespacesAndNewlines)
            table = context
        }

        private mutating func renderTable() {
            guard let context = table else {
                return
            }
            table = nil
            let rows = context.rows
            guard !rows.isEmpty else {
                if let caption = context.caption, !caption.isEmpty {
                    writer.writeBlockLines(["*\(caption)*"])
                }
                return
            }
            let columnCount = min(rows.map(\.count).max() ?? 0, Self.maxTableColumns)
            guard columnCount > 0 else {
                return
            }
            var lines: [String] = []
            if let caption = context.caption, !caption.isEmpty {
                lines.append("*\(caption)*")
                lines.append("")
            }
            func renderRow(_ row: [String]) -> String {
                let padded = (0..<columnCount).map { index in
                    index < row.count ? row[index].replacingOccurrences(of: "|", with: "\\|") : ""
                }
                return "| " + padded.joined(separator: " | ") + " |"
            }
            lines.append(renderRow(rows[0]))
            lines.append("| " + Array(repeating: "---", count: columnCount).joined(separator: " | ") + " |")
            for row in rows.dropFirst() {
                lines.append(renderRow(row))
            }
            writer.writeBlockLines(lines)
        }

        // MARK: - End of input

        private mutating func finishOpenConstructs() {
            // Unclosed captures are flushed innermost-first so their text is not lost.
            if preContext != nil {
                finishPre()
            }
            flushInlineCaptures()
            if table != nil {
                closeCellIfOpen()
                flushRowIfOpen()
                renderTable()
            }
            // Anything still captured (e.g. cells without a table) flushes as plain text.
            while let leftover = writer.popCapture() {
                let text = leftover.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    writer.writeMarker(text, flushingSpace: true)
                }
            }
        }

        // MARK: - Element sets and bounds

        private static let voidElements: Set<String> = [
            "area", "base", "br", "col", "embed", "hr", "img", "input",
            "link", "meta", "param", "source", "track", "wbr"
        ]

        private static let rawTextElements: Set<String> = [
            "script", "style", "textarea", "title", "xmp", "noscript"
        ]

        private static let skippedSubtreeElements: Set<String> = [
            "head", "nav", "aside", "template", "svg", "math", "iframe",
            "object", "canvas", "select", "audio", "video"
        ]

        private static let tableStructureElements: Set<String> = [
            "table", "thead", "tbody", "tfoot", "colgroup", "tr", "td", "th", "caption"
        ]

        /// Elements whose start or end auto-closes open inline captures (browser-style
        /// implicit termination). Trade-off: an HTML5 block-wrapping anchor (`<a><div>…`)
        /// loses its href but keeps ALL of its text; without this, one unclosed `<a>` would
        /// cap the rest of the page at the link buffer's limit.
        private static let blockBoundaryElements: Set<String> = [
            "p", "div", "section", "article", "main", "header", "footer", "figure",
            "figcaption", "fieldset", "form", "details", "address", "dl", "dt", "dd",
            "center", "summary", "h1", "h2", "h3", "h4", "h5", "h6",
            "ul", "ol", "li", "blockquote", "pre", "hr",
            "table", "thead", "tbody", "tfoot", "tr", "td", "th", "caption"
        ]

        private static let maxListDepth = 16
        private static let maxQuoteDepth = 8
        private static let maxEmphasisDepth = 16
        private static let inlineCodeByteLimit = 2048
        private static let linkTextByteLimit = 2048
        private static let preByteLimit = 32_768
        private static let tableCellByteLimit = 1024
        private static let maxTableColumns = 16
        private static let maxTableRows = 200
        private static let maxInlineDataURIBytes = 2048
        private static let maxCodeFenceLength = 16
    }
}
