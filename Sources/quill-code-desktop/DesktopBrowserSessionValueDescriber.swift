import Foundation

enum DesktopBrowserSessionValueDescriber {
    private static let maxDescriptionLength = 4_000

    static func boundedDescription(_ value: Any?) -> String {
        let description = describe(value)
        guard description.count > maxDescriptionLength else { return description }
        return String(description.prefix(maxDescriptionLength)) + "... [truncated]"
    }

    private static func describe(_ value: Any?) -> String {
        switch value {
        case nil, is NSNull:
            return "null"
        case let string as String:
            return string
        case let number as NSNumber:
            return number.stringValue
        case let array as [Any]:
            return array.map(describe).joined(separator: ", ")
        case let dictionary as [String: Any]:
            return dictionary
                .sorted { $0.key < $1.key }
                .map { "\($0.key): \(describe($0.value))" }
                .joined(separator: ", ")
        case let value?:
            return String(describing: value)
        }
    }
}
