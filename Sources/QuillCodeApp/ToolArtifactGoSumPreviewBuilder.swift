import Foundation

enum ToolArtifactGoSumPreviewBuilder {
    static func goSumPreview(for value: String, kind: ToolArtifactKind) -> ToolArtifactGoSumPreview? {
        guard kind == .file,
              let fileURL = localArtifactFileURL(for: value),
              fileURL.lastPathComponent.lowercased() == "go.sum"
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
                  let text = String(data: data, encoding: .utf8)
            else {
                return nil
            }
            let entries = sumEntries(from: text)
            guard !entries.isEmpty else { return nil }
            let preview = preview(
                from: entries,
                byteSizeLabel: ToolArtifactByteSizeFormatter.label(for: fileSize)
            )
            return preview.hasDisplayContent ? preview : nil
        } catch {
            return nil
        }
    }

    private static func preview(from entries: [SumEntry], byteSizeLabel: String?) -> ToolArtifactGoSumPreview {
        let modules = Dictionary(grouping: entries, by: \.modulePath)
        let hostLabels = sourceHostLabels(from: entries)
        let moduleLabels = modules.keys
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            .prefix(previewLabelLimit)
            .map(sanitizedLabel)
        return ToolArtifactGoSumPreview(
            moduleCount: modules.count,
            versionCount: Set(entries.map(\.version)).count,
            checksumCount: entries.count,
            goModChecksumCount: entries.filter(\.isGoModChecksum).count,
            sourceHostLabels: hostLabels,
            modulePreviewLabels: Array(moduleLabels),
            byteSizeLabel: byteSizeLabel
        )
    }

    private static func sumEntries(from text: String) -> [SumEntry] {
        text.split(whereSeparator: \.isNewline).compactMap { line in
            let fields = line.split(separator: " ", omittingEmptySubsequences: true)
            guard fields.count == 3,
                  fields[2].hasPrefix("h1:"),
                  !fields[0].contains("\\"),
                  !fields[1].contains("\\")
            else {
                return nil
            }
            let modulePath = sanitizedLabel(String(fields[0]))
            let version = sanitizedLabel(String(fields[1]))
            guard !modulePath.isEmpty,
                  !version.isEmpty,
                  version.hasPrefix("v")
            else {
                return nil
            }
            return SumEntry(modulePath: modulePath, version: version)
        }
    }

    private static func sourceHostLabels(from entries: [SumEntry]) -> [String] {
        var labels: [String] = []
        var seen = Set<String>()
        for entry in entries {
            guard labels.count < previewLabelLimit,
                  let host = sourceHost(from: entry.modulePath),
                  !seen.contains(host)
            else {
                continue
            }
            seen.insert(host)
            labels.append(sanitizedLabel(host))
        }
        return labels
    }

    private static func sourceHost(from modulePath: String) -> String? {
        guard let firstComponent = modulePath.split(separator: "/").first,
              firstComponent.contains(".")
        else {
            return nil
        }
        return String(firstComponent).lowercased()
    }

    private static func sanitizedLabel(_ value: String) -> String {
        let collapsedWhitespace = value
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(collapsedWhitespace.prefix(characterLimit))
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

    private struct SumEntry {
        var modulePath: String
        var version: String

        var isGoModChecksum: Bool {
            version.hasSuffix("/go.mod")
        }
    }

    private static let byteLimit = 512 * 1_024
    private static let previewLabelLimit = 6
    private static let characterLimit = 120
}
