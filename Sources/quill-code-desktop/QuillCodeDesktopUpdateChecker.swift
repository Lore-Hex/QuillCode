import Foundation

protocol QuillCodeDesktopUpdateChecking: Sendable {
    func check(
        configuration: QuillCodeDesktopUpdateConfiguration
    ) async throws -> QuillCodeDesktopUpdateCheckResult
}

protocol QuillCodeDesktopUpdateManifestLoading: Sendable {
    func loadManifest(from url: URL, byteLimit: Int) async throws -> Data
}

struct QuillCodeDesktopUpdateChecker: QuillCodeDesktopUpdateChecking, Sendable {
    static let manifestByteLimit = 256 * 1_024

    private let loader: any QuillCodeDesktopUpdateManifestLoading

    init(loader: any QuillCodeDesktopUpdateManifestLoading = QuillCodeDesktopUpdateManifestLoader()) {
        self.loader = loader
    }

    func check(
        configuration: QuillCodeDesktopUpdateConfiguration
    ) async throws -> QuillCodeDesktopUpdateCheckResult {
        guard GitHubReleaseRepositoryScope(manifestURL: configuration.manifestURL) != nil else {
            throw QuillCodeDesktopUpdateError.unexpectedFeed
        }
        let data = try await loader.loadManifest(
            from: configuration.manifestURL,
            byteLimit: Self.manifestByteLimit
        )
        let manifest: QuillCodeDesktopUpdateManifest
        do {
            manifest = try JSONDecoder().decode(QuillCodeDesktopUpdateManifest.self, from: data)
        } catch {
            throw QuillCodeDesktopUpdateError.unsupportedManifest
        }
        return try QuillCodeDesktopUpdateManifestValidator.validate(
            manifest,
            configuration: configuration
        )
    }
}

struct QuillCodeDesktopUpdateManifestLoader: QuillCodeDesktopUpdateManifestLoading, @unchecked Sendable {
    private let session: URLSession

    init(session: URLSession? = nil) {
        self.session = session ?? Self.makeSession()
    }

    func loadManifest(from url: URL, byteLimit: Int) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Quill-Cowork-Updater/1", forHTTPHeaderField: "User-Agent")

        let bytes: URLSession.AsyncBytes
        let response: URLResponse
        do {
            (bytes, response) = try await session.bytes(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw QuillCodeDesktopUpdateError.invalidResponse
        }
        guard let response = response as? HTTPURLResponse,
              response.statusCode == 200
        else {
            throw QuillCodeDesktopUpdateError.invalidResponse
        }
        guard response.expectedContentLength <= 0 || response.expectedContentLength <= byteLimit else {
            throw QuillCodeDesktopUpdateError.manifestTooLarge
        }

        var data = Data()
        data.reserveCapacity(min(byteLimit, 16 * 1_024))
        do {
            for try await byte in bytes {
                guard data.count < byteLimit else {
                    throw QuillCodeDesktopUpdateError.manifestTooLarge
                }
                data.append(byte)
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as QuillCodeDesktopUpdateError {
            throw error
        } catch {
            throw QuillCodeDesktopUpdateError.invalidResponse
        }
        return data
    }

    private static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.urlCache = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.waitsForConnectivity = true
        return URLSession(configuration: configuration)
    }
}
