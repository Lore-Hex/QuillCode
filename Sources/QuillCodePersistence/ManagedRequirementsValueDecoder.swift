extension ManagedRequirementsDecoder {
    func requireNonEmpty<T>(_ value: [T]?, path: String) throws {
        if value?.isEmpty == true { throw error(path, "must not be empty") }
    }

    func optionalArray(_ key: String) throws -> [ConfigValue]? {
        guard let value = values[key] else { return nil }
        guard let array = value.arrayValue else { throw error(key, "must be an array") }
        return array
    }

    func optionalObject(_ key: String) throws -> [String: ConfigValue]? {
        guard let value = values[key] else { return nil }
        guard let object = value.objectValue else { throw error(key, "must be a table") }
        return object
    }

    func optionalString(_ key: String) throws -> String? {
        try optionalString(key, in: values, pathPrefix: "")
    }

    func optionalString(
        _ key: String,
        in object: [String: ConfigValue],
        pathPrefix: String
    ) throws -> String? {
        guard let value = object[key] else { return nil }
        guard let string = value.stringValue else {
            throw error(path(pathPrefix, key), "must be a string")
        }
        return string
    }

    func optionalAliasedString(
        canonical: String,
        legacy: String,
        in object: [String: ConfigValue],
        pathPrefix: String
    ) throws -> String? {
        if object[canonical] != nil, object[legacy] != nil {
            throw error(path(pathPrefix, canonical), "cannot be combined with `\(legacy)`")
        }
        return try optionalString(
            object[canonical] == nil ? legacy : canonical,
            in: object,
            pathPrefix: pathPrefix
        )
    }

    func optionalBool(_ key: String) throws -> Bool? {
        try optionalBool(key, in: values, pathPrefix: "")
    }

    func optionalBool(
        _ key: String,
        in object: [String: ConfigValue],
        pathPrefix: String
    ) throws -> Bool? {
        guard let value = object[key] else { return nil }
        guard let bool = value.boolValue else {
            throw error(path(pathPrefix, key), "must be a boolean")
        }
        return bool
    }

    func optionalEnum(_ key: String, allowed: Set<String>) throws -> String? {
        guard let value = try optionalString(key) else { return nil }
        guard allowed.contains(value) else {
            throw error(key, "contains unsupported value `\(value)`")
        }
        return value
    }

    func boolMap(_ key: String) throws -> [String: Bool]? {
        guard let object = try optionalObject(key) else { return nil }
        return try object.reduce(into: [String: Bool]()) { result, entry in
            guard let bool = entry.value.boolValue else {
                throw error("\(key).\(entry.key)", "must be a boolean")
            }
            result[entry.key] = bool
        }
    }

    func stringArray(
        _ key: String,
        allowed: Set<String>
    ) throws -> [String]? {
        try stringArray(key, in: values, pathPrefix: "", allowed: allowed)
    }

    func stringArray(
        _ key: String,
        in object: [String: ConfigValue],
        pathPrefix: String,
        allowed: Set<String>
    ) throws -> [String]? {
        guard let values = try optionalStringArray(key, in: object, pathPrefix: pathPrefix) else {
            return nil
        }
        for value in values where !allowed.contains(value) {
            throw error(path(pathPrefix, key), "contains unsupported value `\(value)`")
        }
        return values
    }

    func optionalStringArray(
        _ key: String,
        in object: [String: ConfigValue],
        pathPrefix: String
    ) throws -> [String]? {
        guard let value = object[key] else { return nil }
        guard let array = value.arrayValue else {
            throw error(path(pathPrefix, key), "must be an array of strings")
        }
        return try array.enumerated().map { offset, value in
            guard let string = value.stringValue else {
                throw error("\(path(pathPrefix, key))[\(offset)]", "must be a string")
            }
            return string
        }
    }

    func optionalPermissionMap(
        _ key: String,
        in object: [String: ConfigValue],
        pathPrefix: String
    ) throws -> [String: String]? {
        guard let value = object[key] else { return nil }
        guard let map = value.objectValue else {
            throw error(path(pathPrefix, key), "must be a table")
        }
        return try map.reduce(into: [String: String]()) { result, entry in
            guard let permission = entry.value.stringValue,
                  ["allow", "deny"].contains(permission) else {
                throw error(
                    "\(path(pathPrefix, key)).\(entry.key)",
                    "must be `allow` or `deny`"
                )
            }
            result[entry.key] = permission
        }
    }

    func optionalUInt16(
        _ key: String,
        in object: [String: ConfigValue],
        pathPrefix: String
    ) throws -> UInt16? {
        guard let value = object[key] else { return nil }
        guard let integer = value.integerValue,
              let result = UInt16(exactly: integer) else {
            throw error(path(pathPrefix, key), "must be an unsigned 16-bit integer")
        }
        return result
    }

    func optionalUInt64(
        canonical: String,
        legacy: String,
        in object: [String: ConfigValue],
        pathPrefix: String
    ) throws -> UInt64? {
        if object[canonical] != nil, object[legacy] != nil {
            throw error(path(pathPrefix, canonical), "cannot be combined with `\(legacy)`")
        }
        let key = object[canonical] == nil ? legacy : canonical
        guard let value = object[key] else { return nil }
        guard let integer = value.integerValue,
              let result = UInt64(exactly: integer) else {
            throw error(path(pathPrefix, key), "must be an unsigned integer")
        }
        return result
    }

    func path(_ prefix: String, _ key: String) -> String {
        prefix.isEmpty ? key : "\(prefix).\(key)"
    }

    func error(_ path: String, _ reason: String) -> ManagedRequirementsLoadError {
        ManagedRequirementsLoadError(path: path, reason: reason)
    }
}
