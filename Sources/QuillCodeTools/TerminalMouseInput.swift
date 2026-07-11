public enum TerminalMouseTrackingMode: String, Codable, Sendable, Hashable {
    case disabled
    case button
    case buttonMotion
    case anyMotion

    public var isEnabled: Bool {
        self != .disabled
    }

    func accepts(_ event: TerminalMouseInputEvent) -> Bool {
        switch self {
        case .disabled:
            return false
        case .button:
            return event.kind != .motion
        case .buttonMotion:
            return event.kind != .motion || event.button != .none
        case .anyMotion:
            return true
        }
    }
}

public enum TerminalMouseEncoding: String, Codable, Sendable, Hashable {
    case x10
    case utf8
    case sgr
    case urxvt
}

public struct TerminalMouseReporting: Codable, Sendable, Hashable {
    public var trackingMode: TerminalMouseTrackingMode
    public var encoding: TerminalMouseEncoding

    public init(
        trackingMode: TerminalMouseTrackingMode = .disabled,
        encoding: TerminalMouseEncoding = .x10
    ) {
        self.trackingMode = trackingMode
        self.encoding = encoding
    }

    public static let disabled = TerminalMouseReporting()

    public var isEnabled: Bool {
        trackingMode.isEnabled
    }
}

public enum TerminalMouseButton: Int, Codable, Sendable, Hashable {
    case left = 0
    case middle = 1
    case right = 2
    case none = 3
}

public enum TerminalMouseEventKind: String, Codable, Sendable, Hashable {
    case press
    case release
    case motion
    case scrollUp
    case scrollDown
    case scrollLeft
    case scrollRight
}

public struct TerminalMouseModifiers: Codable, Sendable, Hashable {
    public var shift: Bool
    public var option: Bool
    public var control: Bool

    public init(shift: Bool = false, option: Bool = false, control: Bool = false) {
        self.shift = shift
        self.option = option
        self.control = control
    }
}

public struct TerminalMousePosition: Codable, Sendable, Hashable {
    public var column: Int
    public var row: Int

    public init(column: Int, row: Int) {
        self.column = column
        self.row = row
    }
}

public struct TerminalMouseInputEvent: Codable, Sendable, Hashable {
    public var kind: TerminalMouseEventKind
    public var button: TerminalMouseButton
    public var position: TerminalMousePosition
    public var modifiers: TerminalMouseModifiers

    public init(
        kind: TerminalMouseEventKind,
        button: TerminalMouseButton = .none,
        position: TerminalMousePosition,
        modifiers: TerminalMouseModifiers = TerminalMouseModifiers()
    ) {
        self.kind = kind
        self.button = button
        self.position = position
        self.modifiers = modifiers
    }
}

public struct TerminalMouseInputRequest: Codable, Sendable, Hashable {
    public var event: TerminalMouseInputEvent
    public var reporting: TerminalMouseReporting

    public init(event: TerminalMouseInputEvent, reporting: TerminalMouseReporting) {
        self.event = event
        self.reporting = reporting
    }
}

public enum TerminalMouseInputEncoder {
    public static func encode(_ request: TerminalMouseInputRequest) -> String? {
        let event = request.event
        let reporting = request.reporting
        guard reporting.trackingMode.accepts(event),
              event.position.column > 0,
              event.position.row > 0 else {
            return nil
        }

        let code = buttonCode(for: event)
        switch reporting.encoding {
        case .sgr:
            return sgrSequence(event: event, code: code)
        case .urxvt:
            return urxvtSequence(event: event, code: code)
        case .x10:
            return legacySequence(event: event, code: code, maximumCoordinate: 223)
        case .utf8:
            return legacySequence(event: event, code: code, maximumCoordinate: 2_015)
        }
    }

    private static func buttonCode(for event: TerminalMouseInputEvent) -> Int {
        let base: Int
        switch event.kind {
        case .scrollUp: base = 64
        case .scrollDown: base = 65
        case .scrollLeft: base = 66
        case .scrollRight: base = 67
        case .press, .release, .motion: base = event.button.rawValue
        }
        let motion = event.kind == .motion ? 32 : 0
        let shift = event.modifiers.shift ? 4 : 0
        let option = event.modifiers.option ? 8 : 0
        let control = event.modifiers.control ? 16 : 0
        return base + motion + shift + option + control
    }

    private static func sgrSequence(event: TerminalMouseInputEvent, code: Int) -> String {
        let terminator = event.kind == .release ? "m" : "M"
        return "\u{1B}[<\(code);\(event.position.column);\(event.position.row)\(terminator)"
    }

    private static func urxvtSequence(event: TerminalMouseInputEvent, code: Int) -> String {
        let legacyCode = event.kind == .release ? releaseCode(for: event) : code
        return "\u{1B}[\(legacyCode + 32);\(event.position.column);\(event.position.row)M"
    }

    private static func legacySequence(
        event: TerminalMouseInputEvent,
        code: Int,
        maximumCoordinate: Int
    ) -> String? {
        guard event.position.column <= maximumCoordinate,
              event.position.row <= maximumCoordinate else {
            return nil
        }
        let legacyCode = event.kind == .release ? releaseCode(for: event) : code
        guard let codeScalar = UnicodeScalar(legacyCode + 32),
              let columnScalar = UnicodeScalar(event.position.column + 32),
              let rowScalar = UnicodeScalar(event.position.row + 32) else {
            return nil
        }
        return "\u{1B}[M\(Character(codeScalar))\(Character(columnScalar))\(Character(rowScalar))"
    }

    private static func releaseCode(for event: TerminalMouseInputEvent) -> Int {
        let shift = event.modifiers.shift ? 4 : 0
        let option = event.modifiers.option ? 8 : 0
        let control = event.modifiers.control ? 16 : 0
        return TerminalMouseButton.none.rawValue + shift + option + control
    }
}
