extension ManagedRequirementsDecoder {
    func decodeNetwork() throws -> ManagedNetworkRequirements? {
        guard let object = try optionalObject("experimental_network") else { return nil }
        let canonicalDomains = try optionalPermissionMap(
            "domains",
            in: object,
            pathPrefix: "experimental_network"
        )
        let allowedDomains = try optionalStringArray(
            "allowed_domains",
            in: object,
            pathPrefix: "experimental_network"
        )
        let deniedDomains = try optionalStringArray(
            "denied_domains",
            in: object,
            pathPrefix: "experimental_network"
        )
        if canonicalDomains != nil, allowedDomains != nil || deniedDomains != nil {
            throw error(
                "experimental_network.domains",
                "cannot be combined with `allowed_domains` or `denied_domains`"
            )
        }
        let domains = canonicalDomains ?? legacyDomainPermissions(
            allowed: allowedDomains,
            denied: deniedDomains
        )

        let canonicalSockets = try optionalPermissionMap(
            "unix_sockets",
            in: object,
            pathPrefix: "experimental_network"
        )
        let legacySockets = try optionalStringArray(
            "allow_unix_sockets",
            in: object,
            pathPrefix: "experimental_network"
        )
        if canonicalSockets != nil, legacySockets != nil {
            throw error(
                "experimental_network.unix_sockets",
                "cannot be combined with `allow_unix_sockets`"
            )
        }
        let unixSockets = canonicalSockets ?? legacySockets.map {
            Dictionary(uniqueKeysWithValues: $0.map { ($0, "allow") })
        }

        return ManagedNetworkRequirements(
            enabled: try optionalBool("enabled", in: object, pathPrefix: "experimental_network"),
            httpPort: try optionalUInt16(
                "http_port",
                in: object,
                pathPrefix: "experimental_network"
            ),
            socksPort: try optionalUInt16(
                "socks_port",
                in: object,
                pathPrefix: "experimental_network"
            ),
            allowUpstreamProxy: try optionalBool(
                "allow_upstream_proxy",
                in: object,
                pathPrefix: "experimental_network"
            ),
            dangerouslyAllowNonLoopbackProxy: try optionalBool(
                "dangerously_allow_non_loopback_proxy",
                in: object,
                pathPrefix: "experimental_network"
            ),
            dangerouslyAllowAllUnixSockets: try optionalBool(
                "dangerously_allow_all_unix_sockets",
                in: object,
                pathPrefix: "experimental_network"
            ),
            domains: domains,
            managedAllowedDomainsOnly: try optionalBool(
                "managed_allowed_domains_only",
                in: object,
                pathPrefix: "experimental_network"
            ),
            unixSockets: unixSockets,
            allowLocalBinding: try optionalBool(
                "allow_local_binding",
                in: object,
                pathPrefix: "experimental_network"
            )
        )
    }

    private func legacyDomainPermissions(
        allowed: [String]?,
        denied: [String]?
    ) -> [String: String]? {
        var values: [String: String] = [:]
        allowed?.forEach { values[$0] = "allow" }
        denied?.forEach { values[$0] = "deny" }
        return values.isEmpty ? nil : values
    }
}
