import Foundation

public enum WorkspaceReviewPresentation: String, Codable, Sendable, Hashable {
    case automatic
    case visible
    case hidden

    public func resolves(hasContent: Bool) -> Bool {
        switch self {
        case .automatic:
            hasContent
        case .visible:
            true
        case .hidden:
            false
        }
    }
}

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
    public var reviewPresentation: WorkspaceReviewPresentation
    public var textScale: WorkspaceTextScale

    public var isReviewVisible: Bool {
        get { reviewPresentation != .hidden }
        set { reviewPresentation = newValue ? .visible : .hidden }
    }

    public init(
        isSidebarVisible: Bool = true,
        isReviewVisible: Bool? = nil,
        reviewPresentation: WorkspaceReviewPresentation = .automatic,
        textScale: WorkspaceTextScale = .standard
    ) {
        self.isSidebarVisible = isSidebarVisible
        self.reviewPresentation = isReviewVisible.map {
            $0 ? WorkspaceReviewPresentation.visible : .hidden
        } ?? reviewPresentation
        self.textScale = textScale
    }

    private enum CodingKeys: String, CodingKey {
        case isSidebarVisible
        case isReviewVisible
        case reviewPresentation
        case textScale
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let presentation = try container.decodeIfPresent(
            WorkspaceReviewPresentation.self,
            forKey: .reviewPresentation
        ) ?? container.decodeIfPresent(Bool.self, forKey: .isReviewVisible).map {
            $0 ? WorkspaceReviewPresentation.automatic : .hidden
        } ?? .automatic
        self.init(
            isSidebarVisible: try container.decodeIfPresent(Bool.self, forKey: .isSidebarVisible) ?? true,
            reviewPresentation: presentation,
            textScale: try container.decodeIfPresent(WorkspaceTextScale.self, forKey: .textScale) ?? .standard
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(isSidebarVisible, forKey: .isSidebarVisible)
        try container.encode(reviewPresentation, forKey: .reviewPresentation)
        try container.encode(textScale, forKey: .textScale)
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

    public init(state: WorkspaceChromeState, reviewHasContent: Bool? = nil) {
        self.init(
            isSidebarVisible: state.isSidebarVisible,
            isReviewVisible: reviewHasContent.map(state.reviewPresentation.resolves(hasContent:))
                ?? state.isReviewVisible,
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
