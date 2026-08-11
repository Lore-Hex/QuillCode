import AppKit
import Foundation

@MainActor
enum QuillCodeDesktopAccessibilityHierarchySettler {
    private static let sampleIntervalNanoseconds: UInt64 = 50_000_000
    private static let requiredStableComparisons = 6
    private static let maximumSamples = 30
    private static let layoutSentinelIdentifiers: Set<String> = [
        "quillcode-sidebar-command-new-chat",
        "quillcode-sidebar-tools-button",
        "quillcode-top-bar-overflow"
    ]

    static func waitUntilStable(in contentView: NSView) async {
        var previousSignature: [String]?
        var stableComparisonCount = 0

        for _ in 0..<maximumSamples {
            try? await Task.sleep(nanoseconds: sampleIntervalNanoseconds)
            guard !Task.isCancelled else { return }
            let currentSignature = signature(
                for: QuillCodeDesktopAccessibilityTree(
                    root: contentView,
                    matchingIdentifiers: layoutSentinelIdentifiers
                ).elements
            )
            if currentSignature == previousSignature {
                stableComparisonCount += 1
                if stableComparisonCount >= requiredStableComparisons {
                    return
                }
            } else {
                previousSignature = currentSignature
                stableComparisonCount = 0
            }
        }
    }

    static func signature(
        for elements: [QuillCodeDesktopAccessibilityElementSnapshot]
    ) -> [String] {
        elements.map { element in
            let frame = element.frame.map {
                [
                    Int($0.minX.rounded()),
                    Int($0.minY.rounded()),
                    Int($0.width.rounded()),
                    Int($0.height.rounded())
                ].map(String.init).joined(separator: ",")
            } ?? "none"
            return [element.identifier, element.role, element.bestLabel, frame]
                .joined(separator: "|")
        }.sorted()
    }
}
