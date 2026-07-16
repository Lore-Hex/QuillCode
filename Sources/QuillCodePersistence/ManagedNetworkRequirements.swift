public struct ManagedNetworkRequirements: Sendable, Equatable {
    public var enabled: Bool?
    public var httpPort: UInt16?
    public var socksPort: UInt16?
    public var allowUpstreamProxy: Bool?
    public var dangerouslyAllowNonLoopbackProxy: Bool?
    public var dangerouslyAllowAllUnixSockets: Bool?
    public var domains: [String: String]?
    public var managedAllowedDomainsOnly: Bool?
    public var unixSockets: [String: String]?
    public var allowLocalBinding: Bool?

    public init(
        enabled: Bool? = nil,
        httpPort: UInt16? = nil,
        socksPort: UInt16? = nil,
        allowUpstreamProxy: Bool? = nil,
        dangerouslyAllowNonLoopbackProxy: Bool? = nil,
        dangerouslyAllowAllUnixSockets: Bool? = nil,
        domains: [String: String]? = nil,
        managedAllowedDomainsOnly: Bool? = nil,
        unixSockets: [String: String]? = nil,
        allowLocalBinding: Bool? = nil
    ) {
        self.enabled = enabled
        self.httpPort = httpPort
        self.socksPort = socksPort
        self.allowUpstreamProxy = allowUpstreamProxy
        self.dangerouslyAllowNonLoopbackProxy = dangerouslyAllowNonLoopbackProxy
        self.dangerouslyAllowAllUnixSockets = dangerouslyAllowAllUnixSockets
        self.domains = domains
        self.managedAllowedDomainsOnly = managedAllowedDomainsOnly
        self.unixSockets = unixSockets
        self.allowLocalBinding = allowLocalBinding
    }

    public var allowedDomains: [String]? {
        matchingDomainPermissions("allow")
    }

    public var deniedDomains: [String]? {
        matchingDomainPermissions("deny")
    }

    public var allowedUnixSockets: [String]? {
        guard let values = unixSockets?
            .filter({ $0.value == "allow" })
            .map(\.key)
            .sorted(),
              !values.isEmpty
        else { return nil }
        return values
    }

    private func matchingDomainPermissions(_ permission: String) -> [String]? {
        guard let values = domains?
            .filter({ $0.value == permission })
            .map(\.key)
            .sorted(),
              !values.isEmpty
        else { return nil }
        return values
    }
}
