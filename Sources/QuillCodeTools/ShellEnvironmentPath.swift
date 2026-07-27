import Foundation

/// Ensures the agent's shell can find developer tools even when QuillCode was launched as a GUI `.app`.
///
/// A `.app` opened from Finder/Dock/launchd inherits only launchd's minimal environment — its `PATH`
/// is the bare `path_helper` default (`/usr/bin:/bin:/usr/sbin:/sbin` plus a couple of Apple dirs).
/// On Apple-Silicon macOS, Homebrew installs to `/opt/homebrew/bin` and adds it to `PATH` per-user via
/// `brew shellenv` in `~/.zprofile` — which a non-interactive, non-login `/bin/sh` never sources. The
/// net effect: the agent's shell tool cannot see `uv`, `python3`, `node`, `rg`, `cargo`, or anything
/// else installed through Homebrew or a language toolchain, and every command that needs them fails
/// with `exit code 127` — observed live driving a repo-onboarding task where `uv pip install` 127'd
/// even though `uv` was installed at `/opt/homebrew/bin/uv`.
///
/// This augments `PATH` with the standard developer-tool locations, APPENDING them so anything already
/// resolvable keeps its existing priority (a task that relied on `/usr/bin/python3` still gets it) —
/// the augmentation only fills the gaps a minimal launchd `PATH` leaves.
public enum ShellEnvironmentPath {
    /// Absolute tool directories a GUI-launched app's minimal `PATH` omits.
    public static let developerToolDirectories = [
        "/opt/homebrew/bin",   // Apple-Silicon Homebrew
        "/opt/homebrew/sbin",
        "/usr/local/bin",      // Intel Homebrew / manual installs
        "/usr/local/sbin",
    ]

    /// Per-user tool directories, resolved against `HOME`.
    public static let homeRelativeToolDirectories = [
        ".local/bin",   // pipx, uv tools, pip --user
        ".cargo/bin",   // Rust
        "go/bin",       // Go
    ]

    /// `base` PATH with the developer-tool directories appended (de-duplicated, order-preserving).
    /// The existing entries keep their priority; only missing dev-tool dirs are added.
    public static func augmentedPATH(base: String?, home: String?) -> String {
        var seen = Set<String>()
        var entries: [String] = []
        func add(_ candidate: String) {
            guard !candidate.isEmpty, !seen.contains(candidate) else { return }
            seen.insert(candidate)
            entries.append(candidate)
        }
        for segment in (base ?? "").split(separator: ":", omittingEmptySubsequences: true) {
            add(String(segment))
        }
        for directory in developerToolDirectories { add(directory) }
        if let home, !home.isEmpty {
            let root = home.hasSuffix("/") ? String(home.dropLast()) : home
            for relative in homeRelativeToolDirectories { add("\(root)/\(relative)") }
        }
        return entries.joined(separator: ":")
    }
}
