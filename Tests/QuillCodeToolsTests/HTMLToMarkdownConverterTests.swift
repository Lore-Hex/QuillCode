import XCTest
@testable import QuillCodeTools

final class HTMLToMarkdownConverterTests: XCTestCase {
    private func convert(
        _ html: String,
        baseURL: URL? = URL(string: "https://example.com/docs/page"),
        maxOutputBytes: Int = 262_144
    ) -> String {
        HTMLToMarkdown.convert(html, options: HTMLToMarkdownOptions(
            baseURL: baseURL,
            maxOutputBytes: maxOutputBytes
        )).markdown
    }

    // MARK: - Elements

    func testHeadingsAndParagraphs() {
        let markdown = convert("<h1>Title</h1><p>First.</p><h2>Section</h2><p>Second.</p>")
        XCTAssertEqual(markdown, "# Title\n\nFirst.\n\n## Section\n\nSecond.")
    }

    func testHeadAndTitleAreDropped() {
        let markdown = convert("""
        <html><head><title>Page Title</title><meta charset="utf-8"></head>\
        <body><h1>Real Heading</h1></body></html>
        """)
        XCTAssertEqual(markdown, "# Real Heading")
        XCTAssertFalse(markdown.contains("Page Title"))
    }

    func testLinksResolveRelativeToBaseURL() {
        let markdown = convert("<p>See <a href=\"/api/reference\">the API docs</a> now.</p>")
        XCTAssertEqual(markdown, "See [the API docs](https://example.com/api/reference) now.")
    }

    func testJavaScriptLinksBecomePlainText() {
        let markdown = convert("<a href=\"javascript:alert(1)\">click</a>")
        XCTAssertEqual(markdown, "click")
    }

    func testLinkDestinationParenthesesAreEscaped() {
        let markdown = convert("<a href=\"https://en.wikipedia.org/wiki/Swift_(language)\">Swift</a>")
        XCTAssertEqual(markdown, "[Swift](https://en.wikipedia.org/wiki/Swift_%28language%29)")
    }

    func testEmphasisAndInlineCode() {
        let markdown = convert("<p>Use <strong>bold</strong>, <em>italic</em>, and <code>let x</code>.</p>")
        XCTAssertEqual(markdown, "Use **bold**, *italic*, and `let x`.")
    }

    func testInlineCodeContainingBackticksUsesDoubleDelimiters() {
        let markdown = convert("<code>a `b` c</code>")
        XCTAssertEqual(markdown, "`` a `b` c ``")
    }

    func testUnorderedAndNestedLists() {
        let markdown = convert("<ul><li>One</li><li>Two<ul><li>Nested</li></ul></li></ul>")
        XCTAssertEqual(markdown, "- One\n- Two\n  - Nested")
    }

    func testOrderedListNumbering() {
        let markdown = convert("<ol><li>First</li><li>Second</li><li>Third</li></ol>")
        XCTAssertEqual(markdown, "1. First\n2. Second\n3. Third")
    }

    func testPreBecomesFencedCodeBlockWithLanguage() {
        let markdown = convert("<pre><code class=\"language-swift\">let x = 1\nprint(x)</code></pre>")
        XCTAssertEqual(markdown, "```swift\nlet x = 1\nprint(x)\n```")
    }

    func testPreWithHighlighterSpansKeepsTextOnly() {
        let markdown = convert("<pre><span class=\"k\">func</span> <span class=\"n\">go</span>()</pre>")
        XCTAssertEqual(markdown, "```\nfunc go()\n```")
    }

    func testPreContainingBacktickFenceUsesLongerFence() {
        let markdown = convert("<pre>```\ninner\n```</pre>")
        XCTAssertTrue(markdown.hasPrefix("````"), "fence must be longer than any backtick run: \(markdown)")
    }

    func testBlockquote() {
        let markdown = convert("<blockquote><p>Quoted</p></blockquote><p>After</p>")
        XCTAssertEqual(markdown, "> Quoted\n\nAfter")
    }

    func testHorizontalRuleAndLineBreak() {
        let markdown = convert("<p>a<br>b</p><hr><p>c</p>")
        XCTAssertEqual(markdown, "a\nb\n\n---\n\nc")
    }

    func testImages() {
        let markdown = convert("<img src=\"/logo.png\" alt=\"Logo\">")
        XCTAssertEqual(markdown, "![Logo](https://example.com/logo.png)")
    }

    func testSmallDataURIImageIsKept() {
        let markdown = convert("<img src=\"data:image/png;base64,iVBORw0KGgo=\" alt=\"dot\">")
        XCTAssertEqual(markdown, "![dot](data:image/png;base64,iVBORw0KGgo=)")
    }

    func testLargeDataURIImageIsSummarized() {
        let payload = String(repeating: "A", count: 10_000)
        let markdown = convert("<img src=\"data:image/png;base64,\(payload)\" alt=\"big\">")
        XCTAssertFalse(markdown.contains("AAAA"))
        XCTAssertTrue(markdown.contains("omitted"), "large data URIs must not flood the output: \(markdown)")
    }

    func testTableBestEffort() {
        let markdown = convert("""
        <table><tr><th>Name</th><th>Value</th></tr>\
        <tr><td>alpha</td><td>1</td></tr><tr><td>beta | pipe</td><td>2</td></tr></table>
        """)
        XCTAssertEqual(markdown, """
        | Name | Value |
        | --- | --- |
        | alpha | 1 |
        | beta \\| pipe | 2 |
        """)
    }

