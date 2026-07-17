import Foundation

struct AppServerRemoteWorkspacePath: Sendable, Equatable {
    struct Resolved: Sendable, Equatable {
        var nativePath: String
        var uri: String
        var relativePath: String
    }

    private enum Flavor: Sendable, Equatable {
        case unix
        case windows(drive: String)
    }

    let root: Resolved
    private let flavor: Flavor
    private let rootComponents: [String]

    init(cwd: String, fallbackCWDURI: String?) throws {
        let selected = cwd.trimmingCharacters(in: .whitespacesAndNewlines)
        let native = try Self.nativePath(
            from: selected.isEmpty ? fallbackCWDURI : selected
        )
        let parsed = try Self.parseAbsolute(native)
        self.flavor = parsed.flavor
        self.rootComponents = parsed.components
        self.root = Self.resolved(
            components: parsed.components,
            relativeComponents: [],
            flavor: parsed.flavor
        )
    }

    func resolve(_ rawPath: String, defaultingToRoot: Bool = false) throws -> Resolved {
        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = trimmed.isEmpty && defaultingToRoot ? "." : trimmed
        guard !value.isEmpty,
              !value.contains("\0"),
              value.rangeOfCharacter(from: .newlines) == nil else {
            throw AppServerRemotePathError.invalidPath(rawPath)
        }

        let normalized = Self.normalizedSeparators(value, flavor: flavor)
        if case .windows(let rootDrive) = flavor,
           normalized.range(of: #"^[A-Za-z]:/"#, options: .regularExpression) != nil,
           !normalized.uppercased().hasPrefix(rootDrive + "/") {
            throw AppServerRemotePathError.outsideWorkspace(rawPath)
        }
        let absolute = Self.isAbsolute(normalized, flavor: flavor)
        var components = absolute ? [] : rootComponents
        for component in Self.components(normalized, flavor: flavor) {
            switch component {
            case "", ".": continue
            case "..":
                guard components.count > rootComponents.count else {
                    throw AppServerRemotePathError.outsideWorkspace(rawPath)
                }
                components.removeLast()
            default:
                components.append(component)
            }
        }
        guard Self.hasPrefix(components, rootComponents, flavor: flavor) else {
            throw AppServerRemotePathError.outsideWorkspace(rawPath)
        }
        return Self.resolved(
            components: components,
            relativeComponents: Array(components.dropFirst(rootComponents.count)),
            flavor: flavor
        )
    }

    func sandboxPathURI(for rawPath: String) throws -> String {
        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.contains("\0"),
              trimmed.rangeOfCharacter(from: .newlines) == nil else {
            throw AppServerRemotePathError.invalidPath(rawPath)
        }

        let normalized = Self.normalizedSeparators(trimmed, flavor: flavor)
        guard Self.isSyntacticallyAbsolute(normalized, flavor: flavor) else {
            return try resolve(normalized).uri
        }
        let parsed = try Self.parseAbsolute(normalized)
        guard parsed.flavor == flavor else {
            throw AppServerRemotePathError.outsideWorkspace(rawPath)
        }
        return Self.resolved(
            components: parsed.components,
            relativeComponents: [],
            flavor: parsed.flavor
        ).uri
    }

    func parent(of path: Resolved) throws -> Resolved {
        guard path.relativePath != "." else { return root }
        let native = path.nativePath
        let separator: Character = flavor == .unix ? "/" : "\\"
        guard let index = native.lastIndex(of: separator) else { return root }
        let parent = String(native[..<index])
        return try resolve(parent.isEmpty ? root.nativePath : parent)
    }

    func contains(canonicalURI: String) -> Bool {
        canonical(canonicalURI) != nil
    }

    func canonical(_ uri: String) -> Resolved? {
        guard let native = try? Self.nativePath(from: uri),
              let parsed = try? Self.parseAbsolute(native),
              parsed.flavor == flavor,
              Self.hasPrefix(parsed.components, rootComponents, flavor: flavor) else {
            return nil
        }
        return Self.resolved(
            components: parsed.components,
            relativeComponents: Array(parsed.components.dropFirst(rootComponents.count)),
            flavor: flavor
        )
    }

    private static func nativePath(from value: String?) throws -> String {
        guard let value,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AppServerRemotePathError.missingWorkspace
        }
        if value.lowercased().hasPrefix("file:") {
            guard let components = URLComponents(string: value),
                  components.scheme?.lowercased() == "file",
                  components.host?.isEmpty != false,
                  components.user == nil,
                  components.password == nil,
                  components.port == nil,
                  components.query == nil,
                  components.fragment == nil,
                  let path = components.percentEncodedPath.removingPercentEncoding else {
                throw AppServerRemotePathError.invalidPath(value)
            }
            if path.range(of: #"^/[A-Za-z]:/"#, options: .regularExpression) != nil {
                return String(path.dropFirst()).replacingOccurrences(of: "/", with: "\\")
            }
            return path
        }
        return value
    }

