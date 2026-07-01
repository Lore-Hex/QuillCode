public struct ComputerUseStatus: Codable, Sendable, Hashable {
    public var available: Bool
    public var screenRecordingGranted: Bool
    public var accessibilityGranted: Bool
    public var message: String
    public var unavailableReason: String?

    public init(
        available: Bool,
        screenRecordingGranted: Bool,
        accessibilityGranted: Bool,
        message: String,
        unavailableReason: String? = nil
    ) {
        self.available = available
        self.screenRecordingGranted = screenRecordingGranted
        self.accessibilityGranted = accessibilityGranted
        self.message = message
        self.unavailableReason = unavailableReason
    }

    public static func permissionStatus(
        screenRecordingGranted: Bool,
        accessibilityGranted: Bool
    ) -> ComputerUseStatus {
        let available = screenRecordingGranted && accessibilityGranted
        let message: String
        switch (screenRecordingGranted, accessibilityGranted) {
        case (true, true):
            message = "Computer Use ready"
        case (false, false):
            message = "Needs Screen Recording + Accessibility"
        case (false, true):
            message = "Needs Screen Recording"
        case (true, false):
            message = "Needs Accessibility"
        }
        return ComputerUseStatus(
            available: available,
            screenRecordingGranted: screenRecordingGranted,
            accessibilityGranted: accessibilityGranted,
            message: message
        )
    }

    public static func unavailable(_ reason: String) -> ComputerUseStatus {
        ComputerUseStatus(
            available: false,
            screenRecordingGranted: false,
            accessibilityGranted: false,
            message: reason,
            unavailableReason: reason
        )
    }

    public static func unsupportedPlatform(_ reason: String) -> ComputerUseStatus {
        unavailable("Unsupported platform: \(reason)")
    }
}
