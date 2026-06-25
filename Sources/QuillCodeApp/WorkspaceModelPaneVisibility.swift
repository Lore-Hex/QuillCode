import Foundation
import QuillCodeCore

@MainActor
extension QuillCodeWorkspaceModel {
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
}
