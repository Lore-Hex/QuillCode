struct TerminalScreenGraphemeCluster {
    var character: Character
    var scalarCount: Int
}

enum TerminalScreenGraphemeClusters {
    static func indexed(in raw: String, scalarCount: Int) -> [TerminalScreenGraphemeCluster?] {
        guard scalarCount > 0 else { return [] }

        var starts = Array<TerminalScreenGraphemeCluster?>(repeating: nil, count: scalarCount)
        var scalarOffset = 0
        for character in raw {
            let count = character.unicodeScalars.count
            if scalarOffset < starts.count {
                starts[scalarOffset] = TerminalScreenGraphemeCluster(
                    character: character,
                    scalarCount: count
                )
            }
            scalarOffset += count
        }
        return starts
    }
}
