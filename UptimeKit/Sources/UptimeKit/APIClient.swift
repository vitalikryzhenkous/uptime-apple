import Foundation

public enum APIError: Error, Equatable, Sendable {
    /// 401 — wrong token.
    case unauthorized
    /// 503 — the server has no UPTIME_API_TOKEN.
    case notConfigured
    /// The server speaks a newer API than this client.
    case unsupportedAPI(Int)
    case badStatus(Int)
    case invalidResponse
}

public enum ServerEvent: Sendable {
    case status(Status)
    case ping
}

/// Where live data comes from; the store depends on this, tests use a fake.
public protocol StatusSource: Sendable {
    func status() async throws -> Status
    /// `status` events (the first one at once) and `ping`s; finishes or throws when the stream breaks.
    func events() -> AsyncThrowingStream<ServerEvent, Error>
}

public struct ServerConfig {
    public static let defaultBaseURL = URL(string: "https://m920q-wsl.tail2012ad.ts.net:8443")!
    /// The server pings every 15 s; this much silence means the stream is dead (docs/api.md: ~40 s).
    public static let streamIdleTimeout: TimeInterval = 40
}

/// API v1 over HTTPS with a bearer token (contract: uptime-board/docs/api.md).
public struct APIClient: StatusSource {
    public let baseURL: URL
    private let token: String
    private let session: URLSession

    public init(baseURL: URL, token: String, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.token = token
        self.session = session
    }

    func request(_ path: String, accept: String = "application/json") -> URLRequest {
        var r = URLRequest(url: baseURL.appending(path: path))
        r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        r.setValue(accept, forHTTPHeaderField: "Accept")
        r.cachePolicy = .reloadIgnoringLocalCacheData
        r.timeoutInterval = 15
        return r
    }

    static func check(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        switch http.statusCode {
        case 200: return
        case 401: throw APIError.unauthorized
        case 503: throw APIError.notConfigured
        default: throw APIError.badStatus(http.statusCode)
        }
    }

    static func decode(_ data: Data) throws -> Status {
        let s = try UptimeJSON.status(from: data)
        if s.api > UptimeJSON.supportedAPI { throw APIError.unsupportedAPI(s.api) }
        return s
    }

    public func status() async throws -> Status {
        let (data, response) = try await session.data(for: request("api/v1/status"))
        try Self.check(response)
        return try Self.decode(data)
    }

    public func events() -> AsyncThrowingStream<ServerEvent, Error> {
        let req: URLRequest = {
            var r = request("api/v1/events", accept: "text/event-stream")
            r.timeoutInterval = ServerConfig.streamIdleTimeout // idle timeout between bytes = dead-stream watchdog
            return r
        }()
        let session = self.session
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, response) = try await session.bytes(for: req)
                    try Self.check(response)
                    var parser = SSEParser()
                    for try await byte in bytes {
                        guard let e = parser.push(byte) else { continue }
                        switch e.event {
                        case "status": continuation.yield(.status(try Self.decode(Data(e.data.utf8))))
                        case "ping": continuation.yield(.ping)
                        default: break
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
