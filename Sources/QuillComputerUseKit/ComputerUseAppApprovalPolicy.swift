import Foundation

public struct ComputerUseAppApprovalPolicy: Sendable, Hashable {
    public var approvedBundleIdentifiers: [String]
    public var approvedAppNames: [String]

    public init(
        approvedBundleIdentifiers: [String] = [],
        approvedAppNames: [String] = []
    ) {
        self.approvedBundleIdentifiers = Self.normalizedValues(approvedBundleIdentifiers)
        self.approvedAppNames = Self.normalizedValues(approvedAppNames)
    }

    public static let unrestricted = ComputerUseAppApprovalPolicy()

    public var isUnrestricted: Bool {
        approvedBundleIdentifiers.isEmpty && approvedAppNames.isEmpty
    }

    public func failureMessage(for application: ComputerUseApplication?) -> String? {
        guard !isUnrestricted else { return nil }
        guard let application else {
            return "Computer Use app approval could not identify the focused application."
        }
        if let bundleIdentifier = Self.normalized(application.bundleIdentifier),
           approvedBundleIdentifiers.contains(bundleIdentifier) {
            return nil
        }
        if let name = Self.normalized(application.name), approvedAppNames.contains(name) {
            return nil
        }
        return "Computer Use is not approved for \(application.displayLabel). "
            + "Add this app to Computer Use approvals before controlling it."
    }

    private static func normalizedValues(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var output: [String] = []
        for value in values {
            guard let normalized = Self.normalized(value), seen.insert(normalized).inserted else {
                continue
            }
            output.append(normalized)
        }
        return output
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return normalized.isEmpty ? nil : normalized
    }
}
