import CoreGraphics
import Foundation
import ImageIO
import QuillCodePlatformUI
import SwiftUI

struct QuillCodeDecodedThumbnail: @unchecked Sendable {
    var image: CGImage
    var pixelWidth: Int
    var pixelHeight: Int
}

enum QuillCodeImageThumbnailError: Error {
    case invalidSource
    case sourceTooLarge
    case unsupportedImage
}

enum QuillCodeImageThumbnailLoader {
    static let maximumEncodedBytes = 32 * 1_024 * 1_024

    static func load(
        from url: URL,
        maximumPixelSize: Int,
        remoteSessionConfiguration: URLSessionConfiguration? = nil
    ) async throws -> QuillCodeDecodedThumbnail {
        let boundedPixelSize = max(1, maximumPixelSize)
        if url.isFileURL {
            return try await Task.detached(priority: .utility) {
                try thumbnail(fromFile: url, maximumPixelSize: boundedPixelSize)
            }.value
        }
        let encodedData: Data
        switch url.scheme?.lowercased() {
        case "data":
            encodedData = try data(from: url)
        case "https", "http":
            encodedData = try await remoteData(
                from: url,
                sessionConfiguration: remoteSessionConfiguration
            )
        default:
            throw QuillCodeImageThumbnailError.invalidSource
        }
        return try await Task.detached(priority: .utility) {
            try thumbnail(from: encodedData, maximumPixelSize: boundedPixelSize)
        }.value
    }

    static func thumbnail(
        from data: Data,
        maximumPixelSize: Int
    ) throws -> QuillCodeDecodedThumbnail {
        guard !data.isEmpty, data.count <= maximumEncodedBytes else {
            throw QuillCodeImageThumbnailError.sourceTooLarge
        }
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options) else {
            return try svgThumbnail(from: data, maximumPixelSize: maximumPixelSize)
        }
        do {
            return try thumbnail(from: source, maximumPixelSize: maximumPixelSize)
        } catch QuillCodeImageThumbnailError.unsupportedImage {
            return try svgThumbnail(from: data, maximumPixelSize: maximumPixelSize)
        }
    }

    static func thumbnail(
        fromFile url: URL,
        maximumPixelSize: Int
    ) throws -> QuillCodeDecodedThumbnail {
        let resolvedURL = url.resolvingSymlinksInPath().standardizedFileURL
        let values = try resolvedURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true else {
            throw QuillCodeImageThumbnailError.invalidSource
        }
        guard let fileSize = values.fileSize,
              fileSize > 0,
              fileSize <= maximumEncodedBytes
        else {
            throw QuillCodeImageThumbnailError.sourceTooLarge
        }
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(resolvedURL as CFURL, options) else {
            let data = try Data(contentsOf: resolvedURL, options: .mappedIfSafe)
            return try svgThumbnail(from: data, maximumPixelSize: maximumPixelSize)
        }
        do {
            return try thumbnail(from: source, maximumPixelSize: maximumPixelSize)
        } catch QuillCodeImageThumbnailError.unsupportedImage {
            let data = try Data(contentsOf: resolvedURL, options: .mappedIfSafe)
            return try svgThumbnail(from: data, maximumPixelSize: maximumPixelSize)
        }
    }

    private static func thumbnail(
        from source: CGImageSource,
        maximumPixelSize: Int
    ) throws -> QuillCodeDecodedThumbnail {
        let boundedPixelSize = max(1, maximumPixelSize)
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: boundedPixelSize,
            kCGImageSourceShouldCacheImmediately: true,
        ] as CFDictionary
        guard CGImageSourceGetCount(source) > 0,
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options)
        else {
            throw QuillCodeImageThumbnailError.unsupportedImage
        }
        return QuillCodeDecodedThumbnail(
            image: image,
            pixelWidth: image.width,
            pixelHeight: image.height
        )
    }

    private static func svgThumbnail(
        from data: Data,
        maximumPixelSize: Int
    ) throws -> QuillCodeDecodedThumbnail {
        let header = String(decoding: data.prefix(4_096), as: UTF8.self).lowercased()
        guard !header.contains("\0"),
              header.contains("<svg"),
              let rasterized = QuillCodePlatformImageRasterizer.rasterizeVectorImage(
                  from: data,
                  maximumPixelSize: maximumPixelSize
              )
        else {
            throw QuillCodeImageThumbnailError.unsupportedImage
        }
        return QuillCodeDecodedThumbnail(
            image: rasterized,
            pixelWidth: rasterized.width,
            pixelHeight: rasterized.height
        )
    }

    private static func data(from url: URL) throws -> Data {
        let source = url.absoluteString
        guard source.lowercased().hasPrefix("data:image/"),
              let separator = source.firstIndex(of: ",")
        else {
            throw QuillCodeImageThumbnailError.invalidSource
        }
        let metadata = source[..<separator].lowercased()
        let payload = source[source.index(after: separator)...]
        if metadata.hasSuffix(";base64") {
            let maximumBase64Characters = ((maximumEncodedBytes + 2) / 3) * 4
            guard payload.utf8.count <= maximumBase64Characters,
                  let data = Data(base64Encoded: String(payload)),
                  data.count <= maximumEncodedBytes
            else {
                throw QuillCodeImageThumbnailError.sourceTooLarge
            }
            return data
        }

        guard payload.utf8.count <= maximumEncodedBytes * 3,
              let decoded = String(payload).removingPercentEncoding,
              let data = decoded.data(using: .utf8),
              data.count <= maximumEncodedBytes
        else {
            throw QuillCodeImageThumbnailError.sourceTooLarge
        }
        return data
    }

    private static func remoteData(
        from url: URL,
        sessionConfiguration: URLSessionConfiguration?
    ) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("image/*", forHTTPHeaderField: "Accept")
        request.setValue("Quill-Cowork-Image-Preview/1", forHTTPHeaderField: "User-Agent")

        let delegate = QuillCodeBoundedImageDataDelegate(maximumBytes: maximumEncodedBytes)
        let delegateQueue = OperationQueue()
        delegateQueue.name = "co.lorehex.QuillCowork.image-preview"
        delegateQueue.qualityOfService = .utility
        delegateQueue.maxConcurrentOperationCount = 1
        let session = URLSession(
            configuration: sessionConfiguration ?? makeRemoteSessionConfiguration(),
            delegate: delegate,
            delegateQueue: delegateQueue
        )
        defer { session.invalidateAndCancel() }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Data, any Error>) in
                let task = session.dataTask(with: request)
                if delegate.start(task: task, continuation: continuation) {
                    task.resume()
                }
            }
        } onCancel: {
            delegate.cancel()
        }
    }

    private static func makeRemoteSessionConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.urlCache = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.waitsForConnectivity = true
        return configuration
    }
}

