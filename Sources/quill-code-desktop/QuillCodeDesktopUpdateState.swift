import Foundation

extension QuillCodeDesktopUpdateController {
    enum State: Equatable {
        case idle
        case checking
        case updateAvailable(QuillCodeDesktopUpdateRelease)
        case downloading(QuillCodeDesktopUpdateRelease)
        case installing(QuillCodeDesktopUpdateRelease)
        case upToDate(latestVersion: String, latestBuild: String)
        case failed(message: String, release: QuillCodeDesktopUpdateRelease?)

        var release: QuillCodeDesktopUpdateRelease? {
            switch self {
            case .updateAvailable(let release), .downloading(let release), .installing(let release):
                return release
            case .failed(_, let release):
                return release
            case .idle, .checking, .upToDate:
                return nil
            }
        }

        var isBusy: Bool {
            switch self {
            case .checking, .downloading, .installing:
                return true
            case .idle, .updateAvailable, .upToDate, .failed:
                return false
            }
        }
    }
}
