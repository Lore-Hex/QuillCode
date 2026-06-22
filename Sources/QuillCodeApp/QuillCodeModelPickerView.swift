import SwiftUI
import QuillCodeCore

struct QuillCodeModelPickerView: View {
    var topBar: TopBarSurface
    @Binding var isPresented: Bool
    var onSetMode: (AgentMode) -> Void
    var onSetModel: (String) -> Void
    var onToggleModelFavorite: (String) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var searchText = ""
    @State private var expandedModelID: String?
    @FocusState private var isSearchFocused: Bool

    private var filteredCategories: [ModelCategorySurface] {
        topBar.filteredModelCategories(matching: searchText)
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
                Text("\(topBar.modelLabel) · \(topBar.modeLabel)")
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
        .help("Choose model and mode")
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            popoverBody
        }
        .onChange(of: isPresented) { _, presented in
            if presented {
                expandedModelID = currentModelID
                DispatchQueue.main.async {
                    isSearchFocused = true
                }
            } else {
                searchText = ""
                expandedModelID = nil
                isSearchFocused = false
            }
        }
    }

    private var popoverBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            modePicker
            searchField
            modelList
        }
        .padding(14)
        .frame(width: 400, height: 500)
        .background(QuillCodePalette.panel)
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

    private var modePicker: some View {
        Picker("Mode", selection: modeBinding) {
            ForEach(AgentMode.allCases, id: \.rawValue) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .frame(minHeight: QuillCodeMetrics.minimumHitTarget)
    }

    private var searchField: some View {
        TextField("Search models", text: $searchText)
            .textFieldStyle(.roundedBorder)
            .focused($isSearchFocused)
            .frame(minHeight: QuillCodeMetrics.minimumHitTarget)
            .accessibilityLabel("Search models")
    }

    @ViewBuilder
    private var modelList: some View {
        if filteredCategories.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 9) {
                    ForEach(filteredCategories) { category in
                        QuillCodeModelCategorySection(
                            category: category,
                            expandedModelID: $expandedModelID,
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

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No models match")
                .font(.headline)
            Text("Try a provider, model name, category, or state.")
                .font(.caption)
                .foregroundStyle(QuillCodePalette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(QuillCodePalette.background.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var modeBinding: Binding<AgentMode> {
        Binding(
            get: {
                AgentMode.allCases.first { $0.title == topBar.modeLabel } ?? .auto
            },
            set: { mode in
                onSetMode(mode)
            }
        )
    }

    private func selectModel(_ option: ModelOptionSurface) {
        onSetModel(option.id)
        isPresented = false
    }
}

private struct QuillCodeModelCategorySection: View {
    var category: ModelCategorySurface
    @Binding var expandedModelID: String?
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
        .background(option.isSelected ? QuillCodePalette.blue.opacity(0.045) : Color.clear)
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(option.isSelected ? QuillCodePalette.blue.opacity(0.16) : Color.clear, lineWidth: 1)
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
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
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
