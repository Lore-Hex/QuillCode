import XCTest

final class ParityAutomationEventSourceGateTests: QuillCodeParityTestCase {
    func testMonitorEventSourceWiringStaysImplemented() throws {
        let eventSourceText = try Self.appSourceText(named: "AutomationEventSource.swift")
        let fileSourceText = try Self.appSourceText(named: "FileAutomationEventSources.swift")
        let lastModifiedText = try Self.appSourceText(named: "URLLastModifiedEventSource.swift")
        let feedSourceText = try Self.appSourceText(named: "URLFeedUpdateEventSource.swift")
        let httpFetcherText = try Self.appSourceText(named: "BoundedHTTPFetcher.swift")
        let resolverText = try Self.appSourceText(named: "AutomationEventSourceResolver.swift")
        let runIntegrationText = try Self.appTestSourceText(
            named: "WorkspaceAutomationRunIntegrationTests.swift"
        )

        Self.assertSource(eventSourceText, containsAll: [
            "public protocol AutomationEventSource",
            "public typealias FileModificationDateProvider",
            "public typealias URLLastModifiedDateProvider",
            "public typealias URLFeedLatestDateProvider"
        ])
        Self.assertSource(eventSourceText, excludes: "public struct FileChangeEventSource")
        Self.assertSource(fileSourceText, containsAll: [
            "public struct FileChangeEventSource",
            "public struct DirectoryChangeEventSource",
            "enum FileModificationDateReader"
        ])
        Self.assertSource(lastModifiedText, containsAll: [
            "public struct URLLastModifiedEventSource",
            "enum HTTPDateParser"
        ])
        Self.assertSource(feedSourceText, containsAll: [
            "public struct URLFeedUpdateEventSource",
            "enum FeedTimestampParser"
        ])
        Self.assertSource(httpFetcherText, containsAll: [
            "enum BoundedHTTPFetcher",
            "AutomationHTTPURLSessionFactory.session"
        ])
        Self.assertSource(resolverText, containsAll: [
            "enum AutomationEventSourceResolver",
            "urlLastModifiedURL",
            "urlFeedUpdateURL"
        ])
        Self.assertSource(
            runIntegrationText,
            contains: "testRunDueAutomationReportsRunsFileChangeMonitorEventSource"
        )
    }
}
