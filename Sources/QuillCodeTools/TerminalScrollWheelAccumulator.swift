public struct TerminalScrollWheelAccumulator: Sendable, Hashable {
    public static let defaultPreciseThreshold = 8.0
    public static let defaultMaximumEventsPerUpdate = 8

    private var remainder = 0.0
    private var activeAxis: Axis?

    public init() {}

    /// Converts platform scroll deltas into bounded terminal wheel steps.
    /// Positive vertical values mean up; positive horizontal values mean left.
    public mutating func consume(
        horizontalDelta: Double,
        verticalDelta: Double,
        isPrecise: Bool
    ) -> [TerminalMouseEventKind] {
        guard horizontalDelta.isFinite,
              verticalDelta.isFinite else {
            reset()
            return []
        }

        let axis = dominantAxis(horizontalDelta: horizontalDelta, verticalDelta: verticalDelta)
        guard let axis else { return [] }
        if activeAxis != axis {
            activeAxis = axis
            remainder = 0
        }

        let delta = axis == .horizontal ? horizontalDelta : verticalDelta
        let threshold = isPrecise ? Self.defaultPreciseThreshold : 1
        let maximumMagnitude = threshold * Double(Self.defaultMaximumEventsPerUpdate)
        let accumulated = remainder + delta
        if accumulated.isFinite {
            remainder = min(maximumMagnitude, max(-maximumMagnitude, accumulated))
        } else {
            remainder = delta.sign == .minus ? -maximumMagnitude : maximumMagnitude
        }
        let availableSteps = Int(abs(remainder) / threshold)
        guard availableSteps > 0 else { return [] }

        let count = min(availableSteps, Self.defaultMaximumEventsPerUpdate)
        let kind = eventKind(axis: axis, positive: remainder > 0)
        remainder -= (remainder > 0 ? 1 : -1) * Double(count) * threshold
        return Array(repeating: kind, count: count)
    }

    public mutating func reset() {
        remainder = 0
        activeAxis = nil
    }

    private func dominantAxis(horizontalDelta: Double, verticalDelta: Double) -> Axis? {
        if abs(verticalDelta) >= abs(horizontalDelta), verticalDelta != 0 {
            return .vertical
        }
        if horizontalDelta != 0 {
            return .horizontal
        }
        return nil
    }

    private func eventKind(axis: Axis, positive: Bool) -> TerminalMouseEventKind {
        switch (axis, positive) {
        case (.vertical, true): .scrollUp
        case (.vertical, false): .scrollDown
        case (.horizontal, true): .scrollLeft
        case (.horizontal, false): .scrollRight
        }
    }

    private enum Axis: Sendable, Hashable {
        case horizontal
        case vertical
    }
}
