import Foundation
import QuillCodeCore

@MainActor
extension QuillCodeWorkspaceModel {
    public func toggleSidebar() {
        chrome.isSidebarVisible.toggle()
    }

    public func toggleExtensions() {
        extensions.isVisible.toggle()
    }

    public func toggleMemories() {
        memories.isVisible.toggle()
    }

    public func toggleActivity() {
        activity.isVisible.toggle()
    }

    public func toggleAutomations() {
        automations.isVisible.toggle()
    }

    public func toggleActivitySection(_ section: ActivitySectionKind) {
        activity.isVisible = true
        if activity.collapsedSectionIDs.contains(section) {
            activity.collapsedSectionIDs.remove(section)
        } else {
            activity.collapsedSectionIDs.insert(section)
        }
    }

    public func dismissInstructionDiagnostic(id: String) -> Bool {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              activeInstructionDiagnosticIDs.contains(trimmed)
        else { return false }
        activity.isVisible = true
        activity.dismissedInstructionDiagnosticIDs.insert(trimmed)
        if let projectIndex = activeInstructionResolutionProjectIndex {
            root.projects[projectIndex].dismissInstructionDiagnostic(id: trimmed)
            saveProjects()
        }
        return true
    }
}
