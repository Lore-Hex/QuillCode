actor AppServerRuntimeFeatureStore {
    private var enablement: [String: Bool] = [:]

    func value(for featureName: String) -> Bool? {
        enablement[featureName]
    }

    func merge(_ updates: [String: Bool]) {
        enablement.merge(updates) { _, incoming in incoming }
    }
}
