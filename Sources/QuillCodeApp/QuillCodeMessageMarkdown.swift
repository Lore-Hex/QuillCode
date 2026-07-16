import SwiftUI

/// Splits a message into renderable markdown blocks: fenced code blocks, headings, bulleted /
/// numbered lists, and prose paragraphs.
///
/// Deliberately tiny and pure (fully unit-testable). Block-level constructs handled: the ``` fence
/// (because it breaks hardest as plain text), ATX headings (`#`/`##`/`###`), and unordered/ordered
/// lists (`- `, `* `, `1. `) — the backbone of coding-agent answers, which otherwise render as a flat
/// monotone slab with literal `## ` / `- ` prefixes. Everything else is prose whose INLINE markdown
/// (bold, italics, `code`, links) SwiftUI renders natively via `AttributedString(markdown:)`. Unclosed
/// fences are treated as code to the end of the message — a streaming reply's half-arrived code block
/// must render as code, not as a stray ``` line.
enum MessageMarkdownBlocks {
    enum Block: Equatable {
        case paragraph(String)
        case heading(level: Int, text: String)
        case list(ordered: Bool, items: [String])
        case code(language: String?, content: String)
    }

    /// Strips U+FFFD replacement characters (the "diamond question mark") at DISPLAY time. They are
    /// unrecoverable transport corruption — a server that lossy-decoded a split emoji — and carry no
    /// meaning a reader could use; Codex-quality rendering shows clean text, not the noise. The raw
    /// transcript record keeps the original bytes untouched (Copy still yields exactly what arrived).
    static func strippingReplacementCharacters(_ text: String) -> String {
        guard text.contains("\u{FFFD}") else { return text }
        var cleaned = text.replacingOccurrences(of: "\u{FFFD}", with: "")
        // Collapse the doubled space a mid-sentence strip leaves behind ("test_add ␣␣" → one space)
        // and the dangling space a line-end strip leaves before the newline.
        while cleaned.contains("  ") {
            cleaned = cleaned.replacingOccurrences(of: "  ", with: " ")
        }
        while cleaned.contains(" \n") {
            cleaned = cleaned.replacingOccurrences(of: " \n", with: "\n")
        }
        while cleaned.hasSuffix(" ") {
            cleaned.removeLast()
        }
        return cleaned
    }

    static func parse(_ text: String) -> [Block] {
        var blocks: [Block] = []
        var prose: [Substring] = []
        var listItems: [String] = []
        var listOrdered = false
        var inList = false
        var codeLines: [Substring] = []
        var codeLanguage: String?
        var inCode = false

        func flushProse() {
            let joined = prose.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !joined.isEmpty { blocks.append(.paragraph(joined)) }
            prose = []
        }

        func flushList() {
            if !listItems.isEmpty { blocks.append(.list(ordered: listOrdered, items: listItems)) }
            listItems = []
            inList = false
        }

        func flushCode() {
            blocks.append(.code(language: codeLanguage, content: codeLines.joined(separator: "\n")))
            codeLines = []
            codeLanguage = nil
        }

        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                if inCode {
                    flushCode()
                } else {
                    flushProse()
                    flushList()
                    let language = trimmed.dropFirst(3).trimmingCharacters(in: .whitespaces)
                    codeLanguage = language.isEmpty ? nil : language
                }
                inCode.toggle()
                continue
            }
            if inCode {
                codeLines.append(line)
                continue
            }
            if let heading = Self.headingMatch(trimmed) {
                flushProse()
                flushList()
                blocks.append(.heading(level: heading.level, text: heading.text))
                continue
            }
            if let item = Self.listItemMatch(trimmed) {
                flushProse()
                if inList && listOrdered != item.ordered { flushList() }
                inList = true
                listOrdered = item.ordered
                listItems.append(item.text)
                continue
            }
            if trimmed.isEmpty {
                if inList { flushList() }
                prose.append(line)
                continue
            }
            // A non-blank, non-item line ends any open list before it joins the prose paragraph.
            if inList { flushList() }
            prose.append(line)
        }
        if inCode {
            flushCode()
        } else {
            flushProse()
            flushList()
        }
        return blocks
    }

    /// An ATX heading `#`/`##`/`###` (levels 4-6 stay prose — a coding answer rarely nests that deep and
    /// the visual scale would be indistinguishable from body). Requires a space after the hashes so a
    /// bare `#hashtag` or a `#` inside prose is not misread.
    static func headingMatch(_ trimmed: String) -> (level: Int, text: String)? {
        guard trimmed.hasPrefix("#") else { return nil }
        var level = 0
        for character in trimmed {
            if character == "#" { level += 1 } else { break }
        }
        guard (1...3).contains(level) else { return nil }
        let rest = trimmed.dropFirst(level)
        guard rest.first == " " else { return nil }
        let heading = rest.trimmingCharacters(in: .whitespaces)
        guard !heading.isEmpty else { return nil }
        return (level, heading)
    }

    /// A list item: `- `, `* `, or `N. `. The trailing space is required so `*italics*` and `**bold**`
    /// (no space after the marker) are not mistaken for bullets.
    static func listItemMatch(_ trimmed: String) -> (ordered: Bool, text: String)? {
        if let first = trimmed.first, first == "-" || first == "*" {
            let rest = trimmed.dropFirst()
            guard rest.first == " " else { return nil }
            let item = rest.trimmingCharacters(in: .whitespaces)
            guard !item.isEmpty else { return nil }
            return (false, item)
        }
        let digits = trimmed.prefix { $0.isNumber }
        guard !digits.isEmpty else { return nil }
        let afterDigits = trimmed.dropFirst(digits.count)
        guard afterDigits.first == "." else { return nil }
        let rest = afterDigits.dropFirst()
        guard rest.first == " " else { return nil }
        let item = rest.trimmingCharacters(in: .whitespaces)
        guard !item.isEmpty else { return nil }
        return (true, item)
    }

    /// Inline markdown for one prose paragraph or list item, preserving the author's line breaks.
    /// Returns nil when the text has no markdown to render (so the caller can use a plain Text fast
    /// path) or when parsing fails (never render a WRONG interpretation — fall back to literal text).
    /// Inline `code` spans are tinted with the cyan accent so identifiers/filenames/flags — the exact
    /// tokens a coder scans for — pop against 13pt prose instead of blending in.
    static func inlineAttributed(_ text: String) -> AttributedString? {
        guard text.contains("*") || text.contains("`") || text.contains("_") || text.contains("[") else {
            return nil
        }
        guard var attributed = try? AttributedString(
            markdown: text,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace
            )
        ) else {
            return nil
        }
        let codeRanges = attributed.runs.compactMap { run -> Range<AttributedString.Index>? in
            guard let intent = run.inlinePresentationIntent, intent.contains(.code) else { return nil }
            return run.range
        }
        for range in codeRanges {
            attributed[range].foregroundColor = QuillCodePalette.blue
        }
        return attributed
    }
}

