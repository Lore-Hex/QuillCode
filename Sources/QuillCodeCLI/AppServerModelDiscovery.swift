import Foundation
import QuillCodeAgent
import QuillCodeCore

extension AppServerSession {
    func listModels(_ raw: CLIJSONValue) async throws -> CLIJSONValue {
        let params = try AppServerParams(raw)
        let includeHidden = try params.optionalBool("includeHidden") ?? false
        let requestedLimit = try params.optionalInt("limit") ?? 50
        guard (1...1_000).contains(requestedLimit) else {
            throw AppServerRPCError.invalidParams("limit must be between 1 and 1000")
        }

        let catalog = await discoveryModelCatalog()
        let defaultModel = TrustedRouterDefaults.normalizedDefaultModelID(
            request.model ?? appConfig.defaultModel
        )
        let models = catalog.models.filter { includeHidden || !Self.isHidden($0) }
        let offset = try Self.decodeModelCursor(try params.optionalString("cursor"))
        let page = Array(models.dropFirst(offset).prefix(requestedLimit))
        let nextOffset = offset + page.count

        return .object([
            "data": .array(page.map { Self.projectedModel($0, defaultModel: defaultModel) }),
            "nextCursor": nextOffset < models.count
                ? .string(Self.encodeModelCursor(nextOffset))
                : .null
        ])
    }

    func modelProviderCapabilities(_ raw: CLIJSONValue) throws -> CLIJSONValue {
        try AppServerDiscoveryParams.requireEmpty(
            raw,
            method: "modelProvider/capabilities/read"
        )
        return .object([
            "namespaceTools": .bool(false),
            "imageGeneration": .bool(false),
            "webSearch": .bool(true)
        ])
    }

    func discoveryModelCatalog() async -> TrustedRouterModelCatalog {
        if let cachedModelCatalog { return cachedModelCatalog }
        let catalog: TrustedRouterModelCatalog
        if request.live {
            let client = TrustedRouterModelCatalogClient(
                apiKey: try? resolvedTrustedRouterAPIKey(),
                baseURL: request.baseURL ?? appConfig.apiBaseURL
            )
            catalog = (try? await client.fetch()) ?? TrustedRouterModelCatalog(
                status: .fallbackAfterFailure("Model discovery was unavailable.")
            )
        } else {
            catalog = TrustedRouterModelCatalog()
        }
        cachedModelCatalog = catalog
        return catalog
    }

    private static func projectedModel(_ value: ModelInfo, defaultModel: String) -> CLIJSONValue {
        let modalities = value.capabilities.inputModalities.compactMap { modality -> String? in
            switch modality.lowercased() {
            case "text": return "text"
            case "image", "images": return "image"
            default: return nil
            }
        }
        let uniqueModalities = Array(Set(modalities)).sorted()
        let description = value.capabilities.summary
            ?? TrustedRouterDefaults.recommendedCapabilitySummaries[value.id]
            ?? "\(value.displayName) via TrustedRouter."
        return .object([
            "id": .string(value.id),
            "model": .string(value.id),
            "upgrade": .null,
            "upgradeInfo": .null,
            "availabilityNux": .null,
            "displayName": .string(value.displayName),
            "description": .string(description),
            "hidden": .bool(isHidden(value)),
            "supportedReasoningEfforts": .array([]),
            "defaultReasoningEffort": .string("medium"),
            "inputModalities": .array((uniqueModalities.isEmpty ? ["text"] : uniqueModalities).map {
                .string($0)
            }),
            "supportsPersonality": .bool(false),
            "additionalSpeedTiers": .array([]),
            "serviceTiers": .array([]),
            "defaultServiceTier": .null,
            "isDefault": .bool(value.id == defaultModel)
        ])
    }

    private static func isHidden(_ model: ModelInfo) -> Bool {
        guard let status = model.capabilities.status?.lowercased() else { return false }
        return ["hidden", "retired", "deprecated"].contains(status)
    }

    private static func encodeModelCursor(_ offset: Int) -> String {
        Data("model-offset:\(offset)".utf8).base64EncodedString()
    }

    private static func decodeModelCursor(_ value: String?) throws -> Int {
        guard let value else { return 0 }
        guard let data = Data(base64Encoded: value),
              let text = String(data: data, encoding: .utf8),
              text.hasPrefix("model-offset:"),
              let offset = Int(text.dropFirst("model-offset:".count)),
              offset >= 0 else {
            throw AppServerRPCError.invalidParams("cursor is invalid")
        }
        return offset
    }
}
