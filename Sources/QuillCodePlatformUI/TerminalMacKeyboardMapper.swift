#if canImport(AppKit)
import AppKit
import QuillCodeTools

enum TerminalMacKeyboardMapper {
    static func inputEvent(from event: NSEvent) -> TerminalKeyboardInputEvent? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard !flags.contains(.command) else { return nil }
        let modifiers = TerminalKeyboardModifiers(
            shift: flags.contains(.shift),
            option: flags.contains(.option),
            control: flags.contains(.control)
        )
        guard let key = key(from: event, flags: flags) else { return nil }
        return TerminalKeyboardInputEvent(key: key, modifiers: modifiers)
    }

    private static func key(
        from event: NSEvent,
        flags: NSEvent.ModifierFlags
    ) -> TerminalKeyboardKey? {
        switch event.keyCode {
        case 36, 76: return .enter
        case 48: return flags.contains(.shift) ? .backtab : .tab
        case 51: return .backspace
        case 53: return .escape
        case 114: return .insert
        case 115: return .home
        case 116: return .pageUp
        case 117: return .deleteForward
        case 119: return .end
        case 121: return .pageDown
        case 123: return .arrowLeft
        case 124: return .arrowRight
        case 125: return .arrowDown
        case 126: return .arrowUp
        case 122: return .function(1)
        case 120: return .function(2)
        case 99: return .function(3)
        case 118: return .function(4)
        case 96: return .function(5)
        case 97: return .function(6)
        case 98: return .function(7)
        case 100: return .function(8)
        case 101: return .function(9)
        case 109: return .function(10)
        case 103: return .function(11)
        case 111: return .function(12)
        default:
            let text = (flags.contains(.control) || flags.contains(.option))
                ? event.charactersIgnoringModifiers
                : event.characters
            return text.flatMap { $0.isEmpty ? nil : .text($0) }
        }
    }
}
#endif
