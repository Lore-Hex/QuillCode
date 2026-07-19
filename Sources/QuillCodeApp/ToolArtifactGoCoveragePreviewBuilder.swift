import Foundation

enum ToolArtifactGoCoveragePreviewBuilder {
    static func goCoveragePreview(for value: String, kind: ToolArtifactKind) -> ToolArtifactGoCoveragePreview? {
        guard kind == .file,
              ToolArtifactDocumentPreviewBuilder.documentPreview(for: value, kind: kind)?.extensionLabel.lowercased() == "gocover",
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
    ) -> ToolArtifactGoCoveragePreview? {
        var modeLabel: String?
        var filesByPath: [String: SourceFileCoverage] = [:]
        var blockCount = 0

        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }

            if line.hasPrefix("mode:") {
                modeLabel = sanitizedMode(String(line.dropFirst(5)))
                continue
            }

            guard let block = CoverageBlock(line) else { continue }
            blockCount += 1
            filesByPath[block.path, default: SourceFileCoverage(path: block.path)].record(block)
        }

        let sourceFiles = filesByPath.values
            .filter(\.hasCoverage)
            .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        guard modeLabel != nil, !sourceFiles.isEmpty else { return nil }

        return ToolArtifactGoCoveragePreview(
            modeLabel: modeLabel,
            sourceFileCount: sourceFiles.count,
            blockCount: blockCount,
            statementCoveredCount: sourceFiles.reduce(0) { $0 + $1.statementCoveredCount },
            statementTotalCount: sourceFiles.reduce(0) { $0 + $1.statementTotalCount },
            byteSizeLabel: byteSizeLabel,
            isTruncated: isTruncated,
            sourcePreviewLabels: sourceFiles.prefix(sourcePreviewLimit).map(\.previewLabel)
        )
    }

    private static func sanitizedMode(_ rawMode: String) -> String? {
        let mode = rawMode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard ["set", "count", "atomic"].contains(mode) else { return nil }
        return mode
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

    private struct CoverageBlock {
        var path: String
        var statementCount: Int
        var executionCount: Int

        init?(_ line: String) {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count == 3,
                  let statementCount = Int(parts[1]),
                  let executionCount = Int(parts[2]),
                  statementCount >= 0,
                  executionCount >= 0,
                  let path = Self.path(from: String(parts[0]))
            else { return nil }
            self.path = path
            self.statementCount = statementCount
            self.executionCount = executionCount
        }

        private static func path(from range: String) -> String? {
            guard let colonIndex = range.lastIndex(of: ":") else { return nil }
            let path = String(range[..<colonIndex])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return path.isEmpty ? nil : path
        }
    }

    private struct SourceFileCoverage {
        var path: String
        var statementCoveredCount = 0
        var statementTotalCount = 0

        var hasCoverage: Bool { statementTotalCount > 0 }

        var previewLabel: String {
            guard let coverage = ToolArtifactGoCoveragePreviewBuilder.coverageLabel(
                covered: statementCoveredCount,
                total: statementTotalCount
            ) else {
                return displayPath(path)
            }
            return "\(displayPath(path)) · \(coverage)"
        }

        mutating func record(_ block: CoverageBlock) {
            statementTotalCount += block.statementCount
            if block.executionCount > 0 {
                statementCoveredCount += block.statementCount
            }
        }

        private func displayPath(_ path: String) -> String {
            let collapsedWhitespace = path
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let fallback = collapsedWhitespace.isEmpty ? "Unknown source" : collapsedWhitespace
            let suffix = fallback
                .split(separator: "/")
                .suffix(2)
            let label = suffix.isEmpty ? fallback : suffix.joined(separator: "/")
            return String(label.prefix(characterLimit))
        }
    }

    private static func coverageLabel(covered: Int, total: Int) -> String? {
        guard total > 0 else { return nil }
        let percent = (Double(covered) / Double(total)) * 100
        let rounded = (percent * 10).rounded() / 10
        let percentLabel = rounded == rounded.rounded()
            ? "\(Int(rounded))%"
            : String(format: "%.1f%%", rounded)
        return percentLabel
    }

    private static let byteLimit = 512 * 1024
    private static let sourcePreviewLimit = 6
    private static let characterLimit = 96
}
