import Foundation

struct WorkspaceCommandPaletteSelection: Equatable {
    private(set) var selectedCommandID: String?

    mutating func select(_ command: WorkspaceCommandSurface) {
        selectedCommandID = command.isEnabled ? command.id : nil
    }

    mutating func reconcile(with commands: [WorkspaceCommandSurface]) {
        let enabled = enabledCommands(from: commands)
        guard !enabled.isEmpty else {
            selectedCommandID = nil
            return
        }
        if let selectedCommandID,
           enabled.contains(where: { $0.id == selectedCommandID }) {
            return
        }
        selectedCommandID = enabled[0].id
    }

    mutating func move(by delta: Int, in commands: [WorkspaceCommandSurface]) {
        let enabled = enabledCommands(from: commands)
        guard !enabled.isEmpty else {
            selectedCommandID = nil
            return
        }
        let currentIndex = selectedCommandID.flatMap { id in
            enabled.firstIndex(where: { $0.id == id })
        } ?? 0
        let nextIndex = positiveModulo(currentIndex + delta, enabled.count)
        selectedCommandID = enabled[nextIndex].id
    }

    func selectedCommand(in commands: [WorkspaceCommandSurface]) -> WorkspaceCommandSurface? {
        let enabled = enabledCommands(from: commands)
        return enabled.first(where: { $0.id == selectedCommandID }) ?? enabled.first
    }

    private func enabledCommands(from commands: [WorkspaceCommandSurface]) -> [WorkspaceCommandSurface] {
        commands.filter(\.isEnabled)
    }

    private func positiveModulo(_ value: Int, _ divisor: Int) -> Int {
        precondition(divisor > 0)
        let remainder = value % divisor
        return remainder >= 0 ? remainder : remainder + divisor
    }
}
