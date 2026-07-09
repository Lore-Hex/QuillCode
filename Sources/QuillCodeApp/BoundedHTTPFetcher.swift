import Foundation

// URLSession and request/response types live in FoundationNetworking on Linux.
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

enum BoundedHTTPFetcher {
    static func fetch(url: URL, method: String, byteLimit: Int) -> Data? {
        let delegate = Delegate(byteLimit: byteLimit)
        let session = AutomationHTTPURLSessionFactory.session(delegate: delegate)
        defer { session.invalidateAndCancel() }

        let task = session.dataTask(with: request(for: url, method: method))
        task.resume()
        guard delegate.waitForCompletion() else {
            task.cancel()
            return nil
        }
        return delegate.result()
    }

    private static func request(for url: URL, method: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = AutomationHTTPURLSessionFactory.timeout
        return request
    }

    private final class Delegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
        private let completionSemaphore = DispatchSemaphore(value: 0)
        private let byteLimit: Int
        private let lock = NSLock()
        private var response: HTTPURLResponse?
        private var body = Data()
        private var exceededLimit = false

        init(byteLimit: Int) {
            self.byteLimit = byteLimit
        }

        func waitForCompletion() -> Bool {
            completionSemaphore.wait(timeout: AutomationHTTPURLSessionFactory.deadline) == .success
        }

        func result() -> Data? {
            lock.lock()
            defer { lock.unlock() }
            guard let response,
                  (200..<400).contains(response.statusCode),
                  !exceededLimit
            else {
                return nil
            }
            return body
        }

        func urlSession(
            _ session: URLSession,
            task: URLSessionTask,
            willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest,
            completionHandler: @escaping (URLRequest?) -> Void
        ) {
            completionHandler(nil)
        }

        func urlSession(
            _ session: URLSession,
            dataTask: URLSessionDataTask,
            didReceive response: URLResponse,
            completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
        ) {
            lock.lock()
            self.response = response as? HTTPURLResponse
            lock.unlock()
            completionHandler(.allow)
        }

        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
            lock.lock()
            defer { lock.unlock() }
            guard !exceededLimit else { return }
            if body.count + data.count > byteLimit {
                exceededLimit = true
                dataTask.cancel()
                return
            }
            body.append(data)
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            completionSemaphore.signal()
        }
    }
}
