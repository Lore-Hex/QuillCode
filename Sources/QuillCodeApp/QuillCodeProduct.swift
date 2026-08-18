import Foundation
import QuillCodeCore
import QuillCodePersistence

public enum QuillCodeProduct {
    public static let distribution = QuillCodeDistribution.current
    public static let displayName = distribution.displayName
    public static let brandByline = distribution.brandByline
    public static let fullBrandName = distribution.fullBrandName
    public static let bundleIdentifier = distribution.bundleIdentifier
    public static let defaultPaths = QuillCodePaths(
        liveHomeDirectoryName: distribution.applicationHomeDirectoryName,
        secretStorageService: distribution.secretStorageService
    )
}
