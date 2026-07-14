import Foundation

public enum WorkspaceTextScale: Int, Codable, Sendable, Hashable, CaseIterable {
    case small
    case standard
    case large
    case extraLarge

    public var canIncrease: Bool { self != .extraLarge }
    public var canDecrease: Bool { self != .small }

    public func increased() -> Self {
        Self(rawValue: min(rawValue + 1, Self.extraLarge.rawValue)) ?? .extraLarge
    }

    public func decreased() -> Self {
        Self(rawValue: max(rawValue - 1, Self.small.rawValue)) ?? .small
    }
}

public struct WorkspaceChromeState: Sendable, Hashable, Codable {
    public var isSidebarVisible: Bool
    public var isReviewVisible: Bool
    public var textScale: WorkspaceTextScale

    public init(
        isSidebarVisible: Bool = true,
        isReviewVisible: Bool = true,
        textScale: WorkspaceTextScale = .standard
    ) {
        self.isSidebarVisible = isSidebarVisible
        self.isReviewVisible = isReviewVisible
        self.textScale = textScale
    }

    private enum CodingKeys: String, CodingKey {
        case isSidebarVisible
        case isReviewVisible
        case textScale
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            isSidebarVisible: try container.decodeIfPresent(
                Bool.self,
                forKey: .isSidebarVisible
            ) ?? true,
            isReviewVisible: try container.decodeIfPresent(
                Bool.self,
                forKey: .isReviewVisible
            ) ?? true,
            textScale: try container.decodeIfPresent(
                WorkspaceTextScale.self,
                forKey: .textScale
            ) ?? .standard
        )
    }
}

public struct WorkspaceChromeSurface: Codable, Sendable, Hashable {
    public var isSidebarVisible: Bool
    public var isReviewVisible: Bool
    public var textScale: WorkspaceTextScale

    public init(
        isSidebarVisible: Bool = true,
        isReviewVisible: Bool = true,
        textScale: WorkspaceTextScale = .standard
    ) {
        self.isSidebarVisible = isSidebarVisible
        self.isReviewVisible = isReviewVisible
        self.textScale = textScale
    }

    public init(state: WorkspaceChromeState) {
        self.init(
            isSidebarVisible: state.isSidebarVisible,
            isReviewVisible: state.isReviewVisible,
            textScale: state.textScale
        )
    }

    private enum CodingKeys: String, CodingKey {
        case isSidebarVisible
        case isReviewVisible
        case textScale
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            isSidebarVisible: try container.decodeIfPresent(
                Bool.self,
                forKey: .isSidebarVisible
            ) ?? true,
            isReviewVisible: try container.decodeIfPresent(
                Bool.self,
                forKey: .isReviewVisible
            ) ?? true,
            textScale: try container.decodeIfPresent(
                WorkspaceTextScale.self,
                forKey: .textScale
            ) ?? .standard
        )
    }
}
