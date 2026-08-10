import Foundation

enum SpendLimitAdjustment {
    static let presets: [Double] = [0.25, 0.50, 1, 2, 5, 10, 25, 50, 100]

    static func increasedLimit(current: Double?, spentUSD: Double) -> Double {
        let baseline = max(current ?? 0, spentUSD, current == nil ? 0.50 : 0)
        if let preset = presets.first(where: { $0 > baseline + 0.000_001 }) {
            return preset
        }
        return roundedCurrency(max(baseline * 2, 1))
    }

    static func decreasedLimit(current: Double?, spentUSD: Double) -> Double? {
        guard let current else { return nil }
        return presets.last(where: {
            $0 < current - 0.000_001 && $0 > spentUSD + 0.000_001
        })
    }

    static func canDecrease(current: Double?, spentUSD: Double) -> Bool {
        decreasedLimit(current: current, spentUSD: spentUSD) != nil
    }

    private static func roundedCurrency(_ value: Double) -> Double {
        (value * 100).rounded(.up) / 100
    }
}
