import Foundation

protocol QuillCodeDesktopUpdateDownloading: Sendable {
    func download(
        from url: URL,
        to destinationURL: URL,
        maximumBytes: Int64,
        progress: @escaping @Sendable (_ receivedBytes: Int64) -> Void
    ) async throws
}

struct QuillCodeDesktopUpdateDownloader: QuillCodeDesktopUpdateDownloading, @unchecked Sendable {
    private let sessionConfiguration: URLSessionConfiguration

    init(session: URLSession? = nil) {
        self.sessionConfiguration = session?.configuration ?? Self.makeSessionConfiguration()
    }

    func download(
        from url: URL,
        to destinationURL: URL,
        maximumBytes: Int64,
        progress: @escaping @Sendable (_ receivedBytes: Int64) -> Void
    ) async throws {
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("application/zip", forHTTPHeaderField: "Accept")
        request.setValue("Quill-Cowork-Updater/1", forHTTPHeaderField: "User-Agent")

        let delegate = try QuillCodeDesktopUpdateDataDelegate(
            destinationURL: destinationURL,
            maximumBytes: maximumBytes,
            progress: progress
        )
        let delegateQueue = OperationQueue()
        delegateQueue.name = "co.lorehex.QuillCowork.update-download"
        delegateQueue.qualityOfService = .utility
        delegateQueue.maxConcurrentOperationCount = 1
        let session = URLSession(
            configuration: sessionConfiguration,
            delegate: delegate,
            delegateQueue: delegateQueue
        )
        defer { session.invalidateAndCancel() }

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, any Error>) in
                let task = session.dataTask(with: request)
                if delegate.start(task: task, continuation: continuation) {
                    task.resume()
                }
            }
        } onCancel: {
            delegate.cancel()
        }
    }

    private static func makeSessionConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 30 * 60
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.urlCache = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.waitsForConnectivity = true
        return configuration
    }
}

private final class QuillCodeDesktopUpdateDataDelegate: NSObject,
    URLSessionDataDelegate,
    @unchecked Sendable
{
    private let destinationURL: URL
    private let temporaryURL: URL
    private let maximumBytes: Int64
    private let reportIntervalBytes: Int64
    private let progress: @Sendable (Int64) -> Void
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, any Error>?
    private var task: URLSessionDataTask?
    private var outputHandle: FileHandle?
    private var receivedBytes: Int64 = 0
    private var lastReportedBytes: Int64 = 0
    private var cancelRequested = false
    private var isComplete = false

    init(
        destinationURL: URL,
        maximumBytes: Int64,
        progress: @escaping @Sendable (Int64) -> Void
    ) throws {
        self.destinationURL = destinationURL
        self.temporaryURL = destinationURL.deletingLastPathComponent().appendingPathComponent(
            ".\(destinationURL.lastPathComponent).\(UUID().uuidString.lowercased()).download",
            isDirectory: false
        )
        self.maximumBytes = maximumBytes
        self.reportIntervalBytes = max(64 * 1_024, min(maximumBytes / 100, 1_024 * 1_024))
        self.progress = progress
        guard maximumBytes > 0,
              FileManager.default.createFile(atPath: temporaryURL.path, contents: nil)
        else {
            throw QuillCodeDesktopUpdateError.installationFailed(
                "the download workspace could not be created"
            )
        }
        self.outputHandle = try FileHandle(forWritingTo: temporaryURL)
    }

    deinit {
        try? outputHandle?.close()
        try? FileManager.default.removeItem(at: temporaryURL)
    }

    func start(
        task: URLSessionDataTask,
        continuation: CheckedContinuation<Void, any Error>
    ) -> Bool {
        lock.lock()
        self.task = task
        self.continuation = continuation
        let shouldCancel = cancelRequested
        lock.unlock()
        if shouldCancel {
            task.cancel()
            complete(.failure(CancellationError()))
            return false
        }
        return true
    }

    func cancel() {
        lock.lock()
        cancelRequested = true
        let task = task
        let hasContinuation = continuation != nil
        lock.unlock()
        task?.cancel()
        if hasContinuation {
            complete(.failure(CancellationError()))
        }
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void
    ) {
        guard let response = response as? HTTPURLResponse,
              response.statusCode == 200
        else {
            completionHandler(.cancel)
            complete(.failure(QuillCodeDesktopUpdateError.invalidResponse))
            return
        }
        guard response.expectedContentLength <= 0 || response.expectedContentLength <= maximumBytes else {
            completionHandler(.cancel)
            complete(.failure(QuillCodeDesktopUpdateError.downloadSizeMismatch))
            return
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        guard !isComplete, let outputHandle else {
            lock.unlock()
            return
        }
        let incomingByteCount = Int64(data.count)
        guard incomingByteCount <= maximumBytes - receivedBytes else {
            lock.unlock()
            dataTask.cancel()
            complete(.failure(QuillCodeDesktopUpdateError.downloadSizeMismatch))
            return
        }
        let nextByteCount = receivedBytes + incomingByteCount
        do {
            try outputHandle.write(contentsOf: data)
        } catch {
            lock.unlock()
            dataTask.cancel()
            complete(.failure(QuillCodeDesktopUpdateError.installationFailed(
                "the download could not be staged"
            )))
            return
        }
        receivedBytes = nextByteCount
        let shouldReport = receivedBytes == maximumBytes ||
            receivedBytes - lastReportedBytes >= reportIntervalBytes
        if shouldReport {
            lastReportedBytes = receivedBytes
        }
        let reportedBytes = receivedBytes
        lock.unlock()
        if shouldReport { progress(reportedBytes) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if error != nil {
            complete(.failure(QuillCodeDesktopUpdateError.invalidResponse))
        } else {
            completeSuccessfulTransfer()
        }
    }

    private func completeSuccessfulTransfer() {
        lock.lock()
        let byteCount = receivedBytes
        lock.unlock()
        guard byteCount == maximumBytes else {
            complete(.failure(QuillCodeDesktopUpdateError.downloadSizeMismatch))
            return
        }
        complete(.success(()))
    }

    private func complete(_ result: Result<Void, any Error>) {
        lock.lock()
        guard !isComplete, let continuation else {
            lock.unlock()
            return
        }
        isComplete = true
        self.continuation = nil
        task = nil
        let outputHandle = outputHandle
        self.outputHandle = nil
        lock.unlock()

        try? outputHandle?.close()
        let finalResult: Result<Void, any Error>
        switch result {
        case .success:
            do {
                try FileManager.default.moveItem(at: temporaryURL, to: destinationURL)
                finalResult = .success(())
            } catch {
                try? FileManager.default.removeItem(at: temporaryURL)
                finalResult = .failure(QuillCodeDesktopUpdateError.installationFailed(
                    "the download could not be staged"
                ))
            }
        case .failure(let error):
            try? FileManager.default.removeItem(at: temporaryURL)
            finalResult = .failure(error)
        }
        continuation.resume(with: finalResult)
    }
}
