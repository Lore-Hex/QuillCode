public enum HostOperatingSystem: String, Sendable, Hashable {
    case macOS
    case linux
    case other

    public static var current: HostOperatingSystem {
        #if os(macOS)
        return .macOS
        #elseif os(Linux)
        return .linux
        #else
        return .other
        #endif
    }
}
