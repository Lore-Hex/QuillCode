import Foundation

struct TerminalDECPrivateModeUpdate: Sendable, Hashable {
    var mode: Int
    var isEnabled: Bool
}

/// Incrementally parses DEC private-mode changes (`CSI ? ... h/l`) from a PTY byte stream.
/// Consumers keep their own semantic state while sharing chunk-boundary and input-bounding logic.
struct TerminalDECPrivateModeParser: Sendable, Hashable {
    private static let maximumParameterLength = 64

    private enum State: Sendable, Hashable {
        case ground
        case escape
        case csi(String)
    }

    private var state: State = .ground

    mutating func consume(_ output: String) -> [TerminalDECPrivateModeUpdate] {
        var updates: [TerminalDECPrivateModeUpdate] = []
        for scalar in output.unicodeScalars {
            updates.append(contentsOf: consume(scalar))
        }
        return updates
    }

    mutating func reset() {
        state = .ground
    }

    private mutating func consume(_ scalar: Unicode.Scalar) -> [TerminalDECPrivateModeUpdate] {
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
                state = .ground
                return Self.updates(final: scalar, parameters: parameters)
            }
            if scalar == "\u{1B}" {
                state = .escape
            } else if value >= 0x20, value <= 0x3F,
                      parameters.unicodeScalars.count < Self.maximumParameterLength {
                parameters.unicodeScalars.append(scalar)
                state = .csi(parameters)
            } else {
                state = .ground
            }
        }
        return []
    }

    private static func updates(
        final: Unicode.Scalar,
        parameters: String
    ) -> [TerminalDECPrivateModeUpdate] {
        guard final == "h" || final == "l", parameters.first == "?" else { return [] }
        let isEnabled = final == "h"
        return parameters.dropFirst().split(separator: ";").compactMap { field in
            guard let mode = Int(field) else { return nil }
            return TerminalDECPrivateModeUpdate(mode: mode, isEnabled: isEnabled)
        }
    }
}
