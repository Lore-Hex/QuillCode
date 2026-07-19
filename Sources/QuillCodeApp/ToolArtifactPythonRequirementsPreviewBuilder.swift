import Foundation

enum ToolArtifactPythonRequirementsPreviewBuilder {
    static func requirementsPreview(
        for value: String,
        kind: ToolArtifactKind
    ) -> ToolArtifactPythonRequirementsPreview? {
        guard kind == .file,
              let fileURL = localArtifactFileURL(for: value),
              isRequirementsFilename(fileURL.lastPathComponent)
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
            let records = requirementRecords(from: text)
            guard records.hasDisplayContent else { return nil }
            return ToolArtifactPythonRequirementsPreview(
                packageCount: records.packageCount,
                pinnedCount: records.pinnedCount,
                rangedCount: records.rangedCount,
                editableCount: records.editableCount,
                includeCount: records.includeCount,
                optionCount: records.optionCount,
                hashCount: records.hashCount,
                sourceHostLabels: Array(records.sourceHosts.prefix(previewLabelLimit)),
                packagePreviewLabels: Array(records.packageLabels.prefix(previewLabelLimit)),
                byteSizeLabel: ToolArtifactByteSizeFormatter.label(for: fileSize)
            )
        } catch {
            return nil
        }
    }

    private static func requirementRecords(from text: String) -> RequirementRecords {
        var records = RequirementRecords()
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = strippedRequirementLine(String(rawLine))
            guard !line.isEmpty else { continue }

            let lowercased = line.lowercased()
            records.hashCount += line.components(separatedBy: "--hash=").count - 1
            records.addHosts(from: line)

            if isIncludeLine(lowercased) {
                records.includeCount += 1
                continue
            }
            if isIndexOrFindLinksLine(lowercased) {
                records.optionCount += 1
                continue
            }
            if lowercased.hasPrefix("--hash=") {
                continue
            }
            if isEditableLine(lowercased) {
                records.editableCount += 1
                if let label = editablePackageLabel(from: line) {
                    records.addPackageLabel(label)
                }
                continue
            }
            guard let requirement = packageRequirement(from: line) else { continue }
            records.packageCount += 1
            if requirement.isPinned {
                records.pinnedCount += 1
            } else if requirement.isRanged {
                records.rangedCount += 1
            }
            records.addPackageLabel(requirement.label)
        }
        return records
    }

    private static func packageRequirement(from line: String) -> PackageRequirement? {
        let withoutEnvironmentMarker = line.split(separator: ";", maxSplits: 1).first.map(String.init) ?? line
        let trimmed = withoutEnvironmentMarker.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.hasPrefix("-"),
              !trimmed.lowercased().hasPrefix("git+"),
              !trimmed.lowercased().hasPrefix("http://"),
              !trimmed.lowercased().hasPrefix("https://")
        else {
            return nil
        }

        if let atRange = trimmed.range(of: " @ ") {
            let name = sanitizedLabel(String(trimmed[..<atRange.lowerBound]))
            guard isPackageNameLike(name) else { return nil }
            return PackageRequirement(label: name, isPinned: false, isRanged: false)
        }

        let operatorRanges = requirementOperators.compactMap { op -> (String, Range<String.Index>)? in
            trimmed.range(of: op).map { (op, $0) }
        }
        let firstOperator = operatorRanges.min { lhs, rhs in
            lhs.1.lowerBound < rhs.1.lowerBound
        }
        let rawName = firstOperator.map { String(trimmed[..<$0.1.lowerBound]) } ?? trimmed
        let name = sanitizedLabel(rawName.split(separator: "[").first.map(String.init) ?? rawName)
        guard isPackageNameLike(name) else { return nil }
        let label = firstOperator.map { op, range in
            let versionSegment = trimmed[range.upperBound...]
                .split(separator: ",", maxSplits: 1)
                .first?
                .split(whereSeparator: \.isWhitespace)
                .first
                .map(String.init) ?? ""
            return sanitizedLabel("\(name)\(op)\(versionSegment)")
        } ?? name
        let operators = Set(operatorRanges.map(\.0))
        return PackageRequirement(
            label: label,
            isPinned: operators.contains("==") || operators.contains("==="),
            isRanged: !operators.isDisjoint(with: rangedOperators)
        )
    }

    private static func strippedRequirementLine(_ value: String) -> String {
        let withoutContinuation = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !withoutContinuation.hasPrefix("#") else { return "" }
        if let commentRange = withoutContinuation.range(of: " #") {
            return String(withoutContinuation[..<commentRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return withoutContinuation
    }

    private static func isIncludeLine(_ lowercased: String) -> Bool {
        lowercased.hasPrefix("-r ")
            || lowercased.hasPrefix("--requirement ")
            || lowercased.hasPrefix("-c ")
            || lowercased.hasPrefix("--constraint ")
    }

    private static func isIndexOrFindLinksLine(_ lowercased: String) -> Bool {
        lowercased.hasPrefix("-i ")
            || lowercased.hasPrefix("--index-url ")
            || lowercased.hasPrefix("--extra-index-url ")
            || lowercased.hasPrefix("-f ")
            || lowercased.hasPrefix("--find-links ")
            || lowercased.hasPrefix("--trusted-host ")
    }

    private static func isEditableLine(_ lowercased: String) -> Bool {
        lowercased.hasPrefix("-e ") || lowercased.hasPrefix("--editable ")
    }

    private static func editablePackageLabel(from line: String) -> String? {
        if let eggRange = line.range(of: "#egg=") {
            let eggName = line[eggRange.upperBound...]
                .split(separator: "&", maxSplits: 1)
                .first
                .map(String.init)
            return eggName.map(sanitizedLabel).flatMap { $0.isEmpty ? nil : $0 }
        }
        let path = line.split(separator: " ").last.map(String.init) ?? line
        let label = sanitizedLabel(URL(string: path)?.lastPathComponent ?? path)
        return label.isEmpty ? nil : label
    }

    private static func isPackageNameLike(_ value: String) -> Bool {
        guard !value.isEmpty else { return false }
        return value.range(of: #"^[A-Za-z0-9][A-Za-z0-9_.-]*$"#, options: .regularExpression) != nil
    }

    private static func hosts(in line: String) -> [String] {
        line.split(whereSeparator: \.isWhitespace).compactMap { token in
            var value = String(token).trimmingCharacters(in: CharacterSet(charactersIn: "\\\",'()[]<>"))
            if value.hasSuffix("\\") {
                value.removeLast()
            }
            if value.lowercased().hasPrefix("git+") {
                value.removeFirst(4)
            }
            guard value.hasPrefix("http://") || value.hasPrefix("https://"),
                  let host = URL(string: value)?.host?.lowercased()
            else {
                return nil
            }
            return sanitizedLabel(host)
        }
    }

    private static func isRequirementsFilename(_ filename: String) -> Bool {
        let lowercased = filename.lowercased()
        return lowercased == "requirements.txt"
            || (lowercased.hasPrefix("requirements-") && lowercased.hasSuffix(".txt"))
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

    private struct PackageRequirement {
        var label: String
        var isPinned: Bool
        var isRanged: Bool
    }

    private struct RequirementRecords {
        var packageCount = 0
        var pinnedCount = 0
        var rangedCount = 0
        var editableCount = 0
        var includeCount = 0
        var optionCount = 0
        var hashCount = 0
        private(set) var packageLabels: [String] = []
        private(set) var sourceHosts: [String] = []
        private var seenPackageLabels = Set<String>()
        private var seenSourceHosts = Set<String>()

        var hasDisplayContent: Bool {
            packageCount > 0
                || editableCount > 0
                || includeCount > 0
                || optionCount > 0
                || hashCount > 0
                || !packageLabels.isEmpty
                || !sourceHosts.isEmpty
        }

        mutating func addPackageLabel(_ label: String) {
            guard !label.isEmpty, !seenPackageLabels.contains(label) else { return }
            seenPackageLabels.insert(label)
            packageLabels.append(label)
        }

        mutating func addHosts(from line: String) {
            for host in ToolArtifactPythonRequirementsPreviewBuilder.hosts(in: line) {
                guard !seenSourceHosts.contains(host) else { continue }
                seenSourceHosts.insert(host)
                sourceHosts.append(host)
            }
        }
    }

    private static let requirementOperators = ["===", "==", "~=", ">=", "<=", "!=", ">", "<"]
    private static let rangedOperators = Set(["~=", ">=", "<=", "!=", ">", "<"])
    private static let byteLimit = 512 * 1_024
    private static let previewLabelLimit = 6
    private static let characterLimit = 120
}
