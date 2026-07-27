import Foundation

enum ToolArtifactSpotBugsPreviewBuilder {
    static func spotBugsPreview(for value: String, kind: ToolArtifactKind) -> ToolArtifactSpotBugsPreview? {
        guard kind == .file,
              let documentPreview = ToolArtifactDocumentPreviewBuilder.documentPreview(for: value, kind: kind),
              documentPreview.kind == .data,
              documentPreview.extensionLabel.lowercased() == "xml",
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

            let collector = SpotBugsPreviewCollector()
            let parser = XMLParser(data: data)
            parser.delegate = collector
            parser.shouldProcessNamespaces = false
            parser.shouldReportNamespacePrefixes = true
            guard parser.parse(),
                  let preview = collector.preview(fileSize: fileSize)
            else {
                return nil
            }
            return preview.hasDisplayContent ? preview : nil
        } catch {
            return nil
        }
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
}

private final class SpotBugsPreviewCollector: NSObject, XMLParserDelegate {
    private var depth = 0
    private var rootElementLabel: String?
    private var bugCount = 0
    private var classLabels: [String] = []
    private var typeLabels: [String] = []
    private var categoryLabels: [String] = []
    private var priorityOneCount = 0
    private var priorityTwoCount = 0
    private var priorityThreeCount = 0
    private var otherPriorityCount = 0

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let label = qualifiedElementName(elementName: elementName, qName: qName)
        if depth == 0 {
            rootElementLabel = label
        }
        if label == "BugInstance" {
            recordBug(attributeDict)
        } else if label == "Class" {
            recordClass(attributeDict)
        }
        depth += 1
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        depth = max(0, depth - 1)
    }

    func preview(fileSize: Int) -> ToolArtifactSpotBugsPreview? {
        guard rootElementLabel == "BugCollection",
              bugCount > 0 || !classLabels.isEmpty
        else {
            return nil
        }

        return ToolArtifactSpotBugsPreview(
            bugCount: bugCount,
            classCount: classLabels.count,
            priorityOneCount: priorityOneCount,
            priorityTwoCount: priorityTwoCount,
            priorityThreeCount: priorityThreeCount,
            otherPriorityCount: otherPriorityCount,
            byteSizeLabel: ToolArtifactByteSizeFormatter.label(for: fileSize),
            typePreviewLabels: Array(typeLabels.prefix(previewLabelLimit)),
            categoryPreviewLabels: Array(categoryLabels.prefix(previewLabelLimit)),
            classPreviewLabels: Array(classLabels.prefix(previewLabelLimit))
        )
    }

    private func recordBug(_ attributes: [String: String]) {
        bugCount += 1
        switch sanitizedLabel(attributes["priority"]).flatMap(Int.init) {
        case 1:
            priorityOneCount += 1
        case 2:
            priorityTwoCount += 1
        case 3:
            priorityThreeCount += 1
        default:
            otherPriorityCount += 1
        }
        appendUnique(sanitizedLabel(attributes["type"]), to: &typeLabels)
        appendUnique(sanitizedLabel(attributes["category"]), to: &categoryLabels)
    }

    private func recordClass(_ attributes: [String: String]) {
        appendUnique(sanitizedClassLabel(attributes["classname"]), to: &classLabels)
    }

    private func appendUnique(_ label: String?, to labels: inout [String]) {
        guard let label, !labels.contains(label) else { return }
        labels.append(label)
    }

    private func sanitizedClassLabel(_ label: String?) -> String? {
        guard let label = sanitizedLabel(label) else { return nil }
        let components = label.split(separator: ".").map(String.init)
        guard components.count > 3 else { return label }
        return components.suffix(3).joined(separator: ".")
    }

    private func sanitizedLabel(_ label: String?) -> String? {
        guard let label else { return nil }
        let collapsedWhitespace = label
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !collapsedWhitespace.isEmpty else { return nil }
        return String(collapsedWhitespace.prefix(characterLimit))
    }

    private func qualifiedElementName(elementName: String, qName: String?) -> String {
        guard let qName, !qName.isEmpty else { return elementName }
        return qName
    }

    private let previewLabelLimit = 6
    private let characterLimit = 80
}