/// Renders an assistant message's markdown: fenced code blocks as language-labelled monospaced panels,
/// headings as a real type hierarchy, bulleted/numbered lists with hanging indents, and prose with
/// inline styling (bold / italics / `code` / links). User messages stay verbatim — what you typed is
/// what you see. Mirrors the block treatment in E2E/harness/index.html.
struct QuillCodeMessageMarkdownView: View {
    var text: String

    var body: some View {
        let displayText = MessageMarkdownBlocks.strippingReplacementCharacters(text)
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(MessageMarkdownBlocks.parse(displayText).enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
    }

    @ViewBuilder
    private func blockView(_ block: MessageMarkdownBlocks.Block) -> some View {
        switch block {
        case .paragraph(let prose):
            proseText(prose)
        case .heading(let level, let heading):
            Text(heading)
                .font(.system(size: headingSize(level), weight: .semibold))
                .foregroundStyle(QuillCodePalette.text)
                .textSelection(.enabled)
                .padding(.top, level == 1 ? 4 : 2)
        case .list(let ordered, let items):
            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(ordered ? "\(index + 1)." : "•")
                            .font(.body)
                            .monospacedDigit()
                            .foregroundStyle(QuillCodePalette.muted)
                            .frame(minWidth: ordered ? 20 : 10, alignment: .trailing)
                        proseText(item)
                    }
                }
            }
        case .code(let language, let content):
            codeBlock(language: language, content: content)
        }
    }

    @ViewBuilder
    private func proseText(_ prose: String) -> some View {
        if let attributed = MessageMarkdownBlocks.inlineAttributed(prose) {
            Text(attributed)
                .font(.body)
                .lineSpacing(6)
                .textSelection(.enabled)
        } else {
            Text(prose)
                .font(.body)
                .lineSpacing(6)
                .textSelection(.enabled)
        }
    }

    private func codeBlock(language: String?, content: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let language {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left.forwardslash.chevron.right")
                        .font(.caption2)
                        .foregroundStyle(QuillCodePalette.faint)
                    Text(language.lowercased())
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(QuillCodePalette.muted)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                Divider().overlay(QuillCodePalette.line)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                Text(content)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(QuillCodePalette.text)
                    .textSelection(.enabled)
                    .padding(10)
            }
        }
        .background(QuillCodePalette.panel3)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(QuillCodePalette.line, lineWidth: 1)
        )
    }

    private func headingSize(_ level: Int) -> CGFloat {
        switch level {
        case 1: return 18
        case 2: return 16
        default: return 14
        }
    }
}
