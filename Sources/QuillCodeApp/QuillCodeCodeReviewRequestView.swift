import SwiftUI
import QuillCodeCore

struct QuillCodeCodeReviewRequestView: View {
    @Binding var request: WorkspaceCodeReviewRequest
    var onCancel: () -> Void
    var onRun: () -> Void

    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case reference
        case instructions
    }

    var body: some View {
        QuillCodeWorktreeDialogFrame(
            title: "Review changes",
            subtitle: "Run a dedicated read-only reviewer and surface prioritized findings inline.",
            systemImage: "checklist",
            iconColor: QuillCodePalette.green
        ) {
            VStack(alignment: .leading, spacing: 8) {
                QuillCodeDialogSectionTitle("Review scope")
                ForEach(WorkspaceCodeReviewScope.allCases, id: \.self) { scope in
                    scopeButton(scope)
                }
            }

            scopeDetail

            HStack(spacing: 7) {
                Image(systemName: request.delivery == .detached ? "rectangle.stack" : "text.bubble")
                    .accessibilityHidden(true)
                Text(deliveryLabel)
                Text("•")
                Text(modelLabel)
            }
            .font(.caption)
            .foregroundStyle(QuillCodePalette.muted)
            .accessibilityIdentifier("quillcode-code-review-routing")
        } footer: {
            HStack(spacing: QuillCodeMetrics.controlClusterSpacing) {
                if let validationMessage = request.validationMessage {
                    Text(validationMessage)
                        .font(.caption)
                        .foregroundStyle(QuillCodePalette.yellow)
                        .lineLimit(2)
                }
                Spacer(minLength: 12)
                Button("Cancel", action: onCancel)
                    .buttonStyle(QuillCodeActionButtonStyle())
                    .quillCodeFormActionTarget()
                    .accessibilityIdentifier("quillcode-code-review-cancel")
                Button("Start review", action: onRun)
                    .buttonStyle(QuillCodeActionButtonStyle(.primary, minWidth: 112))
                    .quillCodeFormActionTarget(minWidth: 112)
                    .disabled(!request.isValid)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("quillcode-code-review-start")
            }
        }
        .accessibilityIdentifier("quillcode-code-review-dialog")
        .onChange(of: request.scope) { _, scope in
            focusedField = scope.requiresReference
                ? .reference
                : scope.requiresInstructions ? .instructions : nil
        }
    }

    private func scopeButton(_ scope: WorkspaceCodeReviewScope) -> some View {
        let isSelected = request.scope == scope
        return Button {
            request.scope = scope
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? QuillCodePalette.blue : QuillCodePalette.muted)
                    .frame(width: 18, height: 18)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(scope.title)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(QuillCodePalette.text)
                    Text(scopeSubtitle(scope))
                        .font(.caption)
                        .foregroundStyle(QuillCodePalette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? QuillCodePalette.blue.opacity(0.12) : Color.white.opacity(0.035))
            )
        }
        .buttonStyle(QuillCodePressableButtonStyle())
        .quillCodeFullRowButtonTarget(radius: 8)
        .accessibilityIdentifier("quillcode-code-review-scope-\(scope.rawValue)")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }

    @ViewBuilder
    private var scopeDetail: some View {
        if request.scope.requiresReference {
            QuillCodeLabeledTextField(
                title: request.scope == .baseBranch ? "Base branch" : "Commit or SHA",
                placeholder: request.scope == .baseBranch ? "main or origin/main" : "HEAD or commit SHA",
                text: referenceBinding,
                footer: request.scope == .baseBranch
                    ? "Reviews changes from the merge base through HEAD."
                    : "Reviews the patch introduced by exactly this commit.",
                accessibilityIdentifier: "quillcode-code-review-reference",
                onSubmit: runIfPossible
            )
            .focused($focusedField, equals: .reference)
        } else if request.scope.requiresInstructions {
            VStack(alignment: .leading, spacing: 6) {
                Text("Review focus")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(QuillCodePalette.muted)
                TextEditor(text: instructionsBinding)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(minHeight: 84, maxHeight: 120)
                    .background(Color.white.opacity(0.045))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
                    .quillCodeTextEntryTarget()
                    .focused($focusedField, equals: .instructions)
                    .accessibilityIdentifier("quillcode-code-review-instructions")
                Text("Describe correctness, security, performance, or API concerns to prioritize.")
                    .font(.caption)
                    .foregroundStyle(QuillCodePalette.muted)
            }
        }
    }

    private var referenceBinding: Binding<String> {
        Binding(
            get: { request.reference ?? "" },
            set: { request.reference = $0 }
        )
    }

    private var instructionsBinding: Binding<String> {
        Binding(
            get: { request.instructions ?? "" },
            set: { request.instructions = $0 }
        )
    }

    private var deliveryLabel: String {
        request.delivery == .detached ? "New detached task" : "Current task"
    }

    private var modelLabel: String {
        guard let model = request.model else { return "Current model" }
        return TrustedRouterDefaults.displayName(fromModelID: model)
    }

    private func scopeSubtitle(_ scope: WorkspaceCodeReviewScope) -> String {
        switch scope {
        case .uncommitted:
            "Staged, unstaged, and untracked files"
        case .baseBranch:
            "Everything changed from a merge base"
        case .commit:
            "One exact commit"
        case .custom:
            "Uncommitted changes with your review criteria"
        }
    }

    private func runIfPossible() {
        guard request.isValid else { return }
        onRun()
    }
}
