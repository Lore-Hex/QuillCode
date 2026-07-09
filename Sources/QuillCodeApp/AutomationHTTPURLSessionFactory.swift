import Foundation

// URLSession and request/response types live in FoundationNetworking on Linux.
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

enum AutomationHTTPURLSessionFactory {
    static let timeout: TimeInterval = 8
    static var deadline: DispatchTime { DispatchTime.now() + 10 }

    static func session(delegate: URLSessionDataDelegate) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.urlCache = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        return URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
    }
}
