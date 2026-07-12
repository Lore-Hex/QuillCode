import Foundation

public struct TerminalKeyboardMode: Codable, Sendable, Hashable {
    public var applicationCursorKeys: Bool
    public var bracketedPaste: Bool

    public init(applicationCursorKeys: Bool = false, bracketedPaste: Bool = false) {
        self.applicationCursorKeys = applicationCursorKeys
        self.bracketedPaste = bracketedPaste
    }

    public static let standard = TerminalKeyboardMode()
}

public struct TerminalKeyboardModeParser: Sendable, Hashable {
    private var parser = TerminalDECPrivateModeParser()
    public private(set) var mode: TerminalKeyboardMode

    public init(mode: TerminalKeyboardMode = .standard) {
        self.mode = mode
    }

    public mutating func consume(_ output: String) {
        for update in parser.consume(output) {
            switch update.mode {
            case 1:
                mode.applicationCursorKeys = update.isEnabled
            case 2_004:
                mode.bracketedPaste = update.isEnabled
            default:
                break
            }
        }
    }

    public mutating func reset() {
        self = TerminalKeyboardModeParser()
    }
}

public enum TerminalKeyboardKey: Codable, Sendable, Hashable {
    case text(String)
    case paste(String)
    case enter
    case tab
    case backtab
    case escape
    case backspace
    case deleteForward
    case insert
    case home
    case end
    case pageUp
    case pageDown
    case arrowUp
    case arrowDown
    case arrowLeft
    case arrowRight
    case function(Int)
}

public struct TerminalKeyboardModifiers: Codable, Sendable, Hashable {
    public var shift: Bool
    public var option: Bool
    public var control: Bool

    public init(shift: Bool = false, option: Bool = false, control: Bool = false) {
        self.shift = shift
        self.option = option
        self.control = control
    }

    var xtermParameter: Int {
        1 + (shift ? 1 : 0) + (option ? 2 : 0) + (control ? 4 : 0)
    }
}

public struct TerminalKeyboardInputEvent: Codable, Sendable, Hashable {
    public var key: TerminalKeyboardKey
    public var modifiers: TerminalKeyboardModifiers

    public init(
        key: TerminalKeyboardKey,
        modifiers: TerminalKeyboardModifiers = TerminalKeyboardModifiers()
    ) {
        self.key = key
        self.modifiers = modifiers
    }
}

public struct TerminalKeyboardInputRequest: Codable, Sendable, Hashable {
    public var event: TerminalKeyboardInputEvent
    public var mode: TerminalKeyboardMode

    public init(event: TerminalKeyboardInputEvent, mode: TerminalKeyboardMode) {
        self.event = event
        self.mode = mode
    }
}

public enum TerminalKeyboardInputEncoder {
    public static let maximumPasteUTF8Bytes = 256 * 1_024

    public static func encode(_ request: TerminalKeyboardInputRequest) -> String? {
        let event = request.event
        let modifier = event.modifiers.xtermParameter
        switch event.key {
        case .text(let text):
            return encodeText(text, modifiers: event.modifiers)
        case .paste(let text):
            let bounded = boundedPaste(text)
                .replacingOccurrences(of: "\u{1B}[200~", with: "")
                .replacingOccurrences(of: "\u{1B}[201~", with: "")
            guard !bounded.isEmpty else { return nil }
            return request.mode.bracketedPaste
                ? "\u{1B}[200~\(bounded)\u{1B}[201~"
                : bounded
        case .enter:
            return "\r"
        case .tab:
            return modifier == 1 ? "\t" : "\u{1B}[1;\(modifier)I"
        case .backtab:
            return "\u{1B}[Z"
        case .escape:
            return "\u{1B}"
        case .backspace:
            return "\u{7F}"
        case .deleteForward:
            return tildeSequence(code: 3, modifier: modifier)
        case .insert:
            return tildeSequence(code: 2, modifier: modifier)
        case .home:
            return cursorSequence(final: "H", modifier: modifier, applicationMode: request.mode.applicationCursorKeys)
        case .end:
            return cursorSequence(final: "F", modifier: modifier, applicationMode: request.mode.applicationCursorKeys)
        case .pageUp:
            return tildeSequence(code: 5, modifier: modifier)
        case .pageDown:
            return tildeSequence(code: 6, modifier: modifier)
        case .arrowUp:
            return cursorSequence(final: "A", modifier: modifier, applicationMode: request.mode.applicationCursorKeys)
        case .arrowDown:
            return cursorSequence(final: "B", modifier: modifier, applicationMode: request.mode.applicationCursorKeys)
        case .arrowRight:
            return cursorSequence(final: "C", modifier: modifier, applicationMode: request.mode.applicationCursorKeys)
        case .arrowLeft:
            return cursorSequence(final: "D", modifier: modifier, applicationMode: request.mode.applicationCursorKeys)
        case .function(let number):
            return functionSequence(number: number, modifier: modifier)
        }
    }

    private static func encodeText(
        _ text: String,
        modifiers: TerminalKeyboardModifiers
    ) -> String? {
        guard !text.isEmpty else { return nil }
        let encoded: String
        if modifiers.control, text.unicodeScalars.count == 1,
           let scalar = text.lowercased().unicodeScalars.first {
            if scalar == " " {
                encoded = "\u{00}"
            } else if scalar == "?" {
                encoded = "\u{7F}"
            } else if scalar.value >= 0x40, scalar.value <= 0x7F,
                      let controlScalar = Unicode.Scalar(scalar.value & 0x1F) {
                encoded = String(controlScalar)
            } else {
                encoded = text
            }
        } else {
            encoded = text
        }
        return modifiers.option ? "\u{1B}\(encoded)" : encoded
    }

    private static func cursorSequence(final: Character, modifier: Int, applicationMode: Bool) -> String {
        if modifier > 1 { return "\u{1B}[1;\(modifier)\(final)" }
        return applicationMode ? "\u{1B}O\(final)" : "\u{1B}[\(final)"
    }

    private static func tildeSequence(code: Int, modifier: Int) -> String {
        modifier > 1 ? "\u{1B}[\(code);\(modifier)~" : "\u{1B}[\(code)~"
    }

    private static func functionSequence(number: Int, modifier: Int) -> String? {
        guard (1...12).contains(number) else { return nil }
        if number <= 4 {
            let final = ["P", "Q", "R", "S"][number - 1]
            return modifier > 1 ? "\u{1B}[1;\(modifier)\(final)" : "\u{1B}O\(final)"
        }
        let code = [15, 17, 18, 19, 20, 21, 23, 24][number - 5]
        return tildeSequence(code: code, modifier: modifier)
    }

    private static func boundedPaste(_ text: String) -> String {
        guard text.utf8.count > maximumPasteUTF8Bytes else { return text }
        var result = ""
        result.reserveCapacity(maximumPasteUTF8Bytes)
        var byteCount = 0
        for character in text {
            let width = String(character).utf8.count
            guard byteCount + width <= maximumPasteUTF8Bytes else { break }
            result.append(character)
            byteCount += width
        }
        return result
    }
}
