import AppKit
import Foundation
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
        guard controller.surface.topBar.appName == "QuillCode",
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
            QuillCodeDesktopSmokeBackground()
            VStack(alignment: .leading, spacing: 18) {
                header
                summaryRows
                commandSection(title: "Required Commands", commands: chrome.requiredCommandIDs)
                commandSection(title: "Exercised Routes", commands: chrome.exercisedCommandIDs)
                Spacer(minLength: 0)
            }
            .padding(24)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(chrome.appName)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(.white)
            Text(chrome.primaryTitle)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.88))
            Text(chrome.subtitle)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.58))
                .lineLimit(2)
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
            Text(label)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color(red: 0.239, green: 0.788, blue: 0.902))
                .frame(width: 92, alignment: .leading)
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
        .background(Color(red: 0.129, green: 0.129, blue: 0.129))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        }
    }

    private func commandSection(title: String, commands: [String]) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.55))
            ForEach(commands, id: \.self) { command in
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color(red: 0.239, green: 0.788, blue: 0.902))
                        .frame(width: 7, height: 7)
                    Text(command)
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.90))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(14)
        .background(Color(red: 0.110, green: 0.110, blue: 0.110))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct QuillCodeDesktopSmokeBackground: View {
    var body: some View {
        ZStack {
            Color(red: 0.090, green: 0.090, blue: 0.090)
            LinearGradient(
                colors: [
                    Color(red: 0.129, green: 0.129, blue: 0.129).opacity(0.82),
                    Color(red: 0.090, green: 0.090, blue: 0.090).opacity(0.96),
                    Color.black.opacity(0.18)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}