struct QuillCodeBoundedAsyncImage<Content: View>: View {
    var url: URL?
    var maximumPixelSize: Int
    @ViewBuilder var content: (AsyncImagePhase) -> Content

    @State private var phase: AsyncImagePhase = .empty

    var body: some View {
        content(phase)
            .task(id: LoadRequest(url: url, maximumPixelSize: maximumPixelSize)) {
                guard let url else {
                    phase = .failure(QuillCodeImageThumbnailError.invalidSource)
                    return
                }
                phase = .empty
                do {
                    let thumbnail = try await QuillCodeImageThumbnailLoader.load(
                        from: url,
                        maximumPixelSize: maximumPixelSize
                    )
                    try Task.checkCancellation()
                    phase = .success(Image(
                        decorative: thumbnail.image,
                        scale: 1,
                        orientation: .up
                    ))
                } catch is CancellationError {
                    return
                } catch {
                    phase = .failure(error)
                }
            }
    }

    private struct LoadRequest: Hashable {
        var url: URL?
        var maximumPixelSize: Int
    }
}

private final class QuillCodeBoundedImageDataDelegate: NSObject,
    URLSessionDataDelegate,
    @unchecked Sendable
{
    private let maximumBytes: Int
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Data, any Error>?
    private var task: URLSessionDataTask?
    private var receivedData = Data()
    private var cancelRequested = false
    private var isComplete = false

    init(maximumBytes: Int) {
        self.maximumBytes = maximumBytes
    }

    func start(
        task: URLSessionDataTask,
        continuation: CheckedContinuation<Data, any Error>
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
            complete(.failure(QuillCodeImageThumbnailError.invalidSource))
            return
        }
        guard response.expectedContentLength <= 0
                || response.expectedContentLength <= Int64(maximumBytes)
        else {
            completionHandler(.cancel)
            complete(.failure(QuillCodeImageThumbnailError.sourceTooLarge))
            return
        }
        if response.expectedContentLength > 0 {
            lock.lock()
            receivedData.reserveCapacity(Int(response.expectedContentLength))
            lock.unlock()
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        guard !isComplete, data.count <= maximumBytes - receivedData.count else {
            lock.unlock()
            dataTask.cancel()
            complete(.failure(QuillCodeImageThumbnailError.sourceTooLarge))
            return
        }
        receivedData.append(data)
        lock.unlock()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        let wasCancelled = cancelRequested
        let data = receivedData
        lock.unlock()
        if wasCancelled {
            complete(.failure(CancellationError()))
        } else if error != nil {
            complete(.failure(QuillCodeImageThumbnailError.invalidSource))
        } else {
            complete(.success(data))
        }
    }

    private func complete(_ result: Result<Data, any Error>) {
        lock.lock()
        guard !isComplete, let continuation else {
            lock.unlock()
            return
        }
        isComplete = true
        self.continuation = nil
        task = nil
        lock.unlock()
        continuation.resume(with: result)
    }
}
