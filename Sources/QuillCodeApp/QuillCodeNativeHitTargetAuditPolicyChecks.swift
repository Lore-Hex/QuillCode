struct QuillCodeNativeSurfacePolicyCoverage {
    let missingRequiredKinds: [String]
    let missingRequiredActions: [String]
    let missingRequiredFocusTargets: [String]
    let unexpectedKinds: [String]
    let unexpectedActions: [String]
    let unexpectedFocusTargets: [String]
}

private protocol SurfacePolicyValue: Hashable, RawRepresentable where RawValue == String {}

extension QuillCodeNativeHitTargetKind: SurfacePolicyValue {}
extension QuillCodeNativeHitTargetAction: SurfacePolicyValue {}
extension QuillCodeNativeFocusTarget: SurfacePolicyValue {}

extension QuillCodeNativeHitTargetAudit {
    typealias PolicyList = [QuillCodeNativeSurfaceTargetPolicy]
    typealias ContractList = [QuillCodeNativeHitTargetContract]
    private typealias PolicyValues<Value> = (QuillCodeNativeSurfaceTargetPolicy) -> [Value]
    private typealias Read<Value> = (QuillCodeNativeHitTargetContract) -> Value?

    static func surfacePolicyCoverage(
        policies: PolicyList,
        contracts: ContractList
    ) -> QuillCodeNativeSurfacePolicyCoverage {
        let contractKind: Read<QuillCodeNativeHitTargetKind> = { Optional($0.kind) }
        let contractAction: Read<QuillCodeNativeHitTargetAction> = { Optional($0.action) }
        let contractFocusTarget: Read<QuillCodeNativeFocusTarget> = \.focusTarget

        return QuillCodeNativeSurfacePolicyCoverage(
            missingRequiredKinds: missingRequiredPolicyValues(
                policies: policies,
                contracts: contracts,
                requiredValues: \.requiredKinds,
                read: contractKind
            ),
            missingRequiredActions: missingRequiredPolicyValues(
                policies: policies,
                contracts: contracts,
                requiredValues: \.requiredActions,
                read: contractAction
            ),
            missingRequiredFocusTargets: missingRequiredPolicyValues(
                policies: policies,
                contracts: contracts,
                requiredValues: \.requiredFocusTargets,
                read: contractFocusTarget
            ),
            unexpectedKinds: unexpectedPolicyValues(
                policies: policies,
                contracts: contracts,
                allowedValues: \.allowedKinds,
                read: contractKind
            ),
            unexpectedActions: unexpectedPolicyValues(
                policies: policies,
                contracts: contracts,
                allowedValues: \.allowedActions,
                read: contractAction
            ),
            unexpectedFocusTargets: unexpectedPolicyValues(
                policies: policies,
                contracts: contracts,
                allowedValues: \.allowedFocusTargets,
                read: contractFocusTarget
            )
        )
    }

    private static func missingRequiredPolicyValues<Value: SurfacePolicyValue>(
        policies: PolicyList,
        contracts: ContractList,
        requiredValues: PolicyValues<Value>,
        read: Read<Value>
    ) -> [String] {
        let contractsByFamily = Dictionary(grouping: contracts, by: \.family)
        return policies.flatMap { policy in
            missingValues(
                policy: policy,
                coveredValues: Set(contractsByFamily[policy.family, default: []].compactMap(read)),
                requiredValues: requiredValues
            )
        }
        .sorted()
    }

    private static func missingValues<Value: SurfacePolicyValue>(
        policy: QuillCodeNativeSurfaceTargetPolicy,
        coveredValues: Set<Value>,
        requiredValues: PolicyValues<Value>
    ) -> [String] {
        requiredValues(policy).compactMap { value in
            coveredValues.contains(value) ? nil : "\(policy.family.rawValue):\(value.rawValue)"
        }
    }

    private static func unexpectedPolicyValues<Value: SurfacePolicyValue>(
        policies: PolicyList,
        contracts: ContractList,
        allowedValues: PolicyValues<Value>,
        read: Read<Value>
    ) -> [String] {
        let allowedValuesByFamily = Dictionary(
            uniqueKeysWithValues: policies.map { ($0.family, Set(allowedValues($0))) }
        )
        return contracts.compactMap { contract in
            guard let value = read(contract),
                  let familyValues = allowedValuesByFamily[contract.family],
                  !familyValues.contains(value)
            else { return nil }
            return "\(contract.family.rawValue):\(contract.id):\(value.rawValue)"
        }
        .sorted()
    }
}
