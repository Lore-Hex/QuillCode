import Foundation

enum ToolArtifactLCOVPreviewBuilder {
    static func lcovPreview(for value: String, kind: ToolArtifactKind) -> ToolArtifactLCOVPreview? {
        guard kind == .file,
              ToolArtifactDocumentPreviewBuilder.documentPreview(for: value, kind: kind)?.extensionLabel.lowercased() == "lcov",
              let fileURL = localArtifactFileURL(for: value)
        else {
            return nil
        }

        do {
            let resourceValues = try fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard resourceValues.isRegularFile == true else { return nil }

            let handle = try FileHandle(forReadingFrom: fileURL)
            defer { try? handle.close() }
            guard let data = try handle.read(upToCount: byteLimit + 1),
                  !data.isEmpty
            else { return nil }

            let isTruncated = data.count > byteLimit
            let previewData = Data(data.prefix(byteLimit))
            guard !previewData.contains(0),
                  let text = String(data: previewData, encoding: .utf8)
            else { return nil }

            return preview(
                from: text,
                byteSizeLabel: resourceValues.fileSize.flatMap(ToolArtifactByteSizeFormatter.label),
                isTruncated: isTruncated
            )
        } catch {
            return nil
        }
    }

    private static func preview(
        from text: String,
        byteSizeLabel: String?,
        isTruncated: Bool
    ) -> ToolArtifactLCOVPreview? {
        var sourceFiles: [SourceFileCoverage] = []
        var current = SourceFileCoverage()
        var sawLCOVRecord = false

        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }

            if line == "end_of_record" {
                appendCurrent(&current, to: &sourceFiles)
                current = SourceFileCoverage()
                continue
            }

            if line.hasPrefix("SF:") {
                appendCurrent(&current, to: &sourceFiles)
                current = SourceFileCoverage(path: String(line.dropFirst(3)))
                sawLCOVRecord = true
            } else if line.hasPrefix("LF:") {
                current.lineFound = intValue(after: "LF:", in: line)
                sawLCOVRecord = true
            } else if line.hasPrefix("LH:") {
                current.lineHit = intValue(after: "LH:", in: line)
                sawLCOVRecord = true
            } else if line.hasPrefix("BRF:") {
                current.branchFound = intValue(after: "BRF:", in: line)
                sawLCOVRecord = true
            } else if line.hasPrefix("BRH:") {
                current.branchHit = intValue(after: "BRH:", in: line)
                sawLCOVRecord = true
            } else if line.hasPrefix("FNF:") {
                current.functionFound = intValue(after: "FNF:", in: line)
                sawLCOVRecord = true
            } else if line.hasPrefix("FNH:") {
                current.functionHit = intValue(after: "FNH:", in: line)
                sawLCOVRecord = true
            } else if line.hasPrefix("DA:") {
                current.observeLineHit(line)
                sawLCOVRecord = true
            } else if line.hasPrefix("FNDA:") {
                current.observeFunctionHit(line)
                sawLCOVRecord = true
            } else if line.hasPrefix("BRDA:") {
                current.observeBranchHit(line)
                sawLCOVRecord = true
            }
        }
        appendCurrent(&current, to: &sourceFiles)

        guard sawLCOVRecord, !sourceFiles.isEmpty else { return nil }
        let sourcePreviewLabels = sourceFiles
            .prefix(sourcePreviewLimit)
            .map(\.previewLabel)

        return ToolArtifactLCOVPreview(
            sourceFileCount: sourceFiles.count,
            lineHitCount: summed(\.lineHit, in: sourceFiles),
            lineFoundCount: summed(\.lineFound, in: sourceFiles),
            branchHitCount: summed(\.branchHit, in: sourceFiles),
            branchFoundCount: summed(\.branchFound, in: sourceFiles),
            functionHitCount: summed(\.functionHit, in: sourceFiles),
            functionFoundCount: summed(\.functionFound, in: sourceFiles),
            byteSizeLabel: byteSizeLabel,
            isTruncated: isTruncated,
            sourcePreviewLabels: sourcePreviewLabels
        )
    }

    private static func appendCurrent(_ current: inout SourceFileCoverage, to sourceFiles: inout [SourceFileCoverage]) {
        guard current.hasCoverage else { return }
        sourceFiles.append(current)
        current = SourceFileCoverage()
    }

    private static func intValue(after prefix: String, in line: String) -> Int? {
        let value = line.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
        guard let int = Int(value), int >= 0 else { return nil }
        return int
    }

    private static func summed(_ keyPath: KeyPath<SourceFileCoverage, Int?>, in sourceFiles: [SourceFileCoverage]) -> Int? {
        var total = 0
        var hasValue = false
        for sourceFile in sourceFiles {
            guard let value = sourceFile[keyPath: keyPath] else { continue }
            total += value
            hasValue = true
        }
        return hasValue ? total : nil
    }

    private static func localArtifactFileURL(for value: String) -> URL? {
        if value.hasPrefix("/") {
            return URL(fileURLWithPath: value)
        }
        guard let url = URL(string: value),
              url.scheme?.lowercased() == "file"
        else { return nil }
        return url
    }

    private struct SourceFileCoverage {
        var path: String?
        var lineHit: Int?
        var lineFound: Int?
        var branchHit: Int?
        var branchFound: Int?
        var functionHit: Int?
        var functionFound: Int?

        var hasCoverage: Bool {
            path != nil || lineHit != nil || lineFound != nil || branchHit != nil || branchFound != nil || functionHit != nil || functionFound != nil
        }

        var previewLabel: String {
            let name = path.map(displayPath) ?? "Unknown source"
            guard let lineHit, let lineFound, lineFound > 0 else { return name }
            let percent = (Double(lineHit) / Double(lineFound)) * 100
            let rounded = (percent * 10).rounded() / 10
            let percentLabel = rounded == rounded.rounded()
                ? "\(Int(rounded))%"
                : String(format: "%.1f%%", rounded)
            return "\(name) · \(percentLabel)"
        }

        mutating func observeLineHit(_ line: String) {
            guard let count = line.split(separator: ",").dropFirst().first.flatMap({ Int($0) }) else {
                return
            }
            lineFound = (lineFound ?? 0) + 1
            if count > 0 {
                lineHit = (lineHit ?? 0) + 1
            } else if lineHit == nil {
                lineHit = 0
            }
        }

        mutating func observeFunctionHit(_ line: String) {
            let parts = line.split(separator: ",", maxSplits: 1)
            guard let countText = parts.first?.dropFirst(5),
                  let count = Int(countText)
            else { return }
            functionFound = (functionFound ?? 0) + 1
            if count > 0 {
                functionHit = (functionHit ?? 0) + 1
            } else if functionHit == nil {
                functionHit = 0
            }
        }

        mutating func observeBranchHit(_ line: String) {
            guard let taken = line.split(separator: ",").last else { return }
            branchFound = (branchFound ?? 0) + 1
            if taken != "-", Int(taken).map({ $0 > 0 }) == true {
                branchHit = (branchHit ?? 0) + 1
            } else if branchHit == nil {
                branchHit = 0
            }
        }

        private func displayPath(_ path: String) -> String {
            let components = path
                .split(separator: "/")
                .suffix(2)
            return components.isEmpty ? path : components.joined(separator: "/")
        }
    }

    private static let byteLimit = 512 * 1024
    private static let sourcePreviewLimit = 6
}
