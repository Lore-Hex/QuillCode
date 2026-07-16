struct ManagedRequirementsDecoder {
    let values: [String: ConfigValue]

    func decode() throws -> ManagedRequirements {
        let allowedApprovalPolicies = try optionalArray("allowed_approval_policies")?
            .enumerated()
            .map { try approvalPolicy($0.element, path: "allowed_approval_policies[\($0.offset)]") }
        try requireNonEmpty(allowedApprovalPolicies, path: "allowed_approval_policies")

        let allowedReviewers = try stringArray(
            "allowed_approvals_reviewers",
            allowed: ["user", "auto_review", "guardian_subagent"]
        )
        try requireNonEmpty(allowedReviewers, path: "allowed_approvals_reviewers")

        let allowedSandboxModes = try stringArray(
            "allowed_sandbox_modes",
            allowed: ["read-only", "workspace-write", "danger-full-access", "external-sandbox"]
        )
        if let allowedSandboxModes, !allowedSandboxModes.contains("read-only") {
            throw error(
                "allowed_sandbox_modes",
                "must include `read-only` to allow any permission profile"
            )
        }

        let permissionProfiles = try boolMap("allowed_permission_profiles")
        let defaultPermissions = try optionalString("default_permissions")
        try validatePermissionDefaults(
            allowed: permissionProfiles,
            defaultPermissions: defaultPermissions,
            allowedSandboxModes: allowedSandboxModes
        )

        var webSearchModes = try stringArray(
            "allowed_web_search_modes",
            allowed: ["disabled", "cached", "indexed", "live"]
        )
        if webSearchModes != nil, webSearchModes?.contains("disabled") == false {
            webSearchModes?.append("disabled")
        }

        let windows = try optionalObject("windows")
        let windowsImplementations = try windows.map {
            try stringArray(
                "allowed_sandbox_implementations",
                in: $0,
                pathPrefix: "windows",
                allowed: ["elevated", "unelevated"]
            )
        } ?? nil

        return ManagedRequirements(
            allowedApprovalPolicies: allowedApprovalPolicies,
            allowedApprovalsReviewers: allowedReviewers,
            allowedSandboxModes: allowedSandboxModes?.filter { $0 != "external-sandbox" },
            allowedWindowsSandboxImplementations: windowsImplementations,
            allowedPermissionProfiles: permissionProfiles,
            defaultPermissions: defaultPermissions,
            allowedWebSearchModes: webSearchModes,
            allowManagedHooksOnly: try optionalBool("allow_managed_hooks_only"),
            allowAppshots: try optionalBool("allow_appshots"),
            allowRemoteControl: try optionalBool("allow_remote_control"),
            computerUse: try decodeComputerUse(),
            featureRequirements: try decodeFeatures(),
            hooks: try decodeHooks(),
            enforceResidency: try optionalEnum("enforce_residency", allowed: ["us"]),
            network: try decodeNetwork()
        )
    }

    private func approvalPolicy(_ value: ConfigValue, path: String) throws -> ManagedApprovalPolicy {
        if let name = value.stringValue {
            guard ["untrusted", "on-failure", "on-request", "never"].contains(name) else {
                throw error(path, "contains unsupported approval policy `\(name)`")
            }
            return .named(name)
        }
        guard let object = value.objectValue,
              Set(object.keys) == Set(["granular"]),
              let granular = object["granular"]?.objectValue else {
            throw error(path, "must be a named or granular approval policy")
        }
        let required = ["sandbox_approval", "rules", "mcp_elicitations"]
        let optional = ["skill_approval", "request_permissions"]
        guard Set(granular.keys).isSubset(of: Set(required + optional)) else {
            throw error(path, "granular policy contains unsupported fields")
        }
        let decoded = try required.reduce(into: [String: Bool]()) { result, key in
            guard let value = granular[key]?.boolValue else {
                throw error("\(path).granular.\(key)", "must be a boolean")
            }
            result[key] = value
        }
        for key in optional where granular[key] != nil && granular[key]?.boolValue == nil {
            throw error("\(path).granular.\(key)", "must be a boolean")
        }
        return .granular(ManagedGranularApprovalPolicy(
            sandboxApproval: decoded["sandbox_approval"] ?? false,
            rules: decoded["rules"] ?? false,
            mcpElicitations: decoded["mcp_elicitations"] ?? false,
            skillApproval: granular["skill_approval"]?.boolValue ?? false,
            requestPermissions: granular["request_permissions"]?.boolValue ?? false
        ))
    }

    private func decodeComputerUse() throws -> ManagedComputerUseRequirements? {
        guard let object = try optionalObject("computer_use") else { return nil }
        return ManagedComputerUseRequirements(
            allowLockedComputerUse: try optionalBool(
                "allow_locked_computer_use",
                in: object,
                pathPrefix: "computer_use"
            )
        )
    }

    private func decodeFeatures() throws -> [String: Bool]? {
        let canonical = values["features"]
        let legacy = values["feature_requirements"]
        if canonical != nil, legacy != nil {
            throw error("features", "cannot be combined with `feature_requirements`")
        }
        guard let value = canonical ?? legacy else { return nil }
        guard let object = value.objectValue else {
            throw error("features", "must be a table of booleans")
        }
        return try object.reduce(into: [String: Bool]()) { result, entry in
            guard let enabled = entry.value.boolValue else {
                throw error("features.\(entry.key)", "must be a boolean")
            }
            result[entry.key] = enabled
        }
    }

    private func validatePermissionDefaults(
        allowed: [String: Bool]?,
        defaultPermissions: String?,
        allowedSandboxModes: [String]?
    ) throws {
        guard let allowed else {
            if defaultPermissions != nil {
                throw error(
                    "default_permissions",
                    "requires `allowed_permission_profiles`"
                )
            }
            return
        }
        let effectiveDefault: String?
        if let defaultPermissions {
            effectiveDefault = defaultPermissions
        } else if allowed[":read-only"] == true, allowed[":workspace"] == true {
            effectiveDefault = ":workspace"
        } else {
            effectiveDefault = nil
        }
        guard let effectiveDefault else {
            throw error(
                "default_permissions",
                "must be set unless both `:workspace` and `:read-only` are allowed"
            )
        }
        guard allowed[effectiveDefault] == true else {
            throw error(
                "default_permissions",
                "`\(effectiveDefault)` must be allowed by `allowed_permission_profiles`"
            )
        }
        if let sandboxMode = ManagedRequirements.builtInPermissionProfiles[effectiveDefault],
           let allowedSandboxModes,
           !allowedSandboxModes.contains(sandboxMode) {
            throw error(
                "default_permissions",
                "`\(effectiveDefault)` is disallowed by `allowed_sandbox_modes`"
            )
        }
    }
}
