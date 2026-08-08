import AppKit
import Foundation

enum QuillCodeDesktopIssueReporter {
    private static let issuesURL = URL(string: "https://github.com/Lore-Hex/QuillCode/issues/new")!

    static func issueURL(metadata: QuillCodeDesktopBuildMetadata) -> URL? {
        guard var components = URLComponents(url: issuesURL, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.queryItems = [
            URLQueryItem(name: "labels", value: "bug"),
            URLQueryItem(name: "title", value: "[Bug] "),
            URLQueryItem(name: "body", value: issueBody(metadata: metadata))
        ]
        return components.url
    }

    @MainActor
    static func open(
        configuration: QuillCodeDesktopUpdateConfiguration?,
        bundle: Bundle = .main
    ) {
        let metadata = QuillCodeDesktopBuildMetadata.current(
            configuration: configuration,
            bundle: bundle
        )
        guard let url = issueURL(metadata: metadata) else { return }
        NSWorkspace.shared.open(url)
    }

    private static func issueBody(metadata: QuillCodeDesktopBuildMetadata) -> String {
        """
        <!-- Describe what happened. Do not include API keys, credentials, or private project data. -->

        ## What happened


        ## Steps to reproduce

        1.

        ## Expected behavior


        ## Build information

        - Version: \(metadata.version) (\(metadata.build))
        - Commit: \(metadata.commit)
        - Channel: \(metadata.channel)
        - System: \(metadata.operatingSystem)
        - Architecture: \(metadata.architecture)
        """
    }
}
