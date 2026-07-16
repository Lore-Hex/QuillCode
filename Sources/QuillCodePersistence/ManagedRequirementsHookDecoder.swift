extension ManagedRequirementsDecoder {
    func decodeHooks() throws -> ManagedHookRequirements? {
        guard let object = try optionalObject("hooks") else { return nil }
        var events: [String: [ManagedHookMatcherGroup]] = [:]
        for event in ManagedHookRequirements.eventNames {
            guard let value = object[event] else {
                events[event] = []
                continue
            }
            guard let groups = value.arrayValue else {
                throw error("hooks.\(event)", "must be an array")
            }
            events[event] = try groups.enumerated().map { offset, value in
                try decodeHookGroup(value, path: "hooks.\(event)[\(offset)]")
            }
        }
        return ManagedHookRequirements(
            managedDirectory: try optionalString("managed_dir", in: object, pathPrefix: "hooks"),
            windowsManagedDirectory: try optionalString(
                "windows_managed_dir",
                in: object,
                pathPrefix: "hooks"
            ),
            events: events
        )
    }

    private func decodeHookGroup(
        _ value: ConfigValue,
        path: String
    ) throws -> ManagedHookMatcherGroup {
        guard let object = value.objectValue,
              let handlers = object["hooks"]?.arrayValue else {
            throw error(path, "must contain a hooks array")
        }
        return ManagedHookMatcherGroup(
            matcher: try optionalString("matcher", in: object, pathPrefix: path),
            hooks: try handlers.enumerated().map { offset, value in
                try decodeHookHandler(value, path: "\(path).hooks[\(offset)]")
            }
        )
    }

    private func decodeHookHandler(_ value: ConfigValue, path: String) throws -> ManagedHookHandler {
        guard let object = value.objectValue,
              let type = object["type"]?.stringValue else {
            throw error(path, "must contain a string type")
        }
        switch type {
        case "prompt": return .prompt
        case "agent": return .agent
        case "command":
            guard let command = object["command"]?.stringValue, !command.isEmpty else {
                throw error("\(path).command", "must be a non-empty string")
            }
            return .command(ManagedCommandHook(
                command: command,
                commandWindows: try optionalAliasedString(
                    canonical: "command_windows",
                    legacy: "commandWindows",
                    in: object,
                    pathPrefix: path
                ),
                timeoutSeconds: try optionalUInt64(
                    canonical: "timeout",
                    legacy: "timeout_sec",
                    in: object,
                    pathPrefix: path
                ),
                isAsync: try optionalBool("async", in: object, pathPrefix: path) ?? false,
                statusMessage: try optionalAliasedString(
                    canonical: "status_message",
                    legacy: "statusMessage",
                    in: object,
                    pathPrefix: path
                )
            ))
        default:
            throw error("\(path).type", "contains unsupported hook type `\(type)`")
        }
    }
}
