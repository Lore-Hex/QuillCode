import Foundation

enum HTMLMarkdownElementPolicy {
    static let voidElements: Set<String> = [
        "area", "base", "br", "col", "embed", "hr", "img", "input",
        "link", "meta", "param", "source", "track", "wbr"
    ]

    static let rawTextElements: Set<String> = [
        "script", "style", "textarea", "title", "xmp", "noscript"
    ]

    static let skippedSubtreeElements: Set<String> = [
        "head", "nav", "aside", "template", "svg", "math", "iframe",
        "object", "canvas", "select", "audio", "video"
    ]

    static let tableStructureElements: Set<String> = [
        "table", "thead", "tbody", "tfoot", "colgroup", "tr", "td", "th", "caption"
    ]

    /// Elements whose start or end auto-closes open inline captures, browser-style.
    static let blockBoundaryElements: Set<String> = [
        "p", "div", "section", "article", "main", "header", "footer", "figure",
        "figcaption", "fieldset", "form", "details", "address", "dl", "dt", "dd",
        "center", "summary", "h1", "h2", "h3", "h4", "h5", "h6",
        "ul", "ol", "li", "blockquote", "pre", "hr",
        "table", "thead", "tbody", "tfoot", "tr", "td", "th", "caption"
    ]

    static let maxListDepth = 16
    static let maxQuoteDepth = 8
    static let maxEmphasisDepth = 16
    static let inlineCodeByteLimit = 2048
    static let linkTextByteLimit = 2048
    static let preByteLimit = 32_768
    static let tableCellByteLimit = 1024
    static let maxTableColumns = 16
    static let maxTableRows = 200
    static let maxInlineDataURIBytes = 2048
    static let maxCodeFenceLength = 16

    static func codeLanguage(fromClass classAttribute: String?) -> String {
        guard let classAttribute else {
            return ""
        }
        for token in classAttribute.split(separator: " ") {
            for prefix in ["language-", "lang-"] where token.hasPrefix(prefix) {
                let language = token.dropFirst(prefix.count).prefix(24)
                guard isValidLanguageIdentifier(language) else {
                    continue
                }
                return String(language)
            }
        }
        return ""
    }

    private static func isValidLanguageIdentifier(_ language: Substring) -> Bool {
        !language.isEmpty && language.allSatisfy {
            $0.isLetter || $0.isNumber || $0 == "+" || $0 == "-" || $0 == "#"
        }
    }
}
