import AppKit
import Foundation
import QuillCodeApp
import SwiftUI

struct QuillCodeDesktopChromeSmokeReport {
    var appName: String
    var primaryTitle: String
    var subtitle: String
    var modelLabel: String
    var modeLabel: String
    var computerUseLabel: String
    var requiredCommandIDs: [String]
    var exercisedCommandIDs: [String]

    var dictionary: [String: Any] {
        [
            "appName": appName,
            "primaryTitle": primaryTitle,
            "subtitle": subtitle,
            "modelLabel": modelLabel,
            "modeLabel": modeLabel,
            "computerUseLabel": computerUseLabel,
            "requiredCommandIDs": requiredCommandIDs,
            "exercisedCommandIDs": exercisedCommandIDs
        ]
    }
}

@MainActor
enum QuillCodeDesktopChromeSmoke {
    static func verify(controller: QuillCodeDesktopController) throws -> QuillCodeDesktopChromeSmokeReport {
        let requiredCommandIDs = [
            "add-project",
            "new-chat",
            "command-palette",
            "keyboard-shortcuts",
            "settings",
            "toggle-terminal",
            "toggle-browser",
            "stop-all",
            "disconnect-all"
        ]
        let commandIDs = Set(controller.surface.commands.map(\.id))
        for commandID in requiredCommandIDs where !commandIDs.contains(commandID) {
            throw QuillCodeDesktopSmokeFailure.chromeCommandMissing(commandID)
        }
        guard controller.surface.topBar.appName == QuillCodeProduct.displayName,
              !controller.surface.topBar.primaryTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !controller.surface.topBar.modelLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !controller.surface.topBar.modeLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw QuillCodeDesktopSmokeFailure.chromeSurfaceIncomplete
        }

        try run("command-palette", controller: controller)
        guard controller.isCommandPalettePresented else {
            throw QuillCodeDesktopSmokeFailure.chromeCommandDidNotRoute("command-palette")
        }
        controller.isCommandPalettePresented = false

        try run("keyboard-shortcuts", controller: controller)
        guard controller.isKeyboardShortcutsPresented else {
            throw QuillCodeDesktopSmokeFailure.chromeCommandDidNotRoute("keyboard-shortcuts")
        }
        controller.isKeyboardShortcutsPresented = false

        try run("settings", controller: controller)
        guard controller.isSettingsPresented else {
            throw QuillCodeDesktopSmokeFailure.chromeCommandDidNotRoute("settings")
        }
        controller.isSettingsPresented = false

        try assertToggleRoute(
            "toggle-terminal",
            controller: controller,
            currentValue: { $0.surface.terminal.isVisible }
        )
        try assertToggleRoute(
            "toggle-browser",
            controller: controller,
            currentValue: { $0.surface.browser.isVisible }
        )

        return QuillCodeDesktopChromeSmokeReport(
            appName: controller.surface.topBar.appName,
            primaryTitle: controller.surface.topBar.primaryTitle,
            subtitle: controller.surface.topBar.subtitle,
            modelLabel: controller.surface.topBar.modelLabel,
            modeLabel: controller.surface.topBar.modeLabel,
            computerUseLabel: controller.surface.topBar.computerUseLabel,
            requiredCommandIDs: requiredCommandIDs,
            exercisedCommandIDs: [
                "command-palette",
                "keyboard-shortcuts",
                "settings",
                "toggle-terminal",
                "toggle-browser"
            ]
        )
    }

    static func render(_ chrome: QuillCodeDesktopChromeSmokeReport, to renderURL: URL) throws -> CGImage {
        let view = QuillCodeDesktopChromeSmokePanel(chrome: chrome)
            .frame(width: 420, height: 760, alignment: .topLeading)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        renderer.isOpaque = true
        renderer.proposedSize = ProposedViewSize(width: 420, height: 760)

        guard let image = renderer.cgImage else {
            throw QuillCodeDesktopSmokeFailure.renderFailed
        }

        let rep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw QuillCodeDesktopSmokeFailure.pngEncodingFailed
        }
        try FileManager.default.createDirectory(
            at: renderURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: renderURL, options: .atomic)
        return image
    }

    private static func assertToggleRoute(
        _ commandID: String,
        controller: QuillCodeDesktopController,
        currentValue: (QuillCodeDesktopController) -> Bool
    ) throws {
        let initialValue = currentValue(controller)
        try run(commandID, controller: controller)
        guard currentValue(controller) != initialValue else {
            throw QuillCodeDesktopSmokeFailure.chromeCommandDidNotRoute(commandID)
        }
        try run(commandID, controller: controller)
        guard currentValue(controller) == initialValue else {
            throw QuillCodeDesktopSmokeFailure.chromeCommandDidNotRoute(commandID)
        }
    }

    private static func run(
        _ commandID: String,
        controller: QuillCodeDesktopController
    ) throws {
        guard let command = controller.surface.commands.first(where: { $0.id == commandID }) else {
            throw QuillCodeDesktopSmokeFailure.chromeCommandMissing(commandID)
        }
        controller.runCommand(command)
    }
}

