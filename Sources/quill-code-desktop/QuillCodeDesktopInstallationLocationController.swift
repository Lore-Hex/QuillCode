import AppKit
import Combine
import Foundation

@MainActor
final class QuillCodeDesktopInstallationLocationController: ObservableObject {
    @Published var isPresented = false

    private let configuration: QuillCodeDesktopUpdateConfiguration?
    private let inspector: any QuillCodeDesktopUpdateInstallationInspecting
    private let defaults: UserDefaults
    private let applicationsURL: URL
    private let openApplications: @MainActor (URL) -> Void

    init(
        configuration: QuillCodeDesktopUpdateConfiguration? = .bundled(),
        inspector: any QuillCodeDesktopUpdateInstallationInspecting =
            QuillCodeDesktopUpdateInstallationInspector(),
        defaults: UserDefaults = .standard,
        applicationsURL: URL = URL(fileURLWithPath: "/Applications", isDirectory: true),
        openApplications: @escaping @MainActor (URL) -> Void = {
            _ = NSWorkspace.shared.open($0)
        }
    ) {
        self.configuration = configuration
        self.inspector = inspector
        self.defaults = defaults
        self.applicationsURL = applicationsURL.standardizedFileURL
        self.openApplications = openApplications
    }

    func startIfNeeded() {
        guard !isPresented,
              let configuration,
              inspector.availability(for: configuration) == .requiresRelocation,
              !Self.isInsideApplications(
                  configuration.applicationURL,
                  applicationsURL: applicationsURL
              ),
              !defaults.bool(forKey: dismissalKey(for: configuration))
        else {
            return
        }
        isPresented = true
    }

    func dismiss() {
        guard let configuration else {
            isPresented = false
            return
        }
        defaults.set(true, forKey: dismissalKey(for: configuration))
        isPresented = false
    }

    func openApplicationsFolder() {
        dismiss()
        openApplications(applicationsURL)
    }

    private func dismissalKey(for configuration: QuillCodeDesktopUpdateConfiguration) -> String {
        "QuillCodeInstallLocation.dismissed.\(configuration.bundleIdentifier).\(configuration.currentBuild)"
    }

    private static func isInsideApplications(
        _ applicationURL: URL,
        applicationsURL: URL
    ) -> Bool {
        let applicationPath = applicationURL.standardizedFileURL.path
        let applicationsPath = applicationsURL.standardizedFileURL.path
        return applicationPath.hasPrefix(applicationsPath + "/")
    }
}
