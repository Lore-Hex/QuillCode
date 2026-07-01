import Foundation

enum WorkspacePOSIXPathNormalizer {
    static func absolutePath(_ rawPath: String) -> String? {
        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("/"), isSafe(trimmed) else { return nil }

        guard let components = normalizedComponents(
            from: trimmed,
            allowLeadingParent: false
        ) else {
            return nil
        }
        return components.isEmpty ? "/" : "/\(components.joined(separator: "/"))"
    }

    static func parentPath(of normalizedAbsolutePath: String) -> String {
        let components = normalizedAbsolutePath
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
        guard components.count > 1 else { return "/" }
        return "/\(components.dropLast().joined(separator: "/"))"
    }

    static func isPath(_ path: String, inside parent: String) -> Bool {
        parent == "/" ? path.hasPrefix("/") : path == parent || path.hasPrefix("\(parent)/")
    }

    static func appending(_ relativePath: String, to base: String) -> String {
        let trimmedBase = base.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedRelative = relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedRelative.isEmpty else { return trimmedBase.isEmpty ? "~" : trimmedBase }

        let baseKind = BaseKind(trimmedBase)
        let baseRemainder = baseKind.remainder(from: trimmedBase)
        let joined = [baseRemainder, trimmedRelative]
            .filter { !$0.isEmpty }
            .joined(separator: "/")
        let components = normalizedComponents(
            from: joined,
            allowLeadingParent: baseKind.allowsLeadingParent
        ) ?? []
        return baseKind.render(components: components)
    }

    private static func isSafe(_ path: String) -> Bool {
        !path.contains("\0") && path.rangeOfCharacter(from: .newlines) == nil
    }

    private static func normalizedComponents(
        from path: String,
        allowLeadingParent: Bool
    ) -> [String]? {
        var components: [String] = []
        for component in path.split(separator: "/", omittingEmptySubsequences: true).map(String.init) {
            switch component {
            case ".":
                continue
            case "..":
                guard !components.isEmpty else {
                    if allowLeadingParent {
                        components.append(component)
                        continue
                    }
                    return nil
                }
                components.removeLast()
            default:
                components.append(component)
            }
        }
        return components
    }

    private enum BaseKind {
        case absolute
        case home
        case relative

        init(_ base: String) {
            if base.hasPrefix("/") {
                self = .absolute
            } else if base == "~" || base.hasPrefix("~/") || base.isEmpty {
                self = .home
            } else {
                self = .relative
            }
        }

        var allowsLeadingParent: Bool {
            self == .relative
        }

        func remainder(from base: String) -> String {
            switch self {
            case .absolute, .relative:
                return base.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            case .home:
                return String(base.dropFirst()).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            }
        }

        func render(components: [String]) -> String {
            let suffix = components.joined(separator: "/")
            switch self {
            case .absolute:
                return "/" + suffix
            case .home:
                return suffix.isEmpty ? "~" : "~/" + suffix
            case .relative:
                return suffix.isEmpty ? "." : suffix
            }
        }
    }
}
