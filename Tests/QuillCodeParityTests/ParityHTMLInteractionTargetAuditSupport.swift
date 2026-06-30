import Foundation

struct HTMLPrimitiveHitTargetKindAudit {
    var packageRoot: URL

    private let primitiveMarkers = [
        "WorkspaceHTMLPrimitives.button(",
        "WorkspaceHTMLPrimitives.commandButton(",
        "WorkspaceHTMLPrimitives.buttonAttributes(",
        "WorkspaceHTMLPrimitives.summary("
    ]

    func violations(in sourceFiles: [URL]) throws -> [String] {
        try sourceFiles.flatMap(violations(in:))
    }

    private func violations(in file: URL) throws -> [String] {
        let source = try String(contentsOf: file, encoding: .utf8)
        let relativePath = file.path.replacingOccurrences(
            of: packageRoot.path + "/",
            with: ""
        )
        var violations: [String] = []

        for marker in primitiveMarkers {
            var searchStart = source.startIndex
            while searchStart < source.endIndex,
                  let markerRange = source.range(of: marker, range: searchStart..<source.endIndex) {
                guard let callRange = callRange(in: source, markerRange: markerRange) else {
                    violations.append("\(relativePath):\(lineNumber(in: source, at: markerRange.lowerBound)) unterminated \(marker)")
                    break
                }
                let callText = String(source[callRange])
                if !callText.contains("hitTargetKind:") {
                    violations.append("\(relativePath):\(lineNumber(in: source, at: markerRange.lowerBound)) \(marker) lacks explicit hitTargetKind")
                }
                searchStart = callRange.upperBound
            }
        }

        return violations
    }

    private func callRange(in source: String, markerRange: Range<String.Index>) -> Range<String.Index>? {
        var depth = 1
        var index = markerRange.upperBound

        while index < source.endIndex {
            if source[index] == "/" {
                if let advanced = skipComment(in: source, from: index) {
                    index = advanced
                    continue
                }
            }
            if source[index] == "\"" {
                index = skipString(in: source, quoteIndex: index, rawPoundCount: 0)
                continue
            }
            if source[index] == "#" {
                let rawStringStart = rawStringDelimiter(in: source, from: index)
                if let rawStringStart {
                    index = skipString(
                        in: source,
                        quoteIndex: rawStringStart.quoteIndex,
                        rawPoundCount: rawStringStart.poundCount
                    )
                    continue
                }
            }

            switch source[index] {
            case "(":
                depth += 1
            case ")":
                depth -= 1
                if depth == 0 {
                    return markerRange.lowerBound..<source.index(after: index)
                }
            default:
                break
            }
            index = source.index(after: index)
        }

        return nil
    }

    private func skipComment(in source: String, from index: String.Index) -> String.Index? {
        guard character(after: index, in: source) == "/" || character(after: index, in: source) == "*" else {
            return nil
        }
        if character(after: index, in: source) == "/" {
            var cursor = source.index(after: source.index(after: index))
            while cursor < source.endIndex, source[cursor] != "\n" {
                cursor = source.index(after: cursor)
            }
            return cursor
        }

        var depth = 1
        var cursor = source.index(after: source.index(after: index))
        while cursor < source.endIndex {
            if source[cursor] == "/", character(after: cursor, in: source) == "*" {
                depth += 1
                cursor = source.index(after: source.index(after: cursor))
                continue
            }
            if source[cursor] == "*", character(after: cursor, in: source) == "/" {
                depth -= 1
                cursor = source.index(after: source.index(after: cursor))
                if depth == 0 {
                    return cursor
                }
                continue
            }
            cursor = source.index(after: cursor)
        }
        return source.endIndex
    }

    private func rawStringDelimiter(
        in source: String,
        from index: String.Index
    ) -> (quoteIndex: String.Index, poundCount: Int)? {
        var cursor = index
        var poundCount = 0
        while cursor < source.endIndex, source[cursor] == "#" {
            poundCount += 1
            cursor = source.index(after: cursor)
        }
        guard poundCount > 0, cursor < source.endIndex, source[cursor] == "\"" else {
            return nil
        }
        return (cursor, poundCount)
    }

