import AppKit
import Foundation

enum QuillCodeDesktopIssueReporter {
    private static let issuesURL = URL(string: "https://github.com/Lore-Hex/QuillCode/issues/new")

    static func issueURL(
        metadata: QuillCodeDesktopBuildMetadata,
        incident: QuillCodeDesktopUnexpectedExit? = nil
    ) -> URL? {
        guard let issuesURL,
              var components = URLComponents(url: issuesURL, resolvingAgainstBaseURL: false)
        else {
            return nil
        }
        components.queryItems = [
            URLQueryItem(name: "labels", value: "bug"),
            URLQueryItem(name: "title", value: incident == nil ? "[Bug] " : "[Crash] "),
            URLQueryItem(name: "body", value: issueBody(metadata: metadata, incident: incident))
        ]
        return components.url
    }

    @MainActor
    static func open(
        configuration: QuillCodeDesktopUpdateConfiguration?,
        incident: QuillCodeDesktopUnexpectedExit? = nil,
        bundle: Bundle = .main
    ) {
        let metadata = QuillCodeDesktopBuildMetadata.current(
            configuration: configuration,
            bundle: bundle
        )
        guard let url = issueURL(metadata: metadata, incident: incident) else { return }
        NSWorkspace.shared.open(url)
    }

    private static func issueBody(
        metadata: QuillCodeDesktopBuildMetadata,
        incident: QuillCodeDesktopUnexpectedExit?
    ) -> String {
        var body = """
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
        if let incident {
            body += """


            ## Previous session

            - Outcome: Ended unexpectedly \(incident.phase.incidentDescription)
            - Started: \(ISO8601DateFormatter().string(from: incident.startedAt))
            - Version: \(incident.metadata.version) (\(incident.metadata.build))
            - Commit: \(incident.metadata.commit)
            - Channel: \(incident.metadata.channel)
            - System: \(incident.metadata.operatingSystem)
            - Architecture: \(incident.metadata.architecture)
            """
        }
        return body
    }
}
