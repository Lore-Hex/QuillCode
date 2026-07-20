import Foundation

enum ToolArtifactBenchmarkDotNetJSONPreviewBuilder {
    static func benchmarkDotNetJSONPreview(
        for value: String,
        kind: ToolArtifactKind
    ) -> ToolArtifactBenchmarkDotNetJSONPreview? {
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

    private static func preview(
        from object: [String: Any],
        byteSizeLabel: String?
    ) -> ToolArtifactBenchmarkDotNetJSONPreview? {
        let benchmarks = object["Benchmarks"] as? [[String: Any]] ?? []
        let environment = object["HostEnvironmentInfo"] as? [String: Any]
        guard isBenchmarkDotNetReport(object: object, benchmarks: benchmarks, environment: environment) else {
            return nil
        }

        let benchmarkLabels = Array(benchmarks.compactMap(benchmarkLabel).prefix(previewLimit))
        return ToolArtifactBenchmarkDotNetJSONPreview(
            title: stringValue(object["Title"]),
            benchmarkCount: benchmarks.count,
            runtimeLabel: runtimeLabel(from: environment),
            architectureLabel: stringValue(environment?["Architecture"]),
            osLabel: stringValue(environment?["OSVersion"]),
            byteSizeLabel: byteSizeLabel,
            benchmarkPreviewLabels: benchmarkLabels
        )
    }

    private static func isBenchmarkDotNetReport(
        object: [String: Any],
        benchmarks: [[String: Any]],
        environment: [String: Any]?
    ) -> Bool {
        guard !benchmarks.isEmpty else { return false }
        let hasBenchmarkDotNetCaption = stringValue(environment?["BenchmarkDotNetCaption"])?
            .localizedCaseInsensitiveContains("benchmarkdotnet") == true
        let hasBenchmarkNames = benchmarks.contains { benchmarkLabel(from: $0) != nil }
        let hasBenchmarkStatistics = benchmarks.contains { $0["Statistics"] is [String: Any] }
        return hasBenchmarkDotNetCaption
            || (stringValue(object["Title"]) != nil && hasBenchmarkNames)
            || (hasBenchmarkNames && hasBenchmarkStatistics)
    }

    private static func benchmarkLabel(from benchmark: [String: Any]) -> String? {
        let direct = stringValue(benchmark["FullName"])
            ?? stringValue(benchmark["DisplayInfo"])
            ?? stringValue(benchmark["Method"])
        if let direct {
            return sanitizedLabel(direct)
        }

        let namespace = stringValue(benchmark["Namespace"])
        let type = stringValue(benchmark["Type"])
        let method = stringValue(benchmark["Method"])
        let components = [namespace, type, method].compactMap { $0 }
        guard !components.isEmpty else { return nil }
        return sanitizedLabel(components.joined(separator: "."))
    }

    private static func runtimeLabel(from environment: [String: Any]?) -> String? {
        stringValue(environment?["RuntimeVersion"])
            ?? stringValue(environment?["Runtime"])
            ?? stringValue(environment?["RuntimeInformation"])
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

    private static func stringValue(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func sanitizedLabel(_ value: String) -> String {
        let collapsedWhitespace = value
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String((collapsedWhitespace.isEmpty ? "Unknown benchmark" : collapsedWhitespace).prefix(characterLimit))
    }

    private static let byteLimit = 512 * 1_024
    private static let previewLimit = 6
    private static let characterLimit = 96
}
