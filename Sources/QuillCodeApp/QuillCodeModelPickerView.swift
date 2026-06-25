import SwiftUI
import QuillCodeCore

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
            .frame(minHeight: QuillCodeMetrics.minimumHitTarget)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(QuillCodePressableButtonStyle())
        .help("Choose model")
        .accessibilityLabel("Model, \(topBar.modelLabel)")
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
            .frame(minHeight: QuillCodeMetrics.minimumHitTarget)
            .accessibilityLabel("Search models")
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
                .buttonStyle(.plain)
                .foregroundStyle(QuillCodePalette.blue)
                .frame(minHeight: QuillCodeMetrics.minimumHitTarget)
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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
                .frame(minHeight: QuillCodeMetrics.minimumHitTarget)
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

private struct QuillCodeModelCategorySection: View {
    var category: ModelCategorySurface
    @Binding var expandedModelID: String?
    var highlightedModelID: String?
    var reduceMotion: Bool
    var onSetModel: (ModelOptionSurface) -> Void
    var onToggleModelFavorite: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(category.category.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(QuillCodePalette.muted)
                .padding(.horizontal, 10)
            ForEach(category.models) { option in
                QuillCodeModelRow(
                    option: option,
                    isExpanded: expandedModelID == option.id,
                    isHighlighted: highlightedModelID == option.id,
                    reduceMotion: reduceMotion,
                    onSelect: onSetModel,
                    onToggleExpanded: toggleExpanded,
                    onToggleFavorite: onToggleModelFavorite
                )
            }
        }
    }

    private func toggleExpanded(_ option: ModelOptionSurface) {
        quillCodeWithAnimation(.easeOut(duration: 0.16), reduceMotion: reduceMotion) {
            expandedModelID = expandedModelID == option.id ? nil : option.id
        }
    }
}

private struct QuillCodeModelRow: View {
    var option: ModelOptionSurface
    var isExpanded: Bool
    var isHighlighted: Bool
    var reduceMotion: Bool
    var onSelect: (ModelOptionSurface) -> Void
    var onToggleExpanded: (ModelOptionSurface) -> Void
    var onToggleFavorite: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 10) {
                Button {
                    onSelect(option)
                } label: {
                    HStack(spacing: 10) {
                        modelSummary
                        Spacer(minLength: 10)
                        if option.isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(QuillCodePalette.green)
                                .accessibilityLabel("Current model")
                        }
                    }
                    .frame(minHeight: QuillCodeMetrics.minimumHitTarget)
                    .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(QuillCodePressableButtonStyle())
                .help(option.metadataDetails.joined(separator: "\n"))
                .accessibilityHint(option.metadataDetails.joined(separator: ", "))

                HStack(spacing: 6) {
                    modelActionButton(
                        systemImage: isExpanded ? "info.circle.fill" : "info.circle",
                        tint: isExpanded ? QuillCodePalette.blue : QuillCodePalette.muted,
                        title: isExpanded ? "Hide model details" : "Show model details"
                    ) {
                        onToggleExpanded(option)
                    }

                    modelActionButton(
                        systemImage: option.isFavorite ? "star.fill" : "star",
                        tint: option.isFavorite ? QuillCodePalette.yellow : QuillCodePalette.muted,
                        title: option.isFavorite ? "Remove favorite model" : "Favorite model"
                    ) {
                        onToggleFavorite(option.id)
                    }
                }
            }

            if isExpanded {
                QuillCodeModelDetails(option: option)
                    .transition(reduceMotion ? .identity : .opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowBackground)
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(rowStroke, lineWidth: 1)
        }
        .overlay(alignment: .leading) {
            if option.isSelected {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(QuillCodePalette.blue.opacity(0.72))
                    .frame(width: 3)
                    .padding(.vertical, 8)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var modelSummary: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(option.detailTitle)
                .font(.callout.weight(.medium))
                .lineLimit(1)
                .truncationMode(.tail)
            Text(option.metadataSummary)
                .font(.caption)
                .foregroundStyle(QuillCodePalette.muted)
                .lineLimit(1)
                .truncationMode(.middle)
            if !option.badges.isEmpty {
                badgeRow
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
    }

    private var rowBackground: Color {
        if option.isSelected {
            return QuillCodePalette.blue.opacity(isHighlighted ? 0.08 : 0.045)
        }
        return isHighlighted ? Color.white.opacity(0.05) : Color.clear
    }

    private var rowStroke: Color {
        if isHighlighted {
            return QuillCodePalette.blue.opacity(0.42)
        }
        return option.isSelected ? QuillCodePalette.blue.opacity(0.16) : Color.clear
    }

    private var badgeRow: some View {
        HStack(spacing: 5) {
            ForEach(option.badges.prefix(3), id: \.self) { badge in
                Text(badge)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(badgeForeground(for: badge))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(badgeBackground(for: badge))
                    .clipShape(Capsule())
            }
        }
        .lineLimit(1)
    }

    private func badgeForeground(for badge: String) -> Color {
        switch badge {
        case "Current":
            return QuillCodePalette.green
        case "Default", "Recommended":
            return QuillCodePalette.blue
        case "Favorite":
            return QuillCodePalette.yellow
        default:
            return QuillCodePalette.muted
        }
    }

    private func badgeBackground(for badge: String) -> Color {
        badgeForeground(for: badge).opacity(0.12)
    }

    private func modelActionButton(
        systemImage: String,
        tint: Color,
        title: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: QuillCodeMetrics.minimumHitTarget, height: QuillCodeMetrics.minimumHitTarget)
                .contentShape(Circle())
        }
        .buttonStyle(QuillCodePressableButtonStyle())
        .help(title)
        .accessibilityLabel(title)
    }
}

private struct QuillCodeModelDetails: View {
    var option: ModelOptionSurface

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
                .opacity(0.28)

            Text(option.capabilitySummary)
                .font(.caption)
                .foregroundStyle(QuillCodePalette.muted)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 5) {
                ForEach(option.metadataRows) { row in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(row.label)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(QuillCodePalette.muted)
                            .frame(width: 62, alignment: .leading)
                        Text(row.value)
                            .font(.caption2.monospaced())
                            .foregroundStyle(QuillCodePalette.text)
                            .lineLimit(2)
                            .truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .padding(.top, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
