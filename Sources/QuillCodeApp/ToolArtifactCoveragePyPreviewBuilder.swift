import Foundation

enum ToolArtifactCoveragePyPreviewBuilder {
    static func coveragePyPreview(for value: String, kind: ToolArtifactKind) -> ToolArtifactCoveragePyPreview? {
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

    private static func preview(from object: [String: Any], byteSizeLabel: String?) -> ToolArtifactCoveragePyPreview? {
        guard let meta = object["meta"] as? [String: Any],
              object["files"] is [String: Any],
              object["totals"] is [String: Any]
        else { return nil }

        let totals = object["totals"] as? [String: Any]
        let files = (object["files"] as? [String: Any] ?? [:])
            .compactMap { path, value -> SourceFileCoverage? in
                guard let fileObject = value as? [String: Any],
                      let summary = fileObject["summary"] as? [String: Any]
                else { return nil }
                return SourceFileCoverage(path: path, summary: summary)
            }
            .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        guard !files.isEmpty else { return nil }

        let totalLines = lineCounter(from: totals) ?? aggregateLines(in: files)
        let totalBranches = branchCounter(from: totals) ?? aggregateBranches(in: files)
        let filePreviewLabels = files
            .prefix(filePreviewLimit)
            .map(\.previewLabel)

        return ToolArtifactCoveragePyPreview(
            versionLabel: stringValue(meta["version"]),
            sourceFileCount: files.count,
            lineCoveredCount: totalLines?.covered,
            lineTotalCount: totalLines?.total,
            branchCoveredCount: totalBranches?.covered,
            branchTotalCount: totalBranches?.total,
            byteSizeLabel: byteSizeLabel,
            filePreviewLabels: filePreviewLabels
        )
    }

    private static func lineCounter(from object: [String: Any]?) -> CoverageCounter? {
        guard let object,
              let covered = intValue(object["covered_lines"]),
              let total = intValue(object["num_statements"]),
              covered >= 0,
              total >= 0
        else { return nil }
        return CoverageCounter(covered: min(covered, total), total: total)
    }

    private static func branchCounter(from object: [String: Any]?) -> CoverageCounter? {
        guard let object,
              let covered = intValue(object["covered_branches"]),
              let total = intValue(object["num_branches"]),
              covered >= 0,
              total >= 0
        else { return nil }
        return CoverageCounter(covered: min(covered, total), total: total)
    }

    private static func aggregateLines(in files: [SourceFileCoverage]) -> CoverageCounter? {
        aggregate(\.lineCoveredCount, \.lineTotalCount, in: files)
    }

    private static func aggregateBranches(in files: [SourceFileCoverage]) -> CoverageCounter? {
        aggregate(\.branchCoveredCount, \.branchTotalCount, in: files)
    }

    private static func aggregate(
        _ coveredPath: KeyPath<SourceFileCoverage, Int?>,
        _ totalPath: KeyPath<SourceFileCoverage, Int?>,
        in files: [SourceFileCoverage]
    ) -> CoverageCounter? {
        var covered = 0
        var total = 0
        var hasCounter = false
        for file in files {
            guard let fileCovered = file[keyPath: coveredPath],
                  let fileTotal = file[keyPath: totalPath]
            else { continue }
            covered += fileCovered
            total += fileTotal
            hasCounter = true
        }
        return hasCounter ? CoverageCounter(covered: covered, total: total) : nil
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

    private static func stringValue(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : String(trimmed.prefix(characterLimit))
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

    private static func coverageLabel(covered: Int?, total: Int?) -> String? {
        guard let covered, let total, total > 0 else { return nil }
        let percent = (Double(covered) / Double(total)) * 100
        let rounded = (percent * 10).rounded() / 10
        let percentLabel = rounded == rounded.rounded()
            ? "\(Int(rounded))%"
            : String(format: "%.1f%%", rounded)
        return percentLabel
    }

    private struct CoverageCounter {
        var covered: Int
        var total: Int
    }

    private struct SourceFileCoverage {
        var path: String
        var lineCoveredCount: Int?
        var lineTotalCount: Int?
        var branchCoveredCount: Int?
        var branchTotalCount: Int?

        init?(path: String, summary: [String: Any]) {
            guard lineCounter(from: summary) != nil || branchCounter(from: summary) != nil else {
                return nil
            }
            self.path = path
            let lines = lineCounter(from: summary)
            lineCoveredCount = lines?.covered
            lineTotalCount = lines?.total
            let branches = branchCounter(from: summary)
            branchCoveredCount = branches?.covered
            branchTotalCount = branches?.total
        }

        var previewLabel: String {
            guard let coverage = ToolArtifactCoveragePyPreviewBuilder.coverageLabel(
                covered: lineCoveredCount,
                total: lineTotalCount
            ) else {
                return ToolArtifactCoveragePyPreviewBuilder.displayPath(path)
            }
            return "\(ToolArtifactCoveragePyPreviewBuilder.displayPath(path)) · \(coverage)"
        }
    }

    private static let byteLimit = 512 * 1_024
    private static let filePreviewLimit = 6
    private static let characterLimit = 96
}
