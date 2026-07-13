enum WorkspaceSubagentPauseKey {
    static func unique(
        workerName: String,
        existing: [String: WorkspaceSubagentApprovalPause]
    ) -> String {
        guard existing[workerName] != nil else { return workerName }
        var suffix = 2
        var candidate = "\(workerName)#\(suffix)"
        while existing[candidate] != nil {
            suffix += 1
            candidate = "\(workerName)#\(suffix)"
        }
        return candidate
    }
}
