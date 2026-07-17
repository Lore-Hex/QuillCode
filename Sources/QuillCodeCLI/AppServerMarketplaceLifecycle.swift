import Foundation
import QuillCodePersistence
import QuillCodeTools

extension AppServerSession {
    func addMarketplace(_ raw: CLIJSONValue) async throws -> CLIJSONValue {
        let params = try AppServerParams(raw)
        let source = try params.requiredString("source")
        let refName = try params.optionalString("refName")
        let sparsePaths = try marketplaceStringArray(params, key: "sparsePaths") ?? []
        let materializer = marketplaceMaterializer()
        let registry = MarketplaceRegistryStore(fileURL: paths.configFile)

        do {
            let prepared = try await marketplaceIO {
                try materializer.prepare(source: source, refName: refName, sparsePaths: sparsePaths)
            }
            return try await addPreparedMarketplace(
                prepared,
                registry: registry,
                materializer: materializer
            )
        } catch let error as AppServerRPCError {
            throw error
        } catch {
            throw Self.marketplaceError(error)
        }
    }

    private func addPreparedMarketplace(
        _ prepared: CodexPreparedMarketplace,
        registry: MarketplaceRegistryStore,
        materializer: CodexMarketplaceMaterializer
    ) async throws -> CLIJSONValue {
        do {
            let registrations = try registry.registrations()
            if let sourceMatch = registrations.first(where: {
                $0.sourceType.rawValue == prepared.sourceType.rawValue
                    && $0.source == prepared.source
                    && $0.name != prepared.name
            }) {
                throw AppServerRPCError.invalidRequest(
                    "marketplace source is already configured as `\(sourceMatch.name)`; "
                        + "the catalog now reports `\(prepared.name)`"
                )
            }
            if let existing = registrations.first(where: { $0.name == prepared.name }) {
                guard Self.matches(existing, prepared: prepared) else {
                    materializer.discard(prepared)
                    throw AppServerRPCError.invalidRequest(
                        "marketplace `\(prepared.name)` is already configured from another source"
                    )
                }
                let root = prepared.managed
                    ? try await marketplaceIO {
                        try materializer.validateInstalledMarketplace(named: prepared.name)
                    }
                    : prepared.root
                if !prepared.managed || FileManager.default.fileExists(atPath: root.path) {
                    materializer.discard(prepared)
                    return marketplaceAddResponse(
                        name: prepared.name,
                        installedRoot: root,
                        alreadyAdded: true
                    )
                }
            }

            let activation = try await marketplaceIO {
                try materializer.activate(prepared, replacingExisting: false)
            }
            do {
                try registry.upsert(Self.registration(for: prepared))
            } catch {
                try await rollbackAndRethrow(error) {
                    try materializer.rollback(activation)
                }
            }
            try? await marketplaceIO { try materializer.finalize(activation) }
            await marketplaceCatalogDidChange()
            return marketplaceAddResponse(
                name: prepared.name,
                installedRoot: activation.installedRoot,
                alreadyAdded: false
            )
        } catch {
            materializer.discard(prepared)
            throw error
        }
    }

    func removeMarketplace(_ raw: CLIJSONValue) async throws -> CLIJSONValue {
        let params = try AppServerParams(raw)
        let name = try params.requiredString("marketplaceName")
        let registry = MarketplaceRegistryStore(fileURL: paths.configFile)
        let materializer = marketplaceMaterializer()

        do {
            let registration = try registry.registration(named: name)
            let removal = try await marketplaceIO { try materializer.stageRemoval(named: name) }
            guard registration != nil || removal != nil else {
                throw AppServerRPCError.invalidRequest(
                    "marketplace `\(name)` is not configured or installed"
                )
            }
            do {
                _ = try registry.remove(named: name)
            } catch {
                if let removal {
                    try await rollbackAndRethrow(error) {
                        try materializer.rollback(removal)
                    }
                }
                throw error
            }
            if let removal { try? await marketplaceIO { try materializer.finalize(removal) } }
            await marketplaceCatalogDidChange()
            return .object([
                "marketplaceName": .string(registration?.name ?? name.lowercased()),
                "installedRoot": removal.map { .string($0.installedRoot.path) } ?? .null
            ])
        } catch let error as AppServerRPCError {
            throw error
        } catch {
            throw Self.marketplaceError(error)
        }
    }

    func upgradeMarketplaces(_ raw: CLIJSONValue) async throws -> CLIJSONValue {
        let params = try AppServerParams(raw)
        let requestedName = try params.optionalString("marketplaceName")
        let registry = MarketplaceRegistryStore(fileURL: paths.configFile)
        let registrations: [MarketplaceRegistration]
        do {
            registrations = try registry.registrations()
        } catch {
            throw Self.marketplaceError(error)
        }

        let selected: [MarketplaceRegistration]
        if let requestedName {
            guard let registration = registrations.first(where: {
                $0.name == requestedName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            }), registration.sourceType == .git else {
                throw AppServerRPCError.invalidRequest(
                    "marketplace `\(requestedName)` is not configured as a Git marketplace"
                )
            }
            selected = [registration]
        } else {
            selected = registrations.filter { $0.sourceType == .git }
        }

        let materializer = marketplaceMaterializer()
        var upgradedRoots: [CLIJSONValue] = []
        var errors: [CLIJSONValue] = []
        for registration in selected {
            do {
                if let root = try await upgradeMarketplace(
                    registration,
                    registry: registry,
                    materializer: materializer
                ) {
                    upgradedRoots.append(.string(root.path))
                }
            } catch {
                errors.append(.object([
                    "marketplaceName": .string(registration.name),
                    "message": .string(Self.boundedMarketplaceError(error))
                ]))
            }
        }
        if !upgradedRoots.isEmpty { await marketplaceCatalogDidChange() }
        return .object([
            "selectedMarketplaces": .array(selected.map { .string($0.name) }),
            "upgradedRoots": .array(upgradedRoots),
            "errors": .array(errors)
        ])
    }

