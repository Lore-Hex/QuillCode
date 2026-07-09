import Foundation

struct ModelPickerSelection: Equatable {
    private(set) var highlightedModelID: String?

    mutating func select(_ model: ModelOptionSurface) {
        highlightedModelID = model.id
    }

    mutating func reconcile(with models: [ModelOptionSurface], preferredID: String? = nil) {
        guard !models.isEmpty else {
            highlightedModelID = nil
            return
        }

        if let preferredID, models.contains(where: { $0.id == preferredID }) {
            highlightedModelID = preferredID
            return
        }

        if let highlightedModelID, models.contains(where: { $0.id == highlightedModelID }) {
            return
        }

        highlightedModelID = models[0].id
    }

    mutating func move(by delta: Int, in models: [ModelOptionSurface]) {
        guard !models.isEmpty else {
            highlightedModelID = nil
            return
        }

        let currentIndex = highlightedModelID.flatMap { id in
            models.firstIndex { $0.id == id }
        } ?? 0
        let nextIndex = positiveModulo(currentIndex + delta, models.count)
        highlightedModelID = models[nextIndex].id
    }

    func selectedModel(in models: [ModelOptionSurface]) -> ModelOptionSurface? {
        models.first { $0.id == highlightedModelID } ?? models.first
    }

    private func positiveModulo(_ value: Int, _ divisor: Int) -> Int {
        precondition(divisor > 0)
        let remainder = value % divisor
        return remainder >= 0 ? remainder : remainder + divisor
    }
}