    private static func parseAbsolute(
        _ path: String
    ) throws -> (flavor: Flavor, components: [String]) {
        let windowsPattern = #"^[A-Za-z]:[\\/]"#
        if path.range(of: windowsPattern, options: .regularExpression) != nil {
            let drive = String(path.prefix(2)).uppercased()
            let tail = String(path.dropFirst(2)).replacingOccurrences(of: "\\", with: "/")
            return (
                .windows(drive: drive),
                try normalizedAbsoluteComponents(
                    tail.split(separator: "/", omittingEmptySubsequences: false).map(String.init),
                    originalPath: path
                )
            )
        }
        guard path.hasPrefix("/") else {
            throw AppServerRemotePathError.workspaceMustBeAbsolute(path)
        }
        return (
            .unix,
            try normalizedAbsoluteComponents(
                path.split(separator: "/", omittingEmptySubsequences: false).map(String.init),
                originalPath: path
            )
        )
    }

    private static func normalizedAbsoluteComponents(
        _ components: [String],
        originalPath: String
    ) throws -> [String] {
        var normalized: [String] = []
        for component in components {
            guard !component.contains("\0"),
                  component.rangeOfCharacter(from: .newlines) == nil else {
                throw AppServerRemotePathError.invalidPath(originalPath)
            }
            switch component {
            case "", ".":
                continue
            case "..":
                guard !normalized.isEmpty else {
                    throw AppServerRemotePathError.outsideWorkspace(originalPath)
                }
                normalized.removeLast()
            default:
                normalized.append(component)
            }
        }
        return normalized
    }

    private static func normalizedSeparators(_ path: String, flavor: Flavor) -> String {
        switch flavor {
        case .unix: path
        case .windows: path.replacingOccurrences(of: "\\", with: "/")
        }
    }

    private static func isAbsolute(_ path: String, flavor: Flavor) -> Bool {
        switch flavor {
        case .unix: path.hasPrefix("/")
        case .windows(let drive): path.uppercased().hasPrefix(drive + "/")
        }
    }

    private static func isSyntacticallyAbsolute(_ path: String, flavor: Flavor) -> Bool {
        switch flavor {
        case .unix:
            path.hasPrefix("/")
        case .windows:
            path.range(of: #"^[A-Za-z]:/"#, options: .regularExpression) != nil
        }
    }

    private static func components(_ path: String, flavor: Flavor) -> [String] {
        switch flavor {
        case .unix:
            return path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        case .windows:
            var path = path
            if path.count >= 3, path[path.index(path.startIndex, offsetBy: 1)] == ":" {
                path = String(path.dropFirst(2))
            }
            return path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        }
    }

    private static func hasPrefix(
        _ candidate: [String],
        _ root: [String],
        flavor: Flavor
    ) -> Bool {
        guard candidate.count >= root.count else { return false }
        switch flavor {
        case .unix:
            return Array(candidate.prefix(root.count)) == root
        case .windows:
            return zip(candidate.prefix(root.count), root).allSatisfy {
                $0.0.caseInsensitiveCompare($0.1) == .orderedSame
            }
        }
    }

    private static func resolved(
        components: [String],
        relativeComponents: [String],
        flavor: Flavor
    ) -> Resolved {
        let nativePath: String
        let uriPath: String
        switch flavor {
        case .unix:
            nativePath = "/" + components.joined(separator: "/")
            uriPath = nativePath
        case .windows(let drive):
            let tail = components.joined(separator: "\\")
            nativePath = tail.isEmpty ? drive + "\\" : drive + "\\" + tail
            uriPath = "/" + drive + "/" + components.joined(separator: "/")
        }
        var uri = URLComponents()
        uri.scheme = "file"
        uri.host = ""
        uri.path = uriPath
        return Resolved(
            nativePath: nativePath,
            uri: uri.url?.absoluteString ?? "file://\(uriPath)",
            relativePath: relativeComponents.isEmpty
                ? "."
                : relativeComponents.joined(separator: "/")
        )
    }
}

enum AppServerRemotePathError: Error, CustomStringConvertible, Sendable, Equatable {
    case missingWorkspace
    case workspaceMustBeAbsolute(String)
    case invalidPath(String)
    case outsideWorkspace(String)

    var description: String {
        switch self {
        case .missingWorkspace:
            "The selected remote environment did not provide a working directory."
        case .workspaceMustBeAbsolute(let path):
            "Remote workspace path must be absolute: \(path)"
        case .invalidPath(let path):
            "Invalid remote workspace path: \(path)"
        case .outsideWorkspace(let path):
            "Path is outside the remote workspace: \(path)"
        }
    }
}
