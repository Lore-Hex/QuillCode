import Foundation

/// A concrete `Host` alias discovered from the user's OpenSSH configuration.
///
/// QuillCode stores the alias, rather than the resolved hostname, in project metadata so later SSH
/// commands continue to honor `ProxyJump`, `IdentityFile`, `Match`, and other OpenSSH settings.
public struct SSHHostConfiguration: Identifiable, Sendable, Hashable {
    public var alias: String
    public var hostName: String?
    public var user: String?
    public var port: Int?

    public init(
        alias: String,
        hostName: String? = nil,
        user: String? = nil,
        port: Int? = nil
    ) {
        self.alias = alias
        self.hostName = hostName
        self.user = user
        self.port = port
    }

    public var id: String { alias.lowercased() }

    public var resolvedAddress: String {
        let destination = hostName ?? alias
        let userPrefix = user.map { "\($0)@" } ?? ""
        let portSuffix = port.flatMap { $0 == 22 ? nil : ":\($0)" } ?? ""
        return "\(userPrefix)\(destination)\(portSuffix)"
    }

    public func projectConnection(path: String) -> ProjectConnection {
        .ssh(path: path, host: alias)
    }
}
