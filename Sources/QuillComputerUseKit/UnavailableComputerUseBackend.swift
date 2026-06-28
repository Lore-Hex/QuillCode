import Foundation

public struct UnavailableComputerUseBackend: ComputerUseBackend {
    public let status: ComputerUseStatus

    public init(status: ComputerUseStatus) {
        self.status = status
    }

    public func screenshot() async throws -> ComputerScreenshot {
        throw ComputerUseError.unavailable(reason)
    }

    public func leftClick(x _: Int, y _: Int) async throws {
        throw ComputerUseError.unavailable(reason)
    }

    public func type(_: String) async throws {
        throw ComputerUseError.unavailable(reason)
    }

    public func scroll(dx _: Int, dy _: Int) async throws {
        throw ComputerUseError.unavailable(reason)
    }

    public func moveCursor(x _: Int, y _: Int) async throws {
        throw ComputerUseError.unavailable(reason)
    }

    public func pressKey(_: String) async throws {
        throw ComputerUseError.unavailable(reason)
    }

    private var reason: String {
        status.unavailableReason ?? status.message
    }
}
