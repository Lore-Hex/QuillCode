import Foundation

enum MemoryNoteContentPolicy {
    static func validatedWriteContent(_ rawContent: String, maxBytes: Int) throws -> String {
        let content = rawContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else {
            throw MemoryNoteWriteError.empty
        }
        let byteCount = Data(content.utf8).count
        guard byteCount <= maxBytes else {
            throw MemoryNoteWriteError.tooLarge(actual: byteCount, maximum: maxBytes)
        }
        guard !looksSensitive(content) else {
            throw MemoryNoteWriteError.sensitiveContent
        }
        return content
    }

    static func validatedUpdateContent(_ rawContent: String, maxBytes: Int) throws -> String {
        do {
            return try validatedWriteContent(rawContent, maxBytes: maxBytes)
        } catch MemoryNoteWriteError.empty {
            throw MemoryNoteUpdateError.empty
        } catch MemoryNoteWriteError.tooLarge(let actual, let maximum) {
            throw MemoryNoteUpdateError.tooLarge(actual: actual, maximum: maximum)
        } catch MemoryNoteWriteError.sensitiveContent {
            throw MemoryNoteUpdateError.sensitiveContent
        } catch {
            throw MemoryNoteUpdateError.updateFailed
        }
    }

    static func title(from baseName: String) -> String {
        let words = baseName
            .replacingOccurrences(of: "_", with: "-")
            .split(separator: "-")
            .map(String.init)
        guard !words.isEmpty else { return baseName }
        return words
            .map { word in
                guard let first = word.first else { return word }
                return first.uppercased() + word.dropFirst()
            }
            .joined(separator: " ")
    }

    static func titleBase(from content: String) -> String {
        let firstLine = content
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init) ?? "Memory"
        var trimmed = firstLine
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = trimmed.range(
            of: #"^remember\s+(that\s+)?"#,
            options: [.regularExpression, .caseInsensitive]
        ) {
            trimmed.removeSubrange(range)
        }
        trimmed = trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 60 else { return trimmed.isEmpty ? "Memory" : trimmed }
        let end = trimmed.index(trimmed.startIndex, offsetBy: 60)
        return String(trimmed[..<end])
    }

    static func availableFilename(in directory: URL, now: Date, title: String) -> String {
        let timestamp = String(Int(now.timeIntervalSince1970))
        let slug = slug(from: title)
        let base = "manual-\(timestamp)-\(slug)"
        var candidate = "\(base).md"
        var index = 2
        while FileManager.default.fileExists(atPath: directory.appendingPathComponent(candidate).path) {
            candidate = "\(base)-\(index).md"
            index += 1
        }
        return candidate
    }

    private static func slug(from title: String) -> String {
        let lowercased = title.lowercased()
        let scalars = lowercased.unicodeScalars.map { scalar -> Character in
            if CharacterSet.alphanumerics.contains(scalar) {
                return Character(scalar)
            }
            return "-"
        }
        let collapsed = String(scalars)
            .split(separator: "-")
            .prefix(8)
            .joined(separator: "-")
        return collapsed.isEmpty ? "memory" : collapsed
    }

    private static func looksSensitive(_ content: String) -> Bool {
        let patterns = [
            #"-----BEGIN [A-Z ]*PRIVATE KEY-----"#,
            #"(?i)\b(password|passwd|passphrase|api[_ -]?key|secret|token|credential)\s*[:=]"#,
            #"(?i)\b(sk|pk|rk|ghp|github_pat|xox[baprs])[-_][A-Za-z0-9_=\-]{16,}"#
        ]
        return patterns.contains { pattern in
            content.range(of: pattern, options: .regularExpression) != nil
        }
    }
}
