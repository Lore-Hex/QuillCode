import SwiftUI

extension QuillCodeBrowserPaneView {
    var header: some View {
        HStack(spacing: QuillCodeMetrics.controlClusterSpacing) {
            Image(systemName: "globe")
                .foregroundStyle(QuillCodePalette.blue)
            Text("Browser")
                .font(.headline)
            Text(browser.statusLabel)
                .font(.caption)
                .foregroundStyle(QuillCodePalette.muted)
            Spacer()
        }
    }

    var tabStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: QuillCodeMetrics.controlClusterSpacing) {
                ForEach(browser.tabs) { tab in
                    browserTabButton(tab)
                }

                browserNavigationButton(systemName: "plus", label: "New browser tab", isEnabled: true) {
                    onCommand("browser-tab-new")
                }

                browserNavigationButton(
                    systemName: "xmark",
                    label: "Close browser tab",
                    isEnabled: browser.canCloseActiveTab
                ) {
                    onCommand("browser-tab-close:\(browser.activeTabID.uuidString)")
                }
            }
        }
    }

    var navigationBar: some View {
        ViewThatFits(in: .horizontal) {
            horizontalNavigationBar
            compactNavigationBar
        }
    }

    private var horizontalNavigationBar: some View {
        HStack(spacing: QuillCodeMetrics.controlClusterSpacing) {
            browserNavigationControls
            browserAddressControls
        }
    }

    private var compactNavigationBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            browserNavigationControls
            browserAddressControls
        }
    }

    private var browserNavigationControls: some View {
        HStack(spacing: QuillCodeMetrics.controlClusterSpacing) {
            browserNavigationButton(
                systemName: "chevron.left",
                label: "Back",
                isEnabled: browser.canGoBack
            ) {
                onCommand("browser-back")
            }
            browserNavigationButton(
                systemName: "chevron.right",
                label: "Forward",
                isEnabled: browser.canGoForward
            ) {
                onCommand("browser-forward")
            }
            browserNavigationButton(
                systemName: "arrow.clockwise",
                label: "Reload",
                isEnabled: browser.canReload
            ) {
                onCommand("browser-reload")
            }
            if let onOpenSession {
                Button("Session", action: onOpenSession)
                    .buttonStyle(QuillCodePressableButtonStyle())
                    .quillCodeTextButtonTarget(minWidth: 84)
                    .disabled(!browser.canOpen && browser.currentURL == nil)
                    .help("Open a visible browser session using QuillCode's persistent browser profile.")
                    .accessibilityIdentifier("quillcode-browser-session")
            }
        }
    }

    private var browserAddressControls: some View {
        HStack(spacing: QuillCodeMetrics.controlClusterSpacing) {
            TextField("localhost:3000, docs/page.html, or https://example.com", text: $addressDraft)
                .textFieldStyle(.roundedBorder)
                .onSubmit(onOpen)
                .quillCodeTextEntryTarget()
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("quillcode-browser-address")
            Button("Open", action: onOpen)
                .buttonStyle(QuillCodePressableButtonStyle())
                .quillCodeTextButtonTarget()
                .disabled(addressDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("quillcode-browser-action")
        }
    }

    private func browserTabButton(_ tab: BrowserTabSurface) -> some View {
        Button {
            onCommand(tab.selectCommandID)
        } label: {
            HStack(spacing: QuillCodeMetrics.denseControlClusterSpacing) {
                Text(tab.title)
                    .font(.caption.weight(tab.isActive ? .semibold : .regular))
                    .lineLimit(1)
                if let urlLabel = tab.urlLabel, tab.isActive {
                    Text(urlLabel)
                        .font(.caption2)
                        .foregroundStyle(QuillCodePalette.muted)
                        .lineLimit(1)
                }
            }
            .quillCodeCapsuleButtonTarget(minWidth: 112)
        }
        .buttonStyle(QuillCodePressableButtonStyle())
        .foregroundStyle(tab.isActive ? QuillCodePalette.text : QuillCodePalette.muted)
        .background(tab.isActive ? QuillCodePalette.selection.opacity(0.42) : QuillCodePalette.panel.opacity(0.8))
        .clipShape(Capsule())
        .accessibilityLabel(tab.isActive ? "Current browser tab \(tab.title)" : "Switch to browser tab \(tab.title)")
    }

    func browserNavigationButton(
        systemName: String,
        label: String,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .quillCodeIconButtonTarget()
                .foregroundStyle(isEnabled ? QuillCodePalette.blue : QuillCodePalette.muted.opacity(0.55))
                .background(QuillCodePalette.selection.opacity(isEnabled ? 0.34 : 0.16))
                .clipShape(RoundedRectangle(cornerRadius: QuillCodeMetrics.iconControlRadius, style: .continuous))
        }
        .buttonStyle(QuillCodePressableButtonStyle())
        .disabled(!isEnabled)
        .accessibilityLabel(label)
    }
}
