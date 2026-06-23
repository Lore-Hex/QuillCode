import AppKit
import Foundation

struct MacSystemSettingsOpener {
    enum Destination {
        case screenRecording
        case accessibility

        fileprivate var urlString: String {
            switch self {
            case .screenRecording:
                "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
            case .accessibility:
                "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
            }
        }
    }

    @discardableResult
    func open(_ destination: Destination) -> Bool {
        guard let url = URL(string: destination.urlString) else { return false }
        NSWorkspace.shared.open(url)
        return true
    }
}
