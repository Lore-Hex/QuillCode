import Foundation
import QuillCodeReview

public enum CLIReviewTarget: Sendable, Equatable {
    case uncommitted
    case baseBranch(String)
    case commit(String)
    case custom(String)

    var scope: WorkspaceCodeReviewScope {
        switch self {
        case .uncommitted: .uncommitted
        case .baseBranch: .baseBranch
        case .commit: .commit
        case .custom: .custom
        }
    }

    var reference: String? {
        switch self {
        case .baseBranch(let reference), .commit(let reference): reference
        case .uncommitted, .custom: nil
        }
    }

    var instructions: String? {
        guard case .custom(let instructions) = self else { return nil }
        return instructions
    }
}

public struct CLIReviewRequest: Sendable, Equatable {
    public var target: CLIReviewTarget?
    public var title: String?
    public var live: Bool
    public var apiKey: String?
    public var model: String?
    public var baseURL: String?
    public var cwd: URL
    public var home: URL?
    public var ignoresUserConfig: Bool
    public var showsHelp: Bool

    public init(
        target: CLIReviewTarget? = nil,
        title: String? = nil,
        live: Bool = true,
        apiKey: String? = nil,
        model: String? = nil,
        baseURL: String? = nil,
        cwd: URL,
        home: URL? = nil,
        ignoresUserConfig: Bool = false,
        showsHelp: Bool = false
    ) {
        self.target = target
        self.title = title
        self.live = live
        self.apiKey = apiKey
        self.model = model
        self.baseURL = baseURL
        self.cwd = cwd
        self.home = home
        self.ignoresUserConfig = ignoresUserConfig
        self.showsHelp = showsHelp
    }

    func workspaceRequest(customInstructions: String? = nil) throws -> WorkspaceCodeReviewRequest {
        guard let target else { throw CLIError.missingReviewTarget }
        let request = WorkspaceCodeReviewRequest(
            scope: target.scope,
            reference: target.reference,
            instructions: customInstructions ?? target.instructions,
            title: title,
            delivery: .current,
            model: model
        )
        if let message = request.validationMessage {
            throw CLIError.invalidReviewRequest(message)
        }
        return request
    }
}
