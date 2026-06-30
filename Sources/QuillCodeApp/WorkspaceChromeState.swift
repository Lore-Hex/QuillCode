import Foundation

public struct WorkspaceChromeState: Sendable, Hashable, Codable {
    public var isSidebarVisible: Bool

    public init(isSidebarVisible: Bool = true) {
        self.isSidebarVisible = isSidebarVisible
    }
}

public struct WorkspaceChromeSurface: Codable, Sendable, Hashable {
    public var isSidebarVisible: Bool

    public init(isSidebarVisible: Bool = true) {
        self.isSidebarVisible = isSidebarVisible
    }

    public init(state: WorkspaceChromeState) {
        self.init(isSidebarVisible: state.isSidebarVisible)
    }
}
