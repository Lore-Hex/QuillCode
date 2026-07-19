import Foundation

enum ToolArtifactIstanbulPreviewBuilder {
    static func istanbulPreview(for value: String, kind: ToolArtifactKind) -> ToolArtifactIstanbulPreview? {
        guard kind == .file,
              let documentPreview = ToolArtifactDocumentPreviewBuilder.documentPreview(for: value, kind: kind),
              documentPreview.kind == .data,
              documentPreview.extensionLabel.lowercased() == "json",
              let fileURL = localArtifactFileURL(for: value)
        else {
            return nil
        }

        do {
            let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard resourceValues.isRegularFile == true else { return nil }
            let fileSize = max(resourceValues.fileSize ?? 0, 0)
            guard fileSize > 0, fileSize <= byteLimit else { return nil }
            let data = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
            guard !data.contains(0) else { return nil }
            let root = try JSONSerialization.jsonObject(with: data, options: [])
            guard let object = root as? [String: Any] else { return nil }
            return preview(
                from: object,
                byteSizeLabel: ToolArtifactByteSizeFormatter.label(for: fileSize)
            )
        } catch {
            return nil
        }
    }

    private static func preview(from object: [String: Any], byteSizeLabel: String?) -> ToolArtifactIstanbulPreview? {
        if let summaryPreview = summaryPreview(from: object, byteSizeLabel: byteSizeLabel) {
            return summaryPreview
        }

        let files = object
            .compactMap { path, value -> FileCoverage? in
                guard let coverage = value as? [String: Any] else { return nil }
                return FileCoverage(path: path, object: coverage)
            }
            .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        guard !files.isEmpty else { return nil }

        let filePreviewLabels = files
            .prefix(filePreviewLimit)
            .map(\.previewLabel)
        return ToolArtifactIstanbulPreview(
            sourceFileCount: files.count,
            statementCoveredCount: summed(\.statementCoveredCount, in: files),
            statementTotalCount: summed(\.statementTotalCount, in: files),
            branchCoveredCount: summed(\.branchCoveredCount, in: files),
            branchTotalCount: summed(\.branchTotalCount, in: files),
            functionCoveredCount: summed(\.functionCoveredCount, in: files),
            functionTotalCount: summed(\.functionTotalCount, in: files),
            lineCoveredCount: summed(\.lineCoveredCount, in: files),
            lineTotalCount: summed(\.lineTotalCount, in: files),
            byteSizeLabel: byteSizeLabel,
            filePreviewLabels: filePreviewLabels
        )
    }

    private static func summaryPreview(from object: [String: Any], byteSizeLabel: String?) -> ToolArtifactIstanbulPreview? {
        guard let total = object["total"] as? [String: Any],
              let lines = counter(named: "lines", in: total)
                ?? counter(named: "statements", in: total)
        else { return nil }

        let statements = counter(named: "statements", in: total)
        let branches = counter(named: "branches", in: total)
        let functions = counter(named: "functions", in: total)
        let files = object
            .filter { key, value in key != "total" && (value as? [String: Any]).map(isSummaryFileCoverage) == true }
            .sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }
            .map { path, value -> String in
                guard let coverage = value as? [String: Any],
                      let fileLines = counter(named: "lines", in: coverage)
                else { return displayPath(path) }
                return "\(displayPath(path)) · \(coverageLabel(covered: fileLines.covered, total: fileLines.total) ?? "lines unknown")"
            }
            .prefix(filePreviewLimit)

