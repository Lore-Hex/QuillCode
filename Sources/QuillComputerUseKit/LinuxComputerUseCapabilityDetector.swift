import Foundation

public struct LinuxComputerUseCapabilityDetector: Sendable {
    public typealias ExecutableLookup = @Sendable (_ executableName: String) -> Bool

    private let environment: [String: String]
    private let executableLookup: ExecutableLookup?

    public init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        executableLookup: ExecutableLookup? = nil
    ) {
        self.environment = environment
        self.executableLookup = executableLookup
    }

    public func report() -> LinuxComputerUseCapabilityReport {
        let session = LinuxComputerUseSession.detect(from: environment)
        switch session {
        case .none:
            return LinuxComputerUseCapabilityReport(
                session: session,
                availableHelpers: [],
                missingHelpers: [],
                status: .unavailable(
                    "Linux Computer Use needs a graphical Wayland or X11 session."
                )
            )
        case .wayland:
            return waylandReport()
        case .x11:
            return x11Report()
        }
    }

    private func waylandReport() -> LinuxComputerUseCapabilityReport {
        let hasScreenshot = hasExecutable("grim")
        let hasPointerAndKeys = hasExecutable("ydotool")
        let hasTyping = hasPointerAndKeys || hasExecutable("wtype")
        var available: [String] = []
        var missing: [String] = []

        if hasScreenshot {
            available.append("grim")
        } else {
            missing.append("grim")
        }

        if hasPointerAndKeys {
            available.append("ydotool")
        } else {
            missing.append("ydotool")
        }

        if hasTyping {
            if !hasPointerAndKeys {
                available.append("wtype")
            }
        } else {
            missing.append("wtype")
        }

        return helperReport(
            session: .wayland,
            availableHelpers: available,
            missingHelpers: missing
        )
    }

    private func x11Report() -> LinuxComputerUseCapabilityReport {
        let hasImport = hasExecutable("import")
        let hasScrot = hasExecutable("scrot")
        let screenshotHelper = hasImport ? "import" : (hasScrot ? "scrot" : nil)
        let hasInput = hasExecutable("xdotool")
        var available: [String] = []
        var missing: [String] = []

        if let screenshotHelper {
            available.append(screenshotHelper)
        } else {
            missing.append("import or scrot")
        }

        if hasInput {
            available.append("xdotool")
        } else {
            missing.append("xdotool")
        }

        return helperReport(
            session: .x11,
            availableHelpers: available,
            missingHelpers: missing
        )
    }

    private func helperReport(
        session: LinuxComputerUseSession,
        availableHelpers: [String],
        missingHelpers: [String]
    ) -> LinuxComputerUseCapabilityReport {
        let status: ComputerUseStatus
        if missingHelpers.isEmpty {
            status = ComputerUseStatus(
                available: true,
                screenRecordingGranted: true,
                accessibilityGranted: true,
                message: "Linux Computer Use ready (\(session.displayName) helpers detected)."
            )
        } else {
            status = .unavailable(
                "Linux Computer Use detected \(session.displayName) but needs helper tools: \(missingHelpers.joined(separator: ", "))."
            )
        }
        return LinuxComputerUseCapabilityReport(
            session: session,
            availableHelpers: availableHelpers,
            missingHelpers: missingHelpers,
            status: status
        )
    }

    private func hasExecutable(_ executableName: String) -> Bool {
        if let executableLookup {
            return executableLookup(executableName)
        }
        return Self.executableExists(
            executableName,
            path: environment["PATH"] ?? ""
        )
    }

    private static func executableExists(
        _ executableName: String,
        path: String
    ) -> Bool {
        path
            .split(separator: ":")
            .map(String.init)
            .contains { directory in
                FileManager.default.isExecutableFile(
                    atPath: URL(fileURLWithPath: directory)
                        .appendingPathComponent(executableName)
                        .path
                )
            }
    }
}

public struct LinuxComputerUseCapabilityReport: Codable, Sendable, Hashable {
    public var session: LinuxComputerUseSession
    public var availableHelpers: [String]
    public var missingHelpers: [String]
    public var status: ComputerUseStatus

    public init(
        session: LinuxComputerUseSession,
        availableHelpers: [String],
        missingHelpers: [String],
        status: ComputerUseStatus
    ) {
        self.session = session
        self.availableHelpers = availableHelpers
        self.missingHelpers = missingHelpers
        self.status = status
    }
}

public enum LinuxComputerUseSession: String, Codable, Sendable, Hashable {
    case none
    case wayland
    case x11

    public static func detect(from environment: [String: String]) -> LinuxComputerUseSession {
        let sessionType = environment["XDG_SESSION_TYPE"]?.lowercased()
        if sessionType == "wayland" || environment["WAYLAND_DISPLAY"]?.isEmpty == false {
            return .wayland
        }
        if sessionType == "x11" || environment["DISPLAY"]?.isEmpty == false {
            return .x11
        }
        return .none
    }

    public var displayName: String {
        switch self {
        case .none:
            return "no graphical session"
        case .wayland:
            return "Wayland"
        case .x11:
            return "X11"
        }
    }
}
