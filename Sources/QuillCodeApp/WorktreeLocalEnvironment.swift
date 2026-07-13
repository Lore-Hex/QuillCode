import Foundation
import QuillCodeCore

struct WorktreeLocalEnvironment: Equatable, Sendable, Identifiable {
    static let maxCount = 16
    static let maxIDLength = 64
    static let maxTitleLength = 80
    static let maxDescriptionLength = 240

    var id: String
    var title: String
    var description: String?
    var setup: WorktreeSetupConfiguration

    init?(
        id: String,
        title: String? = nil,
        description: String? = nil,
        scriptPath: String? = nil,
        macOSScriptPath: String? = nil,
        linuxScriptPath: String? = nil
    ) {
        guard let normalizedID = Self.normalizedID(id) else { return nil }
        self.id = normalizedID
        self.title = Self.normalizedText(title, maxLength: Self.maxTitleLength)
            ?? Self.displayTitle(for: normalizedID)
        self.description = Self.normalizedText(description, maxLength: Self.maxDescriptionLength)

        let directory = ".quillcode/environments/\(normalizedID)"
        let defaultScript = "\(directory)/setup.sh"
        let defaultMacOSScript = "\(directory)/setup.macos.sh"
        let defaultLinuxScript = "\(directory)/setup.linux.sh"
        self.setup = WorktreeSetupConfiguration(
            scriptPath: scriptPath ?? defaultScript,
            macOSScriptPath: macOSScriptPath ?? defaultMacOSScript,
            linuxScriptPath: linuxScriptPath ?? defaultLinuxScript,
            isExplicitlyConfigured: true
        )
    }

    static func normalizedID(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.count <= maxIDLength,
              trimmed.unicodeScalars.allSatisfy({ scalar in
                  CharacterSet.alphanumerics.contains(scalar) || scalar == "-" || scalar == "_"
              })
        else {
            return nil
        }
        return trimmed.lowercased()
    }

    private static func normalizedText(_ value: String?, maxLength: Int) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty,
              trimmed.count <= maxLength,
              trimmed.rangeOfCharacter(from: .newlines) == nil,
              !trimmed.contains("\0")
        else {
            return nil
        }
        return trimmed
    }

    private static func displayTitle(for id: String) -> String {
        id.split(whereSeparator: { $0 == "-" || $0 == "_" })
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }
}

public struct WorkspaceWorktreeEnvironmentOption: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var title: String
    public var description: String?
    public var isDefault: Bool

    public init(id: String, title: String, description: String? = nil, isDefault: Bool = false) {
        self.id = id
        self.title = title
        self.description = description
        self.isDefault = isDefault
    }
}

public struct WorkspaceWorktreeEnvironmentSurface: Codable, Sendable, Hashable {
    public var options: [WorkspaceWorktreeEnvironmentOption]
    public var automaticDetail: String

    public init(
        options: [WorkspaceWorktreeEnvironmentOption] = [],
        automaticDetail: String = "Run the project's default setup when available."
    ) {
        self.options = options
        self.automaticDetail = automaticDetail
    }
}

public struct WorkspaceNewWorktreeThreadRequest: Sendable, Hashable {
    public var name: String?
    public var setupSelection: WorktreeSetupSelection

    public init(name: String? = nil, setupSelection: WorktreeSetupSelection = .automatic) {
        let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.name = trimmedName?.isEmpty == false ? trimmedName : nil
        self.setupSelection = setupSelection
    }
}

extension WorkspaceProjectConfiguration {
    var worktreeEnvironmentSurface: WorkspaceWorktreeEnvironmentSurface {
        let defaultEnvironment = defaultLocalEnvironmentID.flatMap { defaultID in
            localEnvironments.first(where: { $0.id == defaultID })
        }
        return WorkspaceWorktreeEnvironmentSurface(
            options: localEnvironments.map { environment in
                WorkspaceWorktreeEnvironmentOption(
                    id: environment.id,
                    title: environment.title,
                    description: environment.description,
                    isDefault: environment.id == defaultLocalEnvironmentID
                )
            },
            automaticDetail: defaultEnvironment.map {
                "Use the project's default environment, \($0.title)."
            } ?? "Run the project's default setup when available."
        )
    }
}