        return ToolArtifactIstanbulPreview(
            sourceFileCount: object.filter { key, value in
                key != "total" && (value as? [String: Any]).map(isSummaryFileCoverage) == true
            }.count,
            statementCoveredCount: statements?.covered,
            statementTotalCount: statements?.total,
            branchCoveredCount: branches?.covered,
            branchTotalCount: branches?.total,
            functionCoveredCount: functions?.covered,
            functionTotalCount: functions?.total,
            lineCoveredCount: lines.covered,
            lineTotalCount: lines.total,
            byteSizeLabel: byteSizeLabel,
            filePreviewLabels: Array(files)
        )
    }

    private static func isSummaryFileCoverage(_ object: [String: Any]) -> Bool {
        counter(named: "lines", in: object) != nil
            || counter(named: "statements", in: object) != nil
            || counter(named: "branches", in: object) != nil
            || counter(named: "functions", in: object) != nil
    }

    private static func counter(named key: String, in object: [String: Any]) -> CoverageCounter? {
        guard let counterObject = object[key] as? [String: Any],
              let total = intValue(counterObject["total"]),
              let covered = intValue(counterObject["covered"]),
              total >= 0,
              covered >= 0
        else { return nil }
        return CoverageCounter(covered: min(covered, total), total: total)
    }

    private static func summed(_ keyPath: KeyPath<FileCoverage, Int>, in files: [FileCoverage]) -> Int {
        files.reduce(0) { $0 + $1[keyPath: keyPath] }
    }

    private static func localArtifactFileURL(for value: String) -> URL? {
        if value.hasPrefix("/") {
            return URL(fileURLWithPath: value)
        }
        guard let url = URL(string: value),
              url.scheme?.lowercased() == "file"
        else {
            return nil
        }
        return url
    }

    private static func intValue(_ value: Any?) -> Int? {
        switch value {
        case let int as Int:
            return int
        case let number as NSNumber:
            return number.intValue
        case let string as String:
            return Int(string)
        default:
            return nil
        }
    }

    private static func displayPath(_ path: String) -> String {
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

    private static func coverageLabel(covered: Int, total: Int) -> String? {
        guard total > 0 else { return nil }
        let percent = (Double(covered) / Double(total)) * 100
        let rounded = (percent * 10).rounded() / 10
        let percentLabel = rounded == rounded.rounded()
            ? "\(Int(rounded))%"
            : String(format: "%.1f%%", rounded)
        return "\(percentLabel)"
    }

    private struct CoverageCounter {
        var covered: Int
        var total: Int
    }

    private struct FileCoverage {
        var path: String
        var statementCoveredCount: Int
        var statementTotalCount: Int
        var branchCoveredCount: Int
        var branchTotalCount: Int
        var functionCoveredCount: Int
        var functionTotalCount: Int
        var lineCoveredCount: Int
        var lineTotalCount: Int

        init?(path: String, object: [String: Any]) {
            let statementCounts = Self.flatCounter(object["s"])
            let functionCounts = Self.flatCounter(object["f"])
            let branchCounts = Self.branchCounter(object["b"])
            let lineCounts = Self.lineCounter(statementMap: object["statementMap"], statementHits: object["s"])

            guard statementCounts.total > 0
                || functionCounts.total > 0
                || branchCounts.total > 0
                || lineCounts.total > 0
            else {
                return nil
            }

            self.path = path
            statementCoveredCount = statementCounts.covered
            statementTotalCount = statementCounts.total
            branchCoveredCount = branchCounts.covered
            branchTotalCount = branchCounts.total
            functionCoveredCount = functionCounts.covered
            functionTotalCount = functionCounts.total
            lineCoveredCount = lineCounts.covered
            lineTotalCount = lineCounts.total
        }

        var previewLabel: String {
            guard let coverage = ToolArtifactIstanbulPreviewBuilder.coverageLabel(
                covered: lineCoveredCount,
                total: lineTotalCount
            ) else {
                return ToolArtifactIstanbulPreviewBuilder.displayPath(path)
            }
            return "\(ToolArtifactIstanbulPreviewBuilder.displayPath(path)) · \(coverage)"
        }

        private static func flatCounter(_ value: Any?) -> CoverageCounter {
            guard let object = value as? [String: Any] else {
                return CoverageCounter(covered: 0, total: 0)
            }
            let hits = object.values.compactMap(ToolArtifactIstanbulPreviewBuilder.intValue)
            return CoverageCounter(
                covered: hits.filter { $0 > 0 }.count,
                total: hits.count
            )
        }

        private static func branchCounter(_ value: Any?) -> CoverageCounter {
            guard let object = value as? [String: Any] else {
                return CoverageCounter(covered: 0, total: 0)
            }
            var covered = 0
            var total = 0
            for value in object.values {
                if let hits = value as? [Any] {
                    for hit in hits.compactMap(ToolArtifactIstanbulPreviewBuilder.intValue) {
                        total += 1
                        if hit > 0 { covered += 1 }
                    }
                } else if let hit = ToolArtifactIstanbulPreviewBuilder.intValue(value) {
                    total += 1
                    if hit > 0 { covered += 1 }
                }
            }
            return CoverageCounter(covered: covered, total: total)
        }

        private static func lineCounter(statementMap: Any?, statementHits: Any?) -> CoverageCounter {
            guard let statementMap = statementMap as? [String: Any],
                  let statementHits = statementHits as? [String: Any]
            else {
                return CoverageCounter(covered: 0, total: 0)
            }

            var coveredLines = Set<Int>()
            var allLines = Set<Int>()
            for (id, value) in statementMap {
                guard let line = lineNumber(in: value) else { continue }
                allLines.insert(line)
                if ToolArtifactIstanbulPreviewBuilder.intValue(statementHits[id]).map({ $0 > 0 }) == true {
                    coveredLines.insert(line)
                }
            }
            return CoverageCounter(covered: coveredLines.count, total: allLines.count)
        }

        private static func lineNumber(in value: Any) -> Int? {
            guard let object = value as? [String: Any] else { return nil }
            if let line = ToolArtifactIstanbulPreviewBuilder.intValue(object["line"]) {
                return line
            }
            guard let start = object["start"] as? [String: Any] else { return nil }
            return ToolArtifactIstanbulPreviewBuilder.intValue(start["line"])
        }
    }

    private static let byteLimit = 512 * 1_024
    private static let filePreviewLimit = 6
    private static let characterLimit = 96
}
