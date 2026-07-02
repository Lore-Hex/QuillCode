import Foundation

public struct HTMLToMarkdownOptions: Sendable {
    /// Base URL used to resolve relative link and image targets (usually the fetched page URL).
    public var baseURL: URL?
    /// Hard ceiling on produced markdown; conversion stops (and reports truncation) beyond it.
    public var maxOutputBytes: Int
    /// Element depth beyond which structure is ignored (text still flows). Bounds the cost of
    /// pathologically nested documents.
    public var maxElementDepth: Int

    public init(baseURL: URL? = nil, maxOutputBytes: Int = 262_144, maxElementDepth: Int = 48) {
        self.baseURL = baseURL
        self.maxOutputBytes = maxOutputBytes
        self.maxElementDepth = maxElementDepth
    }
}

/// Hand-rolled HTML-to-markdown conversion for `host.web.fetch`: no parser dependency, no
/// recursion, every buffer bounded. Malformed HTML degrades to readable text instead of failing.
public enum HTMLToMarkdown {
    public static func convert(
        _ html: String,
        options: HTMLToMarkdownOptions = HTMLToMarkdownOptions()
    ) -> (markdown: String, truncated: Bool) {
        var converter = HTMLToMarkdownConverter(html: html, options: options)
        return converter.run()
    }
}

struct HTMLToMarkdownConverter {
    var tokenizer: HTMLTokenizer
    let options: HTMLToMarkdownOptions
    let writer: HTMLMarkdownWriter

    var elementDepth = 0
    var emphasisStack: [String] = []
    var listStack: [ListContext] = []
    var quoteDepth = 0
    var inlineCaptures: [InlineCapture] = []
    var preContext: PreContext?
    var table: TableContext?
    var skip: SkipContext?

    enum InlineCapture {
        case link(href: String)
        case code
    }

    struct ListContext {
        var ordered: Bool
        var nextIndex: Int
    }

    struct PreContext {
        var language: String
    }

    struct TableContext {
        var rows: [[String]] = []
        var currentRow: [String]?
        var cellOpen = false
        var captionOpen = false
        var caption: String?
        var nestedTables = 0
    }

    struct SkipContext {
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

    mutating func handleText(_ text: String) {
        guard skip == nil, !text.isEmpty else {
            return
        }
        if isBetweenTableCells {
            return
        }
        writer.writeText(text)
    }

    var isBetweenTableCells: Bool {
        guard let table else {
            return false
        }
        return !table.cellOpen && !table.captionOpen
    }

    // MARK: - Open tags

    mutating func handleOpenTag(_ name: String, attributes: [String: String], selfClosing: Bool) {
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

        if isBetweenTableCells, !Self.tableStructureElements.contains(name) {
            return
        }

        if preContext != nil {
            handleOpenTagInsidePre(name, attributes: attributes)
            return
        }

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
            openHeading(name)
        case "ul", "ol":
            startList(name, structural: structural)
        case "li":
            startListItem()
        case "blockquote":
            startBlockquote(structural: structural)
        case "pre":
            if structural {
                startPre(attributes: attributes)
            }
        case "code", "kbd", "samp", "tt":
            startInlineCode(structural: structural)
        case "strong", "b":
            openEmphasis("**")
        case "em", "i", "cite", "dfn", "var":
            openEmphasis("*")
        case "del", "s", "strike":
            openEmphasis("~~")
        case "a":
            startLink(attributes: attributes, structural: structural)
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
        default:
            break
        }
    }

    mutating func handleOpenTagWhileSkipping(_ name: String, selfClosing: Bool) {
        guard var context = skip else {
            return
        }
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
        if context.name == "head", name == "body" {
            skip = nil
        }
    }

    // MARK: - Close tags

    mutating func handleCloseTag(_ name: String) {
        if var context = skip {
            if name == context.name {
                context.depth -= 1
                skip = context.depth > 0 ? context : nil
            }
            return
        }
        if Self.skippedSubtreeElements.contains(name) || Self.rawTextElements.contains(name) {
            return
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
            closeList()
        case "blockquote":
            closeBlockquote()
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

    mutating func requestBlockBreakAfterBlock(_ name: String) {
        if name != "li" {
            requestBlockBreak()
        }
    }

    // MARK: - Blocks, lists, and emphasis

    mutating func requestLineBreak() {
        writer.requestLineBreak()
    }

    mutating func requestBlockBreak() {
        if listStack.isEmpty {
            writer.requestBlockBreak()
        } else {
            writer.requestLineBreak()
        }
    }

    mutating func openHeading(_ name: String) {
        requestBlockBreak()
        let level = Int(name.dropFirst()) ?? 1
        writer.writeMarker(String(repeating: "#", count: min(max(level, 1), 6)) + " ", flushingSpace: true)
    }

    mutating func startList(_ name: String, structural: Bool) {
        guard structural, listStack.count < Self.maxListDepth else {
            return
        }
        if listStack.isEmpty {
            requestBlockBreak()
        }
        listStack.append(ListContext(ordered: name == "ol", nextIndex: 1))
    }

    mutating func closeList() {
        if !listStack.isEmpty {
            listStack.removeLast()
        }
        if listStack.isEmpty {
            requestBlockBreak()
        }
    }

    mutating func startListItem() {
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

    mutating func startBlockquote(structural: Bool) {
        guard structural, quoteDepth < Self.maxQuoteDepth else {
            return
        }
        requestBlockBreak()
        quoteDepth += 1
        writer.quoteDepth = quoteDepth
        requestBlockBreak()
    }

    mutating func closeBlockquote() {
        if quoteDepth > 0 {
            quoteDepth -= 1
            writer.quoteDepth = quoteDepth
        }
        requestBlockBreak()
    }

    mutating func openEmphasis(_ marker: String) {
        guard preContext == nil, emphasisStack.count < Self.maxEmphasisDepth else {
            return
        }
        emphasisStack.append(marker)
        writer.writeMarker(marker, flushingSpace: true)
    }

    mutating func closeEmphasis(_ marker: String) {
        guard emphasisStack.last == marker else {
            return
        }
        emphasisStack.removeLast()
        writer.writeMarker(marker, flushingSpace: false)
    }

    // MARK: - End of input

    mutating func finishOpenConstructs() {
        if preContext != nil {
            finishPre()
        }
        flushInlineCaptures()
        if table != nil {
            closeCellIfOpen()
            flushRowIfOpen()
            renderTable()
        }
        while let leftover = writer.popCapture() {
            let text = leftover.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                writer.writeMarker(text, flushingSpace: true)
            }
        }
    }
}
