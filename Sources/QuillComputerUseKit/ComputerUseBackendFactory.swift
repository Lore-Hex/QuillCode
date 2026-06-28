import Foundation

public struct ComputerUseBackendFactory: Sendable {
    private let makeBackend: @Sendable () -> any ComputerUseBackend

    public init(makeBackend: @escaping @Sendable () -> any ComputerUseBackend) {
        self.makeBackend = makeBackend
    }

    public func backend() -> any ComputerUseBackend {
        makeBackend()
    }

    public static func platformDefault() -> ComputerUseBackendFactory {
        #if canImport(AppKit) && canImport(ApplicationServices) && canImport(CoreGraphics)
        return ComputerUseBackendFactory {
            MacComputerUseBackend()
        }
        #elseif os(Linux)
        return ComputerUseBackendFactory {
            UnavailableComputerUseBackend(
                status: LinuxComputerUseCapabilityDetector().report().status
            )
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
