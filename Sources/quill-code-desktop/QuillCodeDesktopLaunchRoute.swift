enum QuillCodeDesktopLaunchRoute: Hashable {
    case updateHelper
    case dailyDriverSeed
    case relocationSmoke
    case updaterSmoke
    case coworkEval
    case composerDraftCrashSmoke
    case agentRunCrashSmoke
    case windowSmoke
    case renderSmoke

    private static let priority: [Self] = [
        .updateHelper,
        .dailyDriverSeed,
        .relocationSmoke,
        .updaterSmoke,
        .coworkEval,
        .composerDraftCrashSmoke,
        .agentRunCrashSmoke,
        .windowSmoke,
        .renderSmoke,
    ]

    static func candidates(arguments: [String]) -> [Self] {
        var present: Set<Self> = []
        for argument in arguments.dropFirst() {
            switch argument {
            case QuillCodeDesktopUpdateHelperRequest.modeArgument:
                present.insert(.updateHelper)
            case "--seed-daily-driver-window-smoke":
                present.insert(.dailyDriverSeed)
            case QuillCodeDesktopRelocationSmokeRequest.modeArgument:
                present.insert(.relocationSmoke)
            case QuillCodeDesktopUpdaterSmokeRequest.modeArgument:
                present.insert(.updaterSmoke)
            case "--cowork-eval":
                present.insert(.coworkEval)
            case "--composer-draft-crash-smoke":
                present.insert(.composerDraftCrashSmoke)
            case "--agent-run-crash-smoke":
                present.insert(.agentRunCrashSmoke)
            case "--native-window-smoke":
                present.insert(.windowSmoke)
            case "--native-render-smoke":
                present.insert(.renderSmoke)
            default:
                continue
            }
        }
        return priority.filter { present.contains($0) }
    }
}
