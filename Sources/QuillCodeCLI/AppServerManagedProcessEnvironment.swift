import QuillCodePersistence

enum AppServerProxyEnvironmentPolicy: Sendable, Equatable {
    case inherit
    case stripUpstreamProxy
}

extension AppServerProxyEnvironmentPolicy {
    init(requirements: ManagedRequirements?) {
        if requirements?.network?.allowUpstreamProxy == false {
            self = .stripUpstreamProxy
        } else {
            self = .inherit
        }
    }

    func apply(to environment: [String: String]) -> [String: String] {
        switch self {
        case .inherit:
            environment
        case .stripUpstreamProxy:
            environment.filter { key, _ in
                !Self.proxyEnvironmentKeys.contains(key.lowercased())
            }
        }
    }

    private static let proxyEnvironmentKeys: Set<String> = [
        "http_proxy",
        "https_proxy",
        "all_proxy",
        "no_proxy"
    ]
}
