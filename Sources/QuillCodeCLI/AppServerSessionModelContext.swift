import QuillCodeCore

extension AppServerSession {
    func preservingModelContext(from source: ChatThread, in snapshot: ChatThread) -> ChatThread {
        guard !source.modelContextItems.isEmpty else { return snapshot }
        var merged = snapshot
        let sourceIDs = Set(source.modelContextItems.map(\.id))
        merged.modelContextItems = source.modelContextItems
            + snapshot.modelContextItems.filter { !sourceIDs.contains($0.id) }
        return merged
    }
}
