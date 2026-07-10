extension TerminalScreenBuffer {
    mutating func applyPrivateMode(final: Unicode.Scalar, params: String) {
        guard final == "h" || final == "l" else { return }
        let isEnabled = final == "h"
        for mode in privateModeNumbers(params) {
            switch mode {
            case 47, 1_047, 1_049:
                if isEnabled { enterAlternateScreen() } else { leaveAlternateScreen() }
            case 1_000, 1_002, 1_003, 1_005, 1_006, 1_015:
                mouseModeState.update(privateMode: mode, isEnabled: isEnabled)
            default:
                break
            }
        }
    }

    var mouseReporting: TerminalMouseReporting {
        mouseModeState.reporting
    }

    private func privateModeNumbers(_ params: String) -> [Int] {
        guard params.first == "?" else { return [] }
        return params.dropFirst().split(separator: ";").compactMap { Int($0) }
    }
}
