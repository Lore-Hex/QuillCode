extension TerminalScreenBuffer {
    mutating func setScrollRegion(_ params: String) {
        guard !params.isEmpty else {
            resetScrollRegion()
            return
        }

        let parts = csiParams(params)
        let top = Swift.max(1, parts.first ?? 1) - 1
        let bottomParameter = parts.count > 1 ? parts[1] : Swift.max(lines.count, top + 2)
        let bottom = Swift.max(top + 1, bottomParameter - 1)
        guard bottom <= Self.maxRows else {
            resetScrollRegion()
            return
        }

        setRow(bottom)
        scrollRegion = (top, bottom)
        setCursor(row: originMode ? top : 0, col: 0)
    }

    mutating func resetScrollRegion() {
        scrollRegion = nil
        setCursor(row: 0, col: 0)
    }

    func boundedScrollRegion() -> (top: Int, bottom: Int)? {
        guard let scrollRegion, scrollRegion.top >= 0, scrollRegion.bottom > scrollRegion.top else {
            return nil
        }
        return (scrollRegion.top, Swift.min(scrollRegion.bottom, Self.maxRows))
    }

    mutating func scrollBounds() -> (top: Int, bottom: Int) {
        if let region = boundedScrollRegion() {
            ensureRow(region.bottom)
            return region
        }

        let lastVisibleRow = Swift.max(lines.count - 1, row)
        let bottom = Swift.max(0, Swift.min(lastVisibleRow, Self.maxRows))
        ensureRow(bottom)
        return (0, bottom)
    }
}