    func testEntitiesDecoded() {
        let markdown = convert("<p>&lt;tag&gt; &amp; &#65;&#x42; &copy; &nbsp;done</p>")
        XCTAssertTrue(markdown.contains("<tag> & AB ©"))
        XCTAssertTrue(markdown.contains("done"))
    }

    func testInvalidNumericEntitiesBecomeReplacementCharacter() {
        let markdown = convert("<p>&#0; &#xD800; &#x110000; &#xFFFFFFFFFF;</p>")
        XCTAssertFalse(markdown.isEmpty)
        XCTAssertTrue(markdown.unicodeScalars.contains { $0.value == 0xFFFD })
        XCTAssertFalse(markdown.unicodeScalars.contains { $0.value == 0 })
    }

    func testUnknownEntityPassesThroughLiterally() {
        let markdown = convert("<p>&notarealentity; stays</p>")
        XCTAssertEqual(markdown, "&notarealentity; stays")
    }

    // MARK: - Noise stripping

    func testScriptStyleAndNavAreStripped() {
        let markdown = convert("""
        <nav><a href="/">Home</a> | <a href="/about">About</a></nav>\
        <script>var html = "<p>fake</p>";</script>\
        <style>p { color: red }</style>\
        <p>Real content</p>
        """)
        XCTAssertEqual(markdown, "Real content")
    }

    func testCommentsDoctypeAndCDATAAreDropped() {
        let markdown = convert("<!DOCTYPE html><!-- hidden --><p>a<![CDATA[<b>ignored</b>]]>b</p>")
        XCTAssertEqual(markdown, "ab")
    }

    func testWhitespaceCollapses() {
        let markdown = convert("<p>a   lot\n\n of \t space</p>")
        XCTAssertEqual(markdown, "a lot of space")
    }

    // MARK: - Malformed and hostile input

    func testUnclosedTagsDoNotCrash() {
        let markdown = convert("<div><b>unclosed <i>everything <a href=\"/x\">link text")
        XCTAssertTrue(markdown.contains("unclosed"))
        XCTAssertTrue(markdown.contains("everything"))
        XCTAssertTrue(markdown.contains("link text"))
    }

    func testUnclosedLinkDoesNotSwallowFollowingBlocks() {
        // Browsers auto-close inline elements at block boundaries; one missing </a> must not
        // funnel the rest of the page into the link's bounded capture buffer.
        let body = String(repeating: "Paragraph content here. ", count: 500)
        let markdown = convert("<a href=\"/promo\">card<div><p>\(body)</p></div>")
        XCTAssertTrue(markdown.contains("[card](https://example.com/promo)"))
        XCTAssertGreaterThan(markdown.utf8.count, 10_000, "block content after the unclosed link must be kept")
    }

    func testAngleBracketSoupIsTreatedAsText() {
        let markdown = convert("1 < 2 and 3 > 2, <<>> <not-a-tag <p>ok</p>")
        XCTAssertTrue(markdown.contains("1 < 2"))
        XCTAssertTrue(markdown.contains("ok"))
    }

    func testUnterminatedCommentAndScriptAreBounded() {
        XCTAssertEqual(convert("<p>before</p><!-- never closed"), "before")
        XCTAssertEqual(convert("<p>before</p><script>var x = 1;"), "before")
    }

    func testMissingHeadCloseStillEmitsBody() {
        let markdown = convert("<html><head><meta charset=\"utf-8\"><body><p>Visible</p></body></html>")
        XCTAssertEqual(markdown, "Visible")
    }

    func testDeeplyNestedInputIsBoundedAndTerminates() {
        let html = String(repeating: "<div><ul><li><blockquote>", count: 5_000) + "core"
        let markdown = convert(html)
        XCTAssertTrue(markdown.contains("core"))
    }

    func testHugeFlatInputRespectsOutputBudget() {
        let html = "<p>" + String(repeating: "word ", count: 200_000) + "</p>"
        let result = HTMLToMarkdown.convert(html, options: HTMLToMarkdownOptions(maxOutputBytes: 4_096))
        XCTAssertTrue(result.truncated)
        XCTAssertLessThanOrEqual(result.markdown.utf8.count, 4_096)
    }

    func testMismatchedCloseTagsDoNotCorruptOutput() {
        let markdown = convert("<b><i>x</b></i>y</em></strong>")
        XCTAssertTrue(markdown.contains("x"))
        XCTAssertTrue(markdown.contains("y"))
    }

    func testTableWithStrayContentAndNoClose() {
        let markdown = convert("<table>loose<tr><td>cell</td>")
        XCTAssertTrue(markdown.contains("cell"))
        XCTAssertFalse(markdown.contains("loose"), "inter-cell filler must be dropped: \(markdown)")
    }

    func testNulAndControlCharactersAreStripped() {
        let markdown = convert("<p>a\u{0}b\u{1}c\u{7F}d</p>")
        XCTAssertEqual(markdown, "abcd")
    }

    func testGiantAttributeValueIsBounded() {
        let href = String(repeating: "a", count: 100_000)
        let markdown = convert("<a href=\"https://example.com/\(href)\">x</a>")
        XCTAssertLessThan(markdown.utf8.count, 20_000)
    }

    func testEmptyAndWhitespaceOnlyInput() {
        XCTAssertEqual(convert(""), "")
        XCTAssertEqual(convert("   \n\t  "), "")
        XCTAssertEqual(convert("<div>\n  \n</div>"), "")
    }

    func testRawTextCloseTagRequiresTerminator() {
        // "</scripty" inside a script must not end raw-text mode.
        let markdown = convert("<script>a </scripty b</script><p>after</p>")
        XCTAssertEqual(markdown, "after")
    }
}
