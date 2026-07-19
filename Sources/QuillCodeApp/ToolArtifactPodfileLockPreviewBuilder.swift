import Foundation

enum ToolArtifactPodfileLockPreviewBuilder {
    static func podfileLockPreview(for value: String, kind: ToolArtifactKind) -> ToolArtifactPodfileLockPreview? {
        guard kind == .file,
              let fileURL = localArtifactFileURL(for: value),
              fileURL.lastPathComponent.lowercased() == "podfile.lock"
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
            let parsed = parsedLockfile(from: text)
            guard parsed.podCount > 0 || parsed.dependencyCount > 0 else { return nil }
            let preview = ToolArtifactPodfileLockPreview(
                cocoaPodsVersion: parsed.cocoaPodsVersion,
                podCount: parsed.podCount,
                dependencyCount: parsed.dependencyCount,
                sourceCount: parsed.sourceCount,
                checksumCount: parsed.checksumCount,
                sourcePreviewLabels: parsed.sourceLabels,
                podPreviewLabels: parsed.podLabels,
                byteSizeLabel: ToolArtifactByteSizeFormatter.label(for: fileSize)
            )
            return preview.hasDisplayContent ? preview : nil
        } catch {
            return nil
        }
    }

    private static func parsedLockfile(from text: String) -> ParsedLockfile {
        var section: Section?
        var pods: [PodRecord] = []
        var dependencies = Set<String>()
        var sourceLabels: [String] = []
        var sourceLabelSet = Set<String>()
        var checksumCount = 0
        var cocoaPodsVersion: String?

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let originalLine = String(rawLine)
            let line = originalLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }

            if line.hasPrefix("COCOAPODS:") {
                cocoaPodsVersion = cocoaPodsVersion ?? parsedCocoaPodsVersion(from: line)
                section = .cocoaPods
                continue
            }

            if let nextSection = Section(headerLine: line) {
                section = nextSection
                continue
            }

            switch section {
            case .pods:
                if let pod = podRecord(from: originalLine) {
                    pods.append(pod)
                }
            case .dependencies:
                if let dependency = dependencyName(from: originalLine) {
                    dependencies.insert(dependency)
                }
            case .specRepos:
                appendSpecRepoLabel(from: originalLine, into: &sourceLabels, seen: &sourceLabelSet)
            case .externalSources, .checkoutOptions:
                appendExternalSourceLabel(from: line, into: &sourceLabels, seen: &sourceLabelSet)
            case .specChecksums:
                if checksumLineName(from: originalLine) != nil {
                    checksumCount += 1
                }
            case .cocoaPods:
                cocoaPodsVersion = cocoaPodsVersion ?? sanitizedLabel(line)
            case nil:
                continue
            }
        }

        return ParsedLockfile(
            cocoaPodsVersion: cocoaPodsVersion,
            podCount: pods.count,
            dependencyCount: dependencies.count,
            sourceCount: sourceLabelSet.count,
            sourceLabels: sourceLabels,
            checksumCount: checksumCount,
            podLabels: Array(pods.sorted().prefix(previewLabelLimit)).map(\.label)
        )
    }

    private static func podRecord(from line: String) -> PodRecord? {
        guard line.hasPrefix("  - "), !line.hasPrefix("    - ") else { return nil }
        let trimmed = line.dropFirst(4).trimmingCharacters(in: .whitespaces)
        guard let open = trimmed.lastIndex(of: "("),
              let close = trimmed[open...].firstIndex(of: ")")
        else {
            return nil
        }
        let name = trimmed[..<open].trimmingCharacters(in: .whitespaces)
        let versionStart = trimmed.index(after: open)
        let version = trimmed[versionStart..<close].trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !version.isEmpty else { return nil }
        return PodRecord(
            name: sanitizedLabel(String(name)),
            version: sanitizedLabel(String(version))
        )
    }

    private static func dependencyName(from line: String) -> String? {
        guard line.hasPrefix("  - ") else { return nil }
        let raw = line.dropFirst(4)
        let name = raw.split { $0.isWhitespace || $0 == "(" }.first.map(String.init) ?? ""
        let sanitized = sanitizedLabel(name)
        return sanitized.isEmpty ? nil : sanitized
    }

    private static func checksumLineName(from line: String) -> String? {
        guard line.hasPrefix("  "), let separator = line.firstIndex(of: ":") else { return nil }
        let name = line[..<separator].trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : String(name)
    }

    private static func parsedCocoaPodsVersion(from line: String) -> String? {
        let version = line
            .replacingOccurrences(of: "COCOAPODS:", with: "")
            .trimmingCharacters(in: .whitespaces)
        let sanitized = sanitizedLabel(version)
        return sanitized.isEmpty ? nil : sanitized
    }

    private static func appendSpecRepoLabel(from line: String, into labels: inout [String], seen: inout Set<String>) {
        guard line.hasPrefix("  "), line.hasSuffix(":") else { return }
        let label = sanitizedLabel(String(line.dropLast()).trimmingCharacters(in: .whitespaces))
        append(label, into: &labels, seen: &seen)
    }

    private static func appendExternalSourceLabel(from line: String, into labels: inout [String], seen: inout Set<String>) {
        if let host = hosts(in: line).first {
            append(host, into: &labels, seen: &seen)
            return
        }
        guard line.hasPrefix(":path:") else { return }
        let path = line.replacingOccurrences(of: ":path:", with: "").trimmingCharacters(in: .whitespaces)
        if !path.isEmpty {
            append("path: \(sanitizedLabel(path))", into: &labels, seen: &seen)
        }
    }

    private static func append(_ label: String, into labels: inout [String], seen: inout Set<String>) {
        guard !label.isEmpty, seen.insert(label).inserted else { return }
        guard labels.count < previewLabelLimit else { return }
        labels.append(label)
    }

    private static func hosts(in value: String) -> [String] {
        value
            .split { $0.isWhitespace || $0 == "," }
            .compactMap { token in
                var text = String(token).trimmingCharacters(in: CharacterSet(charactersIn: "\\\",'()[]{}<>"))
                if text.lowercased().hasPrefix("git+") {
                    text.removeFirst(4)
                }
                guard text.hasPrefix("http://") || text.hasPrefix("https://"),
                      let host = URL(string: text)?.host?.lowercased()
                else {
                    return nil
                }
                return sanitizedLabel(host)
            }
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

    private enum Section {
        case pods
        case dependencies
        case specRepos
        case externalSources
        case checkoutOptions
        case specChecksums
        case cocoaPods

        init?(headerLine: String) {
            switch headerLine {
            case "PODS:":
                self = .pods
            case "DEPENDENCIES:":
                self = .dependencies
            case "SPEC REPOS:":
                self = .specRepos
            case "EXTERNAL SOURCES:":
                self = .externalSources
            case "CHECKOUT OPTIONS:":
                self = .checkoutOptions
            case "SPEC CHECKSUMS:":
                self = .specChecksums
            case "COCOAPODS:":
                self = .cocoaPods
            default:
                return nil
            }
        }
    }

    private struct ParsedLockfile {
        var cocoaPodsVersion: String?
        var podCount: Int
        var dependencyCount: Int
        var sourceCount: Int
        var sourceLabels: [String]
        var checksumCount: Int
        var podLabels: [String]
    }

    private struct PodRecord: Comparable {
        var name: String
        var version: String

        var label: String {
            sanitizedLabel("\(name)@\(version)")
        }

        static func < (lhs: PodRecord, rhs: PodRecord) -> Bool {
            lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    private static let byteLimit = 512 * 1_024
    private static let previewLabelLimit = 6
    private static let characterLimit = 120
}
