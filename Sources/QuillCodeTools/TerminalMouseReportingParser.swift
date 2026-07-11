struct TerminalMouseModeState: Sendable, Hashable {
    private var trackingModes: Set<Int> = []
    private var encodings: Set<Int> = []

    init(reporting: TerminalMouseReporting = .disabled) {
        switch reporting.trackingMode {
        case .disabled: break
        case .button: trackingModes.insert(1_000)
        case .buttonMotion: trackingModes.insert(1_002)
        case .anyMotion: trackingModes.insert(1_003)
        }
        switch reporting.encoding {
        case .x10: break
        case .utf8: encodings.insert(1_005)
        case .sgr: encodings.insert(1_006)
        case .urxvt: encodings.insert(1_015)
        }
    }

    var reporting: TerminalMouseReporting {
        TerminalMouseReporting(
            trackingMode: trackingMode,
            encoding: encoding
        )
    }

    mutating func update(privateMode mode: Int, isEnabled: Bool) {
        switch mode {
        case 1_000, 1_002, 1_003:
            update(mode, in: &trackingModes, isEnabled: isEnabled)
        case 1_005, 1_006, 1_015:
            update(mode, in: &encodings, isEnabled: isEnabled)
        default:
            break
        }
    }

    private var trackingMode: TerminalMouseTrackingMode {
        if trackingModes.contains(1_003) { return .anyMotion }
        if trackingModes.contains(1_002) { return .buttonMotion }
        if trackingModes.contains(1_000) { return .button }
        return .disabled
    }

    private var encoding: TerminalMouseEncoding {
        if encodings.contains(1_006) { return .sgr }
        if encodings.contains(1_015) { return .urxvt }
        if encodings.contains(1_005) { return .utf8 }
        return .x10
    }

    private func update(_ mode: Int, in modes: inout Set<Int>, isEnabled: Bool) {
        if isEnabled {
            modes.insert(mode)
        } else {
            modes.remove(mode)
        }
    }
}

/// Incrementally tracks the DEC private modes that control terminal mouse input. Unlike the screen
/// renderer, this parser retains an incomplete CSI sequence between output chunks, so streaming PTY
/// output does not need to be reparsed from the beginning after every write.
public struct TerminalMouseReportingParser: Sendable, Hashable {
    private static let maximumParameterLength = 64

    private enum State: Sendable, Hashable {
        case ground
        case escape
        case csi(String)
    }

    private var modeState: TerminalMouseModeState
    private var state: State = .ground

    public init(reporting: TerminalMouseReporting = .disabled) {
        self.modeState = TerminalMouseModeState(reporting: reporting)
    }

    public var reporting: TerminalMouseReporting {
        modeState.reporting
    }

    public mutating func consume(_ output: String) {
        for scalar in output.unicodeScalars {
            consume(scalar)
        }
    }

    public mutating func reset() {
        self = TerminalMouseReportingParser()
    }

    private mutating func consume(_ scalar: Unicode.Scalar) {
        switch state {
        case .ground:
            if scalar == "\u{1B}" { state = .escape }
        case .escape:
            if scalar == "[" {
                state = .csi("")
            } else {
                state = scalar == "\u{1B}" ? .escape : .ground
            }
        case .csi(var parameters):
            let value = scalar.value
            if value >= 0x40, value <= 0x7E {
                apply(final: scalar, parameters: parameters)
                state = .ground
            } else if scalar == "\u{1B}" {
                state = .escape
            } else if value >= 0x20, value <= 0x3F,
                      parameters.unicodeScalars.count < Self.maximumParameterLength {
                parameters.unicodeScalars.append(scalar)
                state = .csi(parameters)
            } else {
                state = .ground
            }
        }
    }

    private mutating func apply(final: Unicode.Scalar, parameters: String) {
        guard final == "h" || final == "l", parameters.first == "?" else { return }
        let isEnabled = final == "h"
        for mode in parameters.dropFirst().split(separator: ";").compactMap({ Int($0) }) {
            modeState.update(privateMode: mode, isEnabled: isEnabled)
        }
    }
}
