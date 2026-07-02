import AppKit
import Foundation
import UniformTypeIdentifiers

struct QuillCodeDesktopTranscriptExportResult: Equatable, Sendable {
    let url: URL
}

@MainActor
protocol QuillCodeMarkdownExportDestination {
    func write(markdown: String, suggestedFileName: String) throws -> URL?
}

@MainActor
struct MacMarkdownExportDestination: QuillCodeMarkdownExportDestination {
    func write(markdown: String, suggestedFileName: String) throws -> URL? {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = suggestedFileName
        if let markdownType = UTType(filenameExtension: "md") {
            panel.allowedContentTypes = [markdownType]
        }

        guard panel.runModal() == .OK, let url = panel.url else {
            return nil
        }
        try markdown.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}

@MainActor
struct QuillCodeDesktopTranscriptExportCoordinator {
    private let destination: any QuillCodeMarkdownExportDestination

    init(destination: any QuillCodeMarkdownExportDestination = MacMarkdownExportDestination()) {
        self.destination = destination
    }

    func exportConversation(
        title: String,
        markdown: String
    ) throws -> QuillCodeDesktopTranscriptExportResult? {
        guard !markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        guard let url = try destination.write(
            markdown: markdown,
            suggestedFileName: Self.suggestedFileName(for: title)
        ) else {
            return nil
        }
        return QuillCodeDesktopTranscriptExportResult(url: url)
    }

    static func suggestedFileName(for title: String) -> String {
        let sanitizedStem = sanitizedFileStem(for: title)
        let stem = sanitizedStem.isEmpty ? "Conversation" : sanitizedStem
        return stem.hasSuffix(".md") ? stem : "\(stem).md"
    }

    private static func sanitizedFileStem(for title: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " .-_"))
        let characters = title.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? String(scalar) : "-"
        }
        let collapsed = characters.joined()
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s*-\s*"#, with: "-", options: .regularExpression)
            .replacingOccurrences(of: #"-{2,}"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: " .-_"))
        return collapsed
    }
}
