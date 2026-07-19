import Foundation

public struct ComputerUseBackendFactory: Sendable {
    private let makeBackend: @Sendable () -> any ComputerUseBackend

    public init(makeBackend: @escaping @Sendable () -> any ComputerUseBackend) {
        self.makeBackend = makeBackend
    }

    public func backend() -> any ComputerUseBackend {
        makeBackend()
    }

    /// Opt-in gate for routing Computer Use through cua-driver instead of the native CGEvent backend.
    /// Off by default: adopting cua only changes behavior when a user explicitly sets this, so existing
    /// installs are untouched. (A Settings toggle backed by config is the next increment.)
    public static let cuaDriverPreferenceEnvironmentVariable = "QUILLCODE_USE_CUA_DRIVER"

    public static func cuaDriverPreferred(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        environment[cuaDriverPreferenceEnvironmentVariable] == "1"
    }

    public static func platformDefault() -> ComputerUseBackendFactory {
        #if canImport(AppKit) && canImport(ApplicationServices) && canImport(CoreGraphics)
        return ComputerUseBackendFactory {
            MacComputerUseBackend()
        }
        #elseif os(Linux)
        return ComputerUseBackendFactory {
            let report = LinuxComputerUseCapabilityDetector().report()
            guard report.status.available else {
                return UnavailableComputerUseBackend(status: report.status)
            }
            return LinuxComputerUseBackend(report: report)
        }
        #else
        return ComputerUseBackendFactory {
            UnavailableComputerUseBackend(
                status: .unsupportedPlatform("Computer Use is only available on macOS today.")
            )
        }
        #endif
    }
}
