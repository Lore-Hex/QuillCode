import SwiftUI

struct QuillCodeModelPickerView: View {
    var topBar: TopBarSurface
    @Binding var isPresented: Bool
    var onSetModel: (String) -> Void
    var onToggleModelFavorite: (String) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var searchText = ""
    @State private var expandedModelID: String?
    @State private var selection = ModelPickerSelection()
    @FocusState private var isSearchFocused: Bool

    private var filteredCategories: [ModelCategorySurface] {
        topBar.filteredModelCategories(matching: searchText)
    }

    private var filteredModels: [ModelOptionSurface] {
        filteredCategories.flatMap(\.models)
    }

    private var filteredModelCount: Int {
        filteredCategories.reduce(0) { $0 + $1.models.count }
    }

    private var currentModelID: String? {
        topBar.modelCategories
            .flatMap(\.models)
            .first { $0.isSelected }?
            .id
    }

    var body: some View {
        Button {
            guard !topBar.modelIsLocked else { return }
            isPresented.toggle()
        } label: {
            HStack(spacing: QuillCodeMetrics.denseControlClusterSpacing) {
                Image(systemName: topBar.modelIsLocked ? "lock.fill" : "diamond")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(QuillCodePalette.muted)
                Text(topBar.modelLabel)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if !topBar.modelIsLocked {
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(QuillCodePalette.muted)
                }
            }
            .foregroundStyle(QuillCodePalette.text)
            .padding(.horizontal, 8)
            .quillCodeTextButtonTarget(minWidth: 56, radius: 8)
        }
        .buttonStyle(QuillCodePressableButtonStyle())
        .disabled(topBar.modelIsLocked)
        .help(topBar.modelIsLocked ? "Model locked: confidential chats always use the E2E encrypted route" : "Choose model")
        .accessibilityLabel(topBar.modelIsLocked ? "Model locked, \(topBar.modelLabel)" : "Model, \(topBar.modelLabel)")
        .accessibilityIdentifier("quillcode-model-picker-button")
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            popoverBody
        }
        .onChange(of: isPresented) { _, presented in
            if presented {
                expandedModelID = currentModelID
                ensureHighlightedModel(preferredID: currentModelID)
                DispatchQueue.main.async {
                    isSearchFocused = true
                }
            } else {
                searchText = ""
                expandedModelID = nil
                selection.reconcile(with: [])
                isSearchFocused = false
            }
        }
    }

    private var popoverBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            searchField
            resultSummary
            modelList
        }
        .padding(14)
        .frame(width: 400, height: 500)
        .background(QuillCodePalette.panel)
        .onMoveCommand { direction in
            switch direction {
            case .up:
                selection.move(by: -1, in: filteredModels)
            case .down:
                selection.move(by: 1, in: filteredModels)
            default:
                break
            }
        }
        .onExitCommand {
            isPresented = false
        }
        .onChange(of: searchText) { _, _ in
            ensureHighlightedModel(preferredID: highlightedModelID)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Choose Model")
                .font(.headline)
            Text("Search provider, category, model, state, or us-only / eu-only / china-only")
                .font(.caption)
                .foregroundStyle(QuillCodePalette.muted)
            Text(topBar.modelCatalogStatusLabel)
                .font(.caption2.weight(.medium))
                .foregroundStyle(QuillCodePalette.blue)
                .lineLimit(1)
                .help(topBar.modelCatalogStatusDetail ?? topBar.modelCatalogStatusLabel)
            if let healthLabel = topBar.modelProviderHealthLabel {
                Text(healthLabel)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(QuillCodePalette.muted)
                    .lineLimit(1)
                    .help(topBar.modelProviderHealthDetail ?? healthLabel)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var searchField: some View {
        TextField("Search models", text: $searchText)
            .textFieldStyle(.roundedBorder)
            .focused($isSearchFocused)
            .quillCodeTextEntryTarget()
            .accessibilityLabel("Search models")
            .accessibilityIdentifier("quillcode-model-picker-search")
            .onSubmit(selectHighlightedModel)
    }

    @ViewBuilder
    private var modelList: some View {
        if filteredCategories.isEmpty {
            emptyState
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 9) {
                        ForEach(filteredCategories) { category in
                            QuillCodeModelCategorySection(
                                category: category,
                                expandedModelID: $expandedModelID,
                                highlightedModelID: highlightedModelID,
                                reduceMotion: reduceMotion,
                                onSetModel: selectModel,
                                onToggleModelFavorite: onToggleModelFavorite
                            )
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private var resultSummary: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: QuillCodeMetrics.controlClusterSpacing) {
                Text(resultSummaryText)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(QuillCodePalette.muted)
                    .lineLimit(1)

                Spacer(minLength: 8)

                if !searchText.isEmpty {
                    Button("Clear") {
                        clearSearch()
                    }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(QuillCodePressableButtonStyle())
                    .foregroundStyle(QuillCodePalette.blue)
                    .quillCodeTextButtonTarget(minWidth: 56)
                    .help("Clear model search")
                }
            }
            if let scopeSummary = topBar.filteredModelScopeSummary(matching: searchText), !filteredCategories.isEmpty {
                Text(scopeSummary)
                    .font(.caption2)
                    .foregroundStyle(QuillCodePalette.muted.opacity(0.86))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var resultSummaryText: String {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let modelNoun = filteredModelCount == 1 ? "model" : "models"
        if query.isEmpty {
            return "\(filteredModelCount) \(modelNoun) available"
        }
        return "\(filteredModelCount) \(modelNoun) for \"\(query)\""
    }

    private var emptyState: some View {
        let copy = ModelPickerEmptyStateCopy.copy(
            query: searchText,
            catalogSource: topBar.modelCatalogSource,
            catalogStatusDetail: topBar.modelCatalogStatusDetail
        )

        return VStack(alignment: .leading, spacing: 10) {
            Text(copy.title)
                .font(.headline)
            Text(copy.detail)
                .font(.caption)
                .foregroundStyle(QuillCodePalette.muted)
                .fixedSize(horizontal: false, vertical: true)
            if let footnote = copy.footnote {
                Text(footnote)
                    .font(.caption2)
                    .foregroundStyle(QuillCodePalette.muted.opacity(0.86))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !searchText.isEmpty {
                Button("Clear search") {
                    clearSearch()
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(QuillCodePressableButtonStyle())
                .foregroundStyle(QuillCodePalette.blue)
                .quillCodeTextButtonTarget(minWidth: 92, alignment: .leading)
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(QuillCodePalette.background.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func clearSearch() {
        searchText = ""
        ensureHighlightedModel(preferredID: currentModelID)
        DispatchQueue.main.async {
            isSearchFocused = true
        }
    }

    private func ensureHighlightedModel(preferredID: String?) {
        selection.reconcile(with: filteredModels, preferredID: preferredID)
    }

    private func selectHighlightedModel() {
        guard let highlighted = selection.selectedModel(in: filteredModels) else { return }
        selectModel(highlighted)
    }

    private var highlightedModelID: String? {
        selection.highlightedModelID
    }

    private func selectModel(_ option: ModelOptionSurface) {
        onSetModel(option.id)
        isPresented = false
    }
}
