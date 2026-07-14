import SwiftUI

struct QuillCodeReviewScopePicker: View {
    var availableScopes: [WorkspaceReviewScope]
    var activeSelection: WorkspaceReviewSelection?
    var onSelection: (WorkspaceReviewSelection) -> Void

    @FocusState private var isReferenceFocused: Bool
    @State private var pendingScope: WorkspaceReviewScope?
    @State private var referenceDraft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Review scope", selection: scopeBinding) {
                ForEach(availableScopes) { scope in
                    Text(scope.title).tag(scope)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .quillCodeSegmentedControlTarget()
            .frame(width: 360, alignment: .leading)
            .accessibilityIdentifier("quillcode-review-scope")

            if let referenceScope {
                referenceEditor(for: referenceScope)
            }
        }
        .onAppear(perform: synchronizeWithActiveSelection)
        .onChange(of: activeSelection) {
            synchronizeWithActiveSelection()
        }
    }

    private var scopeBinding: Binding<WorkspaceReviewScope> {
        Binding(
            get: { pendingScope ?? activeSelection?.scope ?? .unstaged },
            set: { scope in selectScope(scope) }
        )
    }

    private var referenceScope: WorkspaceReviewScope? {
        if let pendingScope, pendingScope.requiresReference {
            return pendingScope
        }
        guard let activeScope = activeSelection?.scope, activeScope.requiresReference else {
            return nil
        }
        return activeScope
    }

    @ViewBuilder
    private func referenceEditor(for scope: WorkspaceReviewScope) -> some View {
        HStack(spacing: QuillCodeMetrics.controlClusterSpacing) {
            Text(scope.referenceLabel ?? "Reference")
                .font(.caption.weight(.semibold))
                .foregroundStyle(QuillCodePalette.muted)

            TextField(scope.referencePlaceholder ?? "Git reference", text: $referenceDraft)
                .textFieldStyle(.plain)
                .font(.callout.monospaced())
                .padding(.horizontal, 10)
                .quillCodeTextEntryTarget(alignment: .center, radius: 9)
                .background(QuillCodePalette.background.opacity(0.72))
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .focused($isReferenceFocused)
                .onSubmit(compareReference)
                .accessibilityLabel(scope.referenceLabel ?? "Git reference")
                .accessibilityIdentifier("quillcode-review-reference")

            Button("Compare", action: compareReference)
                .font(.caption.weight(.semibold))
                .quillCodeFormActionTarget(minWidth: 82)
                .foregroundStyle(canCompare ? Color.white : QuillCodePalette.muted)
                .background(canCompare ? QuillCodePalette.blue : QuillCodePalette.selection.opacity(0.45))
                .clipShape(Capsule())
                .buttonStyle(QuillCodePressableButtonStyle())
                .disabled(!canCompare)
                .accessibilityIdentifier("quillcode-review-compare")
        }
        .frame(maxWidth: 520, alignment: .leading)
    }

    private var canCompare: Bool {
        !referenceDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func selectScope(_ scope: WorkspaceReviewScope) {
        guard scope.requiresReference else {
            pendingScope = nil
            referenceDraft = ""
            if let selection = WorkspaceReviewSelection(scope: scope) {
                onSelection(selection)
            }
            return
        }

        pendingScope = scope
        if activeSelection?.scope == scope {
            referenceDraft = activeSelection?.reference ?? ""
        } else {
            referenceDraft = scope == .commit ? "HEAD" : ""
        }
        Task { @MainActor in
            isReferenceFocused = true
        }
    }

    private func compareReference() {
        guard let scope = referenceScope,
              let selection = WorkspaceReviewSelection(scope: scope, reference: referenceDraft)
        else {
            return
        }
        pendingScope = nil
        isReferenceFocused = false
        onSelection(selection)
    }

    private func synchronizeWithActiveSelection() {
        guard pendingScope == nil else { return }
        referenceDraft = activeSelection?.reference ?? ""
    }
}
