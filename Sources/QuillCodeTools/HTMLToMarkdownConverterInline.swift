import Foundation

extension HTMLToMarkdownConverter {
    mutating func startInlineCode(structural: Bool) {
        guard structural, preContext == nil else {
            return
        }
        if writer.pushCapture(byteLimit: Self.inlineCodeByteLimit) {
            inlineCaptures.append(.code)
        }
    }

    mutating func startLink(attributes: [String: String], structural: Bool) {
        guard structural else {
            return
        }
        if writer.pushCapture(byteLimit: Self.linkTextByteLimit) {
            inlineCaptures.append(.link(href: attributes["href"] ?? ""))
        }
    }

    mutating func finishLink() {
        guard case .link(let href)? = inlineCaptures.last else {
            return
        }
        inlineCaptures.removeLast()
        emitLink(href: href, text: writer.popCapture() ?? "")
    }

    mutating func finishInlineCode() {
        guard case .code? = inlineCaptures.last else {
            return
        }
        inlineCaptures.removeLast()
        emitInlineCode(writer.popCapture() ?? "")
    }

    mutating func flushInlineCaptures() {
        while let capture = inlineCaptures.popLast() {
            switch capture {
            case .link(let href):
                emitLink(href: href, text: writer.popCapture() ?? "")
            case .code:
                emitInlineCode(writer.popCapture() ?? "")
            }
        }
    }

    mutating func emitLink(href: String, text: String) {
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

    mutating func emitInlineCode(_ content: String) {
        let text = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return
        }
        let marker = text.contains("`") ? "`` \(text) ``" : "`\(text)`"
        writer.writeMarker(marker, flushingSpace: true)
    }

    mutating func writeImage(_ attributes: [String: String]) {
        let alt = normalizedImageAlt(attributes["alt"] ?? "")
        let source = attributes["src"] ?? ""
        if source.lowercased().hasPrefix("data:") {
            writeDataImage(source: source, alt: alt)
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

    func resolvedLinkDestination(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        guard !Self.blockedLinkSchemes.contains(where: { trimmed.lowercased().hasPrefix($0) }) else {
            return nil
        }
        let resolved = URL(string: trimmed, relativeTo: options.baseURL)?.absoluteString ?? trimmed
        let sanitized = resolved.unicodeScalars.reduce(into: "") { output, scalar in
            output += markdownDestinationScalar(scalar)
        }
        return sanitized.isEmpty ? nil : sanitized
    }

    func escapedLinkLabel(_ label: String) -> String {
        label
            .replacingOccurrences(of: "[", with: "\\[")
            .replacingOccurrences(of: "]", with: "\\]")
    }

    private static let blockedLinkSchemes = ["javascript:", "vbscript:", "data:", "blob:", "about:"]

    private mutating func writeDataImage(source: String, alt: String) {
        if source.utf8.count <= Self.maxInlineDataURIBytes {
            writer.writeMarker("![\(escapedLinkLabel(alt))](\(source))", flushingSpace: true)
            return
        }
        let kilobytes = source.utf8.count / 1_024
        let label = alt.isEmpty ? "" : " \"\(alt)\""
        writer.writeText("[inline image\(label) omitted — \(kilobytes) KB data URI]")
    }

    private func normalizedImageAlt(_ alt: String) -> String {
        alt.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func markdownDestinationScalar(_ scalar: Unicode.Scalar) -> String {
        switch scalar {
        case "(":
            return "%28"
        case ")":
            return "%29"
        case " ":
            return "%20"
        default:
            return scalar.value >= 0x20 && scalar.value != 0x7F ? String(scalar) : ""
        }
    }
}