private struct QuillCodeDesktopChromeSmokePanel: View {
    var chrome: QuillCodeDesktopChromeSmokeReport

    var body: some View {
        ZStack {
            CharterSmokePalette.page
            VStack(alignment: .leading, spacing: 20) {
                header
                summaryRows
                commandSection(title: "Required commands", commands: chrome.requiredCommandIDs)
                commandSection(title: "Exercised routes", commands: chrome.exercisedCommandIDs)
                Spacer(minLength: 0)
            }
            .padding(24)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(chrome.appName)
                .font(.custom("Iowan Old Style", size: 30).weight(.semibold))
                .foregroundStyle(CharterSmokePalette.ivory)
            Text(chrome.primaryTitle)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(CharterSmokePalette.ivoryDim)
            Text(chrome.subtitle)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(CharterSmokePalette.muted)
                .lineLimit(2)
            Rectangle()
                .fill(CharterSmokePalette.sage)
                .frame(width: 44, height: 2)
                .padding(.top, 4)
        }
    }

    private var summaryRows: some View {
        VStack(alignment: .leading, spacing: 10) {
            chip(label: "Model", value: chrome.modelLabel)
            chip(label: "Mode", value: chrome.modeLabel)
            chip(label: "Computer Use", value: chrome.computerUseLabel)
        }
    }

    private func chip(label: String, value: String) -> some View {
        HStack(spacing: 10) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(CharterSmokePalette.muted)
                .frame(width: 92, alignment: .leading)
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(CharterSmokePalette.ivory)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
        .background(CharterSmokePalette.raised)
        .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .stroke(CharterSmokePalette.line, lineWidth: 1)
        }
    }

    private func commandSection(title: String, commands: [String]) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(CharterSmokePalette.muted)
            ForEach(commands, id: \.self) { command in
                HStack(spacing: 8) {
                    Circle()
                        .fill(CharterSmokePalette.sage)
                        .frame(width: 6, height: 6)
                    Text(command)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(CharterSmokePalette.ivoryDim)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(14)
        .background(CharterSmokePalette.card)
        .overlay {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .stroke(CharterSmokePalette.line, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}

private enum CharterSmokePalette {
    static let page = Color(red: 0.039, green: 0.055, blue: 0.043)
    static let card = Color(red: 0.051, green: 0.071, blue: 0.055)
    static let raised = Color(red: 0.071, green: 0.094, blue: 0.075)
    static let line = Color(red: 0.165, green: 0.188, blue: 0.165)
    static let ivory = Color(red: 0.929, green: 0.910, blue: 0.859)
    static let ivoryDim = Color(red: 0.839, green: 0.851, blue: 0.800)
    static let muted = Color(red: 0.514, green: 0.561, blue: 0.502)
    static let sage = Color(red: 0.663, green: 0.804, blue: 0.725)
}
