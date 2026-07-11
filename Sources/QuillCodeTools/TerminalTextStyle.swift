import Foundation

public struct TerminalRGBColor: Codable, Sendable, Hashable {
    public var red: UInt8
    public var green: UInt8
    public var blue: UInt8

    public init(red: UInt8, green: UInt8, blue: UInt8) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    public var cssHex: String {
        String(format: "#%02X%02X%02X", red, green, blue)
    }
}

public enum TerminalTextColor: Codable, Sendable, Hashable {
    case black
    case red
    case green
    case yellow
    case blue
    case magenta
    case cyan
    case white
    case brightBlack
    case brightRed
    case brightGreen
    case brightYellow
    case brightBlue
    case brightMagenta
    case brightCyan
    case brightWhite
    case indexed(UInt8)
    case rgb(TerminalRGBColor)

    public var resolvedRGB: TerminalRGBColor {
        switch self {
        case .black: return TerminalRGBColor(red: 0, green: 0, blue: 0)
        case .red: return TerminalRGBColor(red: 205, green: 0, blue: 0)
        case .green: return TerminalRGBColor(red: 0, green: 205, blue: 0)
        case .yellow: return TerminalRGBColor(red: 205, green: 205, blue: 0)
        case .blue: return TerminalRGBColor(red: 0, green: 0, blue: 238)
        case .magenta: return TerminalRGBColor(red: 205, green: 0, blue: 205)
        case .cyan: return TerminalRGBColor(red: 0, green: 205, blue: 205)
        case .white: return TerminalRGBColor(red: 229, green: 229, blue: 229)
        case .brightBlack: return TerminalRGBColor(red: 127, green: 127, blue: 127)
        case .brightRed: return TerminalRGBColor(red: 255, green: 0, blue: 0)
        case .brightGreen: return TerminalRGBColor(red: 0, green: 255, blue: 0)
        case .brightYellow: return TerminalRGBColor(red: 255, green: 255, blue: 0)
        case .brightBlue: return TerminalRGBColor(red: 92, green: 92, blue: 255)
        case .brightMagenta: return TerminalRGBColor(red: 255, green: 0, blue: 255)
        case .brightCyan: return TerminalRGBColor(red: 0, green: 255, blue: 255)
        case .brightWhite: return TerminalRGBColor(red: 255, green: 255, blue: 255)
        case let .indexed(index): return Self.indexedRGB(index)
        case let .rgb(color): return color
        }
    }

    private static func indexedRGB(_ index: UInt8) -> TerminalRGBColor {
        if index < 16 {
            return standardColor(for: index).resolvedRGB
        }
        if index < 232 {
            let offset = Int(index) - 16
            let red = offset / 36
            let green = (offset % 36) / 6
            let blue = offset % 6
            return TerminalRGBColor(
                red: cubeComponent(red),
                green: cubeComponent(green),
                blue: cubeComponent(blue)
            )
        }
        let gray = UInt8(8 + (Int(index) - 232) * 10)
        return TerminalRGBColor(red: gray, green: gray, blue: gray)
    }

    private static func standardColor(for index: UInt8) -> TerminalTextColor {
        switch index {
        case 0: return .black
        case 1: return .red
        case 2: return .green
        case 3: return .yellow
        case 4: return .blue
        case 5: return .magenta
        case 6: return .cyan
        case 7: return .white
        case 8: return .brightBlack
        case 9: return .brightRed
        case 10: return .brightGreen
        case 11: return .brightYellow
        case 12: return .brightBlue
        case 13: return .brightMagenta
        case 14: return .brightCyan
        default: return .brightWhite
        }
    }

    private static func cubeComponent(_ value: Int) -> UInt8 {
        UInt8(value == 0 ? 0 : 55 + value * 40)
    }
}

public struct TerminalTextStyle: Codable, Sendable, Hashable {
    public var foreground: TerminalTextColor?
    public var background: TerminalTextColor?
    public var isBold: Bool
    public var isFaint: Bool
    public var isItalic: Bool
    public var isUnderlined: Bool
    public var isInverse: Bool
    public var isConcealed: Bool
    public var isStrikethrough: Bool

    public init(
        foreground: TerminalTextColor? = nil,
        background: TerminalTextColor? = nil,
        isBold: Bool = false,
        isFaint: Bool = false,
        isItalic: Bool = false,
        isUnderlined: Bool = false,
        isInverse: Bool = false,
        isConcealed: Bool = false,
        isStrikethrough: Bool = false
    ) {
        self.foreground = foreground
        self.background = background
        self.isBold = isBold
        self.isFaint = isFaint
        self.isItalic = isItalic
        self.isUnderlined = isUnderlined
        self.isInverse = isInverse
        self.isConcealed = isConcealed
        self.isStrikethrough = isStrikethrough
    }

    public static let plain = TerminalTextStyle()
}

public struct TerminalTextRun: Codable, Sendable, Hashable {
    public var text: String
    public var style: TerminalTextStyle

    public init(text: String, style: TerminalTextStyle = .plain) {
        self.text = text
        self.style = style
    }
}

public struct TerminalRenderedFrame: Codable, Sendable, Hashable {
    public var text: String
    public var runs: [TerminalTextRun]
    public var mouseReporting: TerminalMouseReporting

    public init(
        text: String,
        runs: [TerminalTextRun],
        mouseReporting: TerminalMouseReporting = .disabled
    ) {
        self.text = text
        self.runs = runs
        self.mouseReporting = mouseReporting
    }
}
