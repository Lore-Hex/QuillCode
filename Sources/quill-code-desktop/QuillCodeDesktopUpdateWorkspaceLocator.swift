import Foundation

/// Locates an update workspace from the helper executable inside it.
///
/// The helper used to be a bare copy of the running executable placed directly
/// in the workspace, so the workspace was simply its parent directory. A
/// Developer ID signature seals the bundle's `Info.plist`, so an executable
/// copied out of its bundle fails validation and the kernel kills it at exec
/// with SIGKILL -- invisible under ad-hoc signing, fatal once the app is
/// really signed. The helper therefore now runs from a copy of the whole app
/// bundle, and the workspace is the directory holding that bundle.
///
/// Both sides derive the workspace with this, so the parent and the helper --
/// which rebuilds its own path from `Bundle.main.executableURL` -- continue to
/// agree without changing the argument contract between them.
enum QuillCodeDesktopUpdateWorkspaceLocator {
    static func workspaceURL(forHelperAt helperURL: URL) -> URL {
        let executableParent = helperURL.deletingLastPathComponent()
        guard executableParent.lastPathComponent == "MacOS" else {
            return executableParent.standardizedFileURL
        }
        let contentsURL = executableParent.deletingLastPathComponent()
        guard contentsURL.lastPathComponent == "Contents" else {
            return executableParent.standardizedFileURL
        }
        let bundleURL = contentsURL.deletingLastPathComponent()
        guard bundleURL.pathExtension == "app" else {
            return executableParent.standardizedFileURL
        }
        return bundleURL.deletingLastPathComponent().standardizedFileURL
    }

    /// The helper bundle itself, when the helper runs from one.
    static func helperBundleURL(forHelperAt helperURL: URL) -> URL? {
        let workspace = workspaceURL(forHelperAt: helperURL)
        guard workspace != helperURL.deletingLastPathComponent() else { return nil }
        return helperURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .standardizedFileURL
    }

    /// The `.app` bundle containing a running executable, if there is one.
    static func applicationBundleURL(forExecutableAt executableURL: URL) -> URL? {
        let macOSURL = executableURL.deletingLastPathComponent()
        guard macOSURL.lastPathComponent == "MacOS" else { return nil }
        let contentsURL = macOSURL.deletingLastPathComponent()
        guard contentsURL.lastPathComponent == "Contents" else { return nil }
        let bundleURL = contentsURL.deletingLastPathComponent()
        guard bundleURL.pathExtension == "app" else { return nil }
        return bundleURL.standardizedFileURL
    }
}