    private func upgradeMarketplace(
        _ registration: MarketplaceRegistration,
        registry: MarketplaceRegistryStore,
        materializer: CodexMarketplaceMaterializer
    ) async throws -> URL? {
        let prepared = try await marketplaceIO {
            try materializer.prepare(
                source: registration.source,
                refName: registration.refName,
                sparsePaths: registration.sparsePaths
            )
        }
        do {
            guard prepared.managed,
                  prepared.name == registration.name,
                  prepared.sourceType == .git
            else {
                throw CodexMarketplaceMaterializationError.invalidMarketplace(
                    "catalog name changed from `\(registration.name)` to `\(prepared.name)`"
                )
            }
            let destination = materializer.installedRoot.appendingPathComponent(
                registration.name,
                isDirectory: true
            )
            if prepared.revision == registration.lastRevision,
               FileManager.default.fileExists(atPath: destination.path) {
                _ = try await marketplaceIO {
                    try materializer.validateInstalledMarketplace(named: registration.name)
                }
                materializer.discard(prepared)
                return nil
            }

            let activation = try await marketplaceIO {
                try materializer.activate(prepared, replacingExisting: true)
            }
            do {
                try registry.upsert(Self.registration(for: prepared))
            } catch {
                try await rollbackAndRethrow(error) {
                    try materializer.rollback(activation)
                }
            }
            try? await marketplaceIO { try materializer.finalize(activation) }
            return activation.installedRoot
        } catch {
            materializer.discard(prepared)
            throw error
        }
    }

    private func marketplaceStringArray(
        _ params: AppServerParams,
        key: String
    ) throws -> [String]? {
        guard let values = try params.optionalArray(key) else { return nil }
        return try values.enumerated().map { index, value in
            guard let string = value.stringValue else {
                throw AppServerRPCError.invalidParams("\(key)[\(index)] must be a string")
            }
            return string
        }
    }

    private func marketplaceMaterializer() -> CodexMarketplaceMaterializer {
        CodexMarketplaceMaterializer(home: paths.home, currentDirectory: currentDirectory)
    }

    private func marketplaceIO<T: Sendable>(
        _ operation: @escaping @Sendable () throws -> T
    ) async throws -> T {
        try await Task.detached(priority: .utility, operation: operation).value
    }

    private func rollbackAndRethrow(
        _ originalError: Error,
        rollback: @escaping @Sendable () throws -> Void
    ) async throws -> Never {
        do {
            try await marketplaceIO(rollback)
        } catch {
            throw AppServerRPCError.internalError(
                "marketplace transaction rollback failed: \(Self.boundedMarketplaceError(error))"
            )
        }
        throw originalError
    }

    private func marketplaceAddResponse(
        name: String,
        installedRoot: URL,
        alreadyAdded: Bool
    ) -> CLIJSONValue {
        .object([
            "marketplaceName": .string(name),
            "installedRoot": .string(installedRoot.path),
            "alreadyAdded": .bool(alreadyAdded)
        ])
    }

    private func marketplaceCatalogDidChange() async {
        cachedSkillSnapshots.removeAll(keepingCapacity: true)
        refreshSkillWatcher()
        await sendNotification("skills/changed", params: .object([:]))
    }

    private static func matches(
        _ registration: MarketplaceRegistration,
        prepared: CodexPreparedMarketplace
    ) -> Bool {
        registration.sourceType.rawValue == prepared.sourceType.rawValue
            && registration.source == prepared.source
            && registration.refName == prepared.refName
            && registration.sparsePaths == prepared.sparsePaths
    }

    private static func registration(
        for prepared: CodexPreparedMarketplace
    ) -> MarketplaceRegistration {
        let sourceType: MarketplaceSourceType = switch prepared.sourceType {
        case .local: .local
        case .git: .git
        }
        return MarketplaceRegistration(
            name: prepared.name,
            sourceType: sourceType,
            source: prepared.source,
            refName: prepared.refName,
            sparsePaths: prepared.sparsePaths,
            lastUpdated: ISO8601DateFormatter().string(from: Date()),
            lastRevision: prepared.revision
        )
    }

    private static func marketplaceError(_ error: Error) -> AppServerRPCError {
        AppServerRPCError.invalidRequest(boundedMarketplaceError(error))
    }

    private static func boundedMarketplaceError(_ error: Error) -> String {
        String(String(describing: error).prefix(2_000))
    }
}
