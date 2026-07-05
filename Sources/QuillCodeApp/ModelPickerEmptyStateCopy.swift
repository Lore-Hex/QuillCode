import Foundation
import QuillCodeCore

struct ModelPickerEmptyStateCopy: Sendable, Hashable {
    var title: String
    var detail: String
    var footnote: String?

    static func copy(
        query: String,
        catalogSource: ModelCatalogSource?,
        catalogStatusDetail: String?
    ) -> ModelPickerEmptyStateCopy {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let queryLabel = normalizedQuery.isEmpty ? "that query" : "\"\(normalizedQuery)\""
        let searchHint = "Try a provider, category, model name, capability, or state."

        switch catalogSource {
        case .bundled:
            return ModelPickerEmptyStateCopy(
                title: "No bundled model matches",
                detail: "The built-in catalog is intentionally small. Sign in or refresh TrustedRouter to search live provider models for \(queryLabel).",
                footnote: catalogStatusDetail
            )
        case .fallbackAfterFailure:
            return ModelPickerEmptyStateCopy(
                title: "No fallback model matches",
                detail: "The last TrustedRouter refresh failed, so QuillCode is searching the bundled fallback catalog for \(queryLabel).",
                footnote: catalogStatusDetail
            )
        case .liveTrustedRouter, .publicTrustedRouter:
            return ModelPickerEmptyStateCopy(
                title: "No TrustedRouter model matches",
                detail: searchHint,
                footnote: catalogStatusDetail
            )
        case nil:
            return ModelPickerEmptyStateCopy(
                title: "No models match",
                detail: searchHint,
                footnote: catalogStatusDetail
            )
        }
    }
}
