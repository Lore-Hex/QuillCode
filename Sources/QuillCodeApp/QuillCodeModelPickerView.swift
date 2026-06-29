import SwiftUI

struct QuillCodeModelPickerView: View {
    var topBar: TopBarSurface
    @Binding var isPresented: Bool
    var onSetModel: (String) -> Void
    var onToggleModelFavorite: (String) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var searchText = ""
    @State private var expandedModelID: String?
    @State private var highlightedModelID: String?
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
            isPresented.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "diamond")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(QuillCodePalette.muted)
                Text(topBar.modelLabel)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(QuillCodePalette.muted)
            }
            .foregroundStyle(QuillCodePalette.text)
            .padding(.horizontal, 8)
            .quillCodeTextButtonTarget(minWidth: 56, radius: 8)
        }
        .buttonStyle(QuillCodePressableButtonStyle())
        .help("Choose model")
        .accessibilityLabel("Model, \(topBar.modelLabel)")
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
                highlightedModelID = nil
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
                moveHighlightedModel(by: -1)
            case .down:
                moveHighlightedModel(by: 1)
            default:
                break
            }
        }
        .onChange(of: searchText) { _, _ in
            ensureHighlightedModel(preferredID: highlightedModelID)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Choose Model")
                .font(.headline)
            Text("Search provider, category, model, or state")
                .font(.caption)
                .foregroundStyle(QuillCodePalette.muted)
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
        HStack(spacing: 8) {
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
        VStack(alignment: .leading, spacing: 10) {
            Text("No models match")
                .font(.headline)
            Text("Try a provider, model name, category, or state.")
                .font(.caption)
                .foregroundStyle(QuillCodePalette.muted)
                .fixedSize(horizontal: false, vertical: true)
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
        if let preferredID, filteredModels.contains(where: { $0.id == preferredID }) {
            highlightedModelID = preferredID
            return
        }
        if let highlightedModelID, filteredModels.contains(where: { $0.id == highlightedModelID }) {
            return
        }
        highlightedModelID = filteredModels.first?.id
    }

    private func moveHighlightedModel(by delta: Int) {
        guard !filteredModels.isEmpty else {
            highlightedModelID = nil
            return
        }
        let currentIndex = highlightedModelID.flatMap { id in
            filteredModels.firstIndex { $0.id == id }
        } ?? 0
        let nextIndex = (currentIndex + delta + filteredModels.count) % filteredModels.count
        highlightedModelID = filteredModels[nextIndex].id
    }

    private func selectHighlightedModel() {
        guard let highlighted = highlightedModelID.flatMap({ id in
            filteredModels.first { $0.id == id }
        }) ?? filteredModels.first else { return }
        selectModel(highlighted)
    }

    private func selectModel(_ option: ModelOptionSurface) {
        onSetModel(option.id)
        isPresented = false
    }
}
