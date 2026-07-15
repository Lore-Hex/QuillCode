import Foundation

extension ConfigValue {
    static func stringArray(_ values: [String]) -> ConfigValue {
        .array(values.map(ConfigValue.string))
    }
}

extension Dictionary where Key == String, Value == ConfigValue {
    func string(_ key: String) -> String? {
        self[key]?.stringValue
    }

    func bool(_ key: String) -> Bool? {
        self[key]?.boolValue
    }

    func double(_ key: String) -> Double? {
        self[key]?.numberValue
    }

    func int(_ key: String) -> Int? {
        guard let value = self[key]?.integerValue,
              value >= Int64(Int.min),
              value <= Int64(Int.max)
        else { return nil }
        return Int(value)
    }

    func stringArray(_ key: String) -> [String] {
        guard let value = self[key] else { return [] }
        if let string = value.stringValue { return [string] }
        return value.arrayValue?.compactMap(\.stringValue) ?? []
    }
}
