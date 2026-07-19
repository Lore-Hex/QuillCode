import Foundation

enum ToolArtifactSARIFPreviewBuilder {
    static func sarifPreview(for value: String, kind: ToolArtifactKind) -> ToolArtifactSARIFPreview? {
        guard kind == .file,
              ToolArtifactDocumentPreviewBuilder.documentPreview(for: value, kind: kind)?.extensionLabel.lowercased() == "sarif",
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
            guard !data.contains(0),
                  let root = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                  let runs = root["runs"] as? [[String: Any]]
            else {
                return nil
            }
            let preview = preview(from: root, runs: runs, fileSize: fileSize)
            return preview.hasDisplayContent ? preview : nil
        } catch {
            return nil
        }
    }

    private static func preview(from root: [String: Any], runs: [[String: Any]], fileSize: Int) -> ToolArtifactSARIFPreview {
        var resultCount = 0
        var errorCount = 0
        var warningCount = 0
        var noteCount = 0
        var noneCount = 0
        var toolLabels: [String] = []
        var seenTools = Set<String>()
        var ruleLabels: [String] = []
        var seenRules = Set<String>()

        for run in runs {
            appendToolLabels(from: run, into: &toolLabels, seen: &seenTools)
            appendRuleLabels(from: run, into: &ruleLabels, seen: &seenRules)

            let results = run["results"] as? [[String: Any]] ?? []
            resultCount += results.count
            for result in results {
                switch (result["level"] as? String)?.lowercased() {
                case "error":
                    errorCount += 1
                case "note":
                    noteCount += 1
                case "none":
                    noneCount += 1
                default:
                    warningCount += 1
                }
                appendResultRuleLabel(from: result, into: &ruleLabels, seen: &seenRules)
            }
        }

        return ToolArtifactSARIFPreview(
            versionLabel: sanitizedLabel(root["version"] as? String),
            runCount: runs.count,
            resultCount: resultCount,
            errorCount: errorCount,
            warningCount: warningCount,
            noteCount: noteCount,
            noneCount: noneCount,
            byteSizeLabel: ToolArtifactByteSizeFormatter.label(for: fileSize),
            toolPreviewLabels: Array(toolLabels.prefix(previewLabelLimit)),
            rulePreviewLabels: Array(ruleLabels.prefix(previewLabelLimit))
        )
    }

    private static func appendToolLabels(
        from run: [String: Any],
        into labels: inout [String],
        seen: inout Set<String>
    ) {
        guard let tool = run["tool"] as? [String: Any],
              let driver = tool["driver"] as? [String: Any],
              let name = sanitizedLabel(driver["name"] as? String),
              !seen.contains(name)
        else {
            return
        }
        seen.insert(name)
        labels.append(name)
    }

    private static func appendRuleLabels(
        from run: [String: Any],
        into labels: inout [String],
        seen: inout Set<String>
    ) {
        guard let tool = run["tool"] as? [String: Any],
              let driver = tool["driver"] as? [String: Any],
              let rules = driver["rules"] as? [[String: Any]]
        else {
            return
        }
        for rule in rules {
            guard labels.count < previewLabelLimit,
                  let ruleID = sanitizedLabel(rule["id"] as? String),
                  !seen.contains(ruleID)
            else {
                continue
            }
            seen.insert(ruleID)
            labels.append(ruleID)
        }
    }

    private static func appendResultRuleLabel(
        from result: [String: Any],
        into labels: inout [String],
        seen: inout Set<String>
    ) {
        guard labels.count < previewLabelLimit,
              let ruleID = sanitizedLabel(result["ruleId"] as? String),
              !seen.contains(ruleID)
        else {
            return
        }
        seen.insert(ruleID)
        labels.append(ruleID)
    }

    private static func sanitizedLabel(_ label: String?) -> String? {
        guard let label else { return nil }
        let collapsedWhitespace = label
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !collapsedWhitespace.isEmpty else { return nil }
        return String(collapsedWhitespace.prefix(labelCharacterLimit))
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

    private static let byteLimit = 512 * 1_024
    private static let previewLabelLimit = 6
    private static let labelCharacterLimit = 80
}