    private func skipString(
        in source: String,
        quoteIndex: String.Index,
        rawPoundCount: Int
    ) -> String.Index {
        let isTripleQuoted = character(after: quoteIndex, in: source) == "\""
            && character(after: source.index(after: quoteIndex), in: source) == "\""
        var cursor = isTripleQuoted
            ? source.index(after: source.index(after: source.index(after: quoteIndex)))
            : source.index(after: quoteIndex)

        while cursor < source.endIndex {
            if rawPoundCount == 0, source[cursor] == "\\" {
                cursor = source.index(after: cursor)
                if cursor < source.endIndex {
                    cursor = source.index(after: cursor)
                }
                continue
            }

            if source[cursor] == "\"" {
                if isTripleQuoted {
                    guard character(after: cursor, in: source) == "\"",
                          character(after: source.index(after: cursor), in: source) == "\"" else {
                        cursor = source.index(after: cursor)
                        continue
                    }
                    let afterQuotes = source.index(after: source.index(after: source.index(after: cursor)))
                    if let end = endOfRawStringDelimiter(in: source, from: afterQuotes, poundCount: rawPoundCount) {
                        return end
                    }
                    cursor = afterQuotes
                    continue
                }

                let afterQuote = source.index(after: cursor)
                if let end = endOfRawStringDelimiter(in: source, from: afterQuote, poundCount: rawPoundCount) {
                    return end
                }
            }

            cursor = source.index(after: cursor)
        }

        return source.endIndex
    }

    private func endOfRawStringDelimiter(
        in source: String,
        from index: String.Index,
        poundCount: Int
    ) -> String.Index? {
        var cursor = index
        var remaining = poundCount
        while remaining > 0, cursor < source.endIndex, source[cursor] == "#" {
            remaining -= 1
            cursor = source.index(after: cursor)
        }
        return remaining == 0 ? cursor : nil
    }

    private func character(after index: String.Index, in source: String) -> Character? {
        guard index < source.endIndex else { return nil }
        let next = source.index(after: index)
        return next < source.endIndex ? source[next] : nil
    }

    private func lineNumber(in source: String, at index: String.Index) -> Int {
        source[..<index].reduce(1) { partial, character in
            character == "\n" ? partial + 1 : partial
        }
    }
}

struct HTMLSourceInteractionTargetAudit {
    var packageRoot: URL

    private let primitiveMarkers = [
        "WorkspaceHTMLPrimitives.button(",
        "WorkspaceHTMLPrimitives.commandButton(",
        "WorkspaceHTMLPrimitives.buttonAttributes(",
        "WorkspaceHTMLPrimitives.hitTargetAttributes(kind:",
        "WorkspaceHTMLPrimitives.summary("
    ]

    private let hitTargetMarkers = [
        "WorkspaceHTMLPrimitives.ownedHitTargetClass",
        "WorkspaceHTMLPrimitives.linkHitTargetClass",
        "WorkspaceHTMLPrimitives.iconHitTargetClass",
        "WorkspaceHTMLPrimitives.textHitTargetClass",
        "WorkspaceHTMLPrimitives.textEntryHitTargetClass",
        "WorkspaceHTMLPrimitives.segmentedHitTargetClass",
        "WorkspaceHTMLPrimitives.rowHitTargetClass",
        "WorkspaceHTMLPrimitives.switchRowHitTargetClass",
        "WorkspaceHTMLPrimitives.capsuleHitTargetClass",
        "WorkspaceHTMLPrimitives.formActionHitTargetClass",
        "WorkspaceHTMLPrimitives.adjustableHitTargetClass"
    ]

    func violations(in sourceFiles: [URL]) throws -> [String] {
        try sourceFiles.flatMap(violations(in:))
    }

    private func violations(in file: URL) throws -> [String] {
        let lines = try String(contentsOf: file, encoding: .utf8)
            .components(separatedBy: .newlines)
        let relativePath = file.path.replacingOccurrences(
            of: packageRoot.path + "/",
            with: ""
        )
        return lines.enumerated().compactMap { index, line in
            guard containsHTMLInteractiveElement(line) else { return nil }
            if lineHasPrimitiveTargetContract(line) {
                return nil
            }
            if lineHasSharedTargetClass(line) {
                guard lineHasSemanticHitTargetContract(line) else {
                    return "\(relativePath):\(index + 1) generated HTML control uses a shared hit-target class without full semantic data-hit-target-kind/action/source contract"
                }
                return nil
            }
            return "\(relativePath):\(index + 1) generated HTML control lacks shared hit-target primitive"
        }
    }

    private func containsHTMLInteractiveElement(_ line: String) -> Bool {
        line.contains("<button")
            || line.contains("<summary")
            || line.contains("<a ")
            || line.contains("<input")
            || line.contains("<select")
            || line.contains("<textarea")
    }

    private func lineHasPrimitiveTargetContract(_ line: String) -> Bool {
        primitiveMarkers.contains { line.contains($0) }
    }

    private func lineHasSharedTargetClass(_ line: String) -> Bool {
        hitTargetMarkers.contains { line.contains($0) }
    }

    private func lineHasSemanticHitTargetContract(_ line: String) -> Bool {
        if line.contains("WorkspaceHTMLPrimitives.hitTargetAttributes")
            || line.contains("WorkspaceHTMLPrimitives.hitTargetKindAttribute") {
            return true
        }
        return [
            #"data-hit-target-kind"#,
            #"data-hit-target-action"#,
            #"data-hit-target-source"#
        ].allSatisfy { line.contains($0) }
    }
}
