import Foundation
import QuillCodePersistence

public struct WorkspaceThreadLoadIssue: Sendable, Hashable {
    private static let displayedThreadIDLimit = 3

    private var loadedThreadCount: Int
    private var fileIssues: [ThreadFileIssue]
    private var directoryReadFailed: Bool

    public init?(listing: ThreadListing) {
        guard listing.directoryReadFailed || !listing.issues.isEmpty else { return nil }
        self.loadedThreadCount = listing.threads.count
        self.fileIssues = listing.issues
        self.directoryReadFailed = listing.directoryReadFailed
    }

    var runtimeIssue: RuntimeIssueSurface {
        RuntimeIssueSurface(
            severity: .warning,
            title: title,
            message: message,
            actionLabel: "Review diagnostics",
            recovery: RuntimeRecoveryTelemetry(
                route: .settings,
                reason: .savedChatsUnreadable,
                commandID: "settings"
            ),
            diagnostics: diagnostics
        )
    }

    private var title: String {
        if directoryReadFailed {
            return "Saved chats could not be inspected"
        }
        return fileIssues.count == 1
            ? "A saved chat could not be loaded"
            : "Some saved chats could not be loaded"
    }

    private var message: String {
        if directoryReadFailed {
            return "\(QuillCodeProduct.displayName) started without changing the chat directory. " +
                "Review the storage diagnostics before continuing."
        }
        let count = fileIssues.count
        let noun = count == 1 ? "chat" : "chats"
        let healthy = loadedThreadCount == 0
            ? ""
            : " Your other \(loadedThreadCount) \(loadedThreadCount == 1 ? "chat is" : "chats are") still available."
        return "\(count) saved \(noun) could not be loaded.\(healthy) " +
            "The affected files were left unchanged so they can be recovered."
    }

    private var diagnostics: [RuntimeDiagnosticSurface] {
        var rows = [
            RuntimeDiagnosticSurface(label: "Loaded chats", value: String(loadedThreadCount)),
            RuntimeDiagnosticSurface(label: "Affected files", value: String(fileIssues.count)),
        ]
        appendCount(.exceedsSizeLimit, label: "Oversized files", to: &rows)
        appendCount(.symbolicLink, label: "Rejected links", to: &rows)
        appendCount(.notRegularFile, label: "Non-file paths", to: &rows)
        if directoryReadFailed {
            rows.append(RuntimeDiagnosticSurface(label: "Directory scan", value: "Failed"))
        }
        if let threadIDs = displayedThreadIDs {
            rows.append(RuntimeDiagnosticSurface(label: "Chat IDs", value: threadIDs))
        }
        rows.append(RuntimeDiagnosticSurface(
            label: "Recovery",
            value: "Back up ~/.quillcode/threads, then run quill-code doctor."
        ))
        return rows
    }

    private var displayedThreadIDs: String? {
        let ids = fileIssues.compactMap { issue -> String? in
            let stem = issue.fileURL.deletingPathExtension().lastPathComponent
            return UUID(uuidString: stem)?.uuidString.lowercased()
        }
        guard !ids.isEmpty else { return nil }
        let displayed = ids.prefix(Self.displayedThreadIDLimit)
        let remainder = ids.count - displayed.count
        return displayed.joined(separator: ", ") + (remainder > 0 ? " and \(remainder) more" : "")
    }

    private func appendCount(
        _ reason: ThreadFileIssueReason,
        label: String,
        to rows: inout [RuntimeDiagnosticSurface]
    ) {
        let count = fileIssues.count { $0.reason == reason }
        guard count > 0 else { return }
        rows.append(RuntimeDiagnosticSurface(label: label, value: String(count)))
    }
}
