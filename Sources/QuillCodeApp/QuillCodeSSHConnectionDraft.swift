import Foundation
import QuillCodeCore
import QuillCodeTools

enum QuillCodeSSHConnectionMode: String, CaseIterable, Identifiable {
    case configured = "SSH config"
    case manual = "Manual"

    var id: String { rawValue }
}

struct QuillCodeSSHHostLoadState: Equatable {
    var hosts: [SSHHostConfiguration] = []
    var configPath = "~/.ssh/config"
    var warnings: [String] = []
    var isLoading = false
    var hasLoaded = false

    static let loading = QuillCodeSSHHostLoadState(isLoading: true)

    static func loaded(_ result: SSHHostDiscoveryResult) -> QuillCodeSSHHostLoadState {
        QuillCodeSSHHostLoadState(
            hosts: result.hosts,
            configPath: result.configPath,
            warnings: result.warnings,
            hasLoaded: true
        )
    }
}

struct QuillCodeSSHConnectionDraft: Equatable {
    var mode = QuillCodeSSHConnectionMode.configured
    var hostLoad = QuillCodeSSHHostLoadState.loading
    var query = ""
    var selectedHostID: String?
    var manualAddress = ""
    var remotePath = "~"
    var projectName = ""
    var isConnecting = false
    var errorMessage: String?

    var filteredHosts: [SSHHostConfiguration] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return hostLoad.hosts }
        return hostLoad.hosts.filter {
            $0.alias.localizedCaseInsensitiveContains(needle)
                || $0.resolvedAddress.localizedCaseInsensitiveContains(needle)
        }
    }

    var selectedHost: SSHHostConfiguration? {
        guard let selectedHostID else { return nil }
        return hostLoad.hosts.first { $0.id == selectedHostID }
    }

    var request: WorkspaceSSHProjectRequest? {
        let path = remotePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isValidRemotePath(path) else { return nil }
        let connection: ProjectConnection?
        switch mode {
        case .configured:
            connection = selectedHost?.projectConnection(path: path)
        case .manual:
            let address = manualAddress.trimmingCharacters(in: .whitespacesAndNewlines)
            connection = ProjectConnection.parseSSHDestination(address, path: path)
        }
        guard let connection, connection.host?.isEmpty == false else { return nil }
        let name = projectName.trimmingCharacters(in: .whitespacesAndNewlines)
        return WorkspaceSSHProjectRequest(connection: connection, name: name.isEmpty ? nil : name)
    }

    var canConnect: Bool {
        request != nil && !isConnecting
    }

    mutating func apply(_ result: SSHHostDiscoveryResult) {
        hostLoad = .loaded(result)
        if let selectedHostID,
           hostLoad.hosts.contains(where: { $0.id == selectedHostID }) {
            return
        }
        selectedHostID = hostLoad.hosts.first?.id
        if hostLoad.hosts.isEmpty {
            mode = .manual
        }
    }

    private static func isValidRemotePath(_ path: String) -> Bool {
        !path.isEmpty && (path.hasPrefix("/") || path == "~" || path.hasPrefix("~/"))
    }
}
