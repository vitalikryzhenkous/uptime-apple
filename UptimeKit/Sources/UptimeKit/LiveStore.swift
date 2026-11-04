import Foundation
import Observation

public enum ConnectionState: Equatable, Sendable {
    case idle
    /// No token saved yet — open Settings.
    case noToken
    case connecting
    case live
    /// Waiting `seconds` before the next attempt; `reason` is for the UI.
    case retrying(seconds: Int, reason: String)
    /// 401: the token is wrong. Stays here until the token changes (`start()` again).
    case unauthorized
    /// 503: the server has no token configured.
    case notConfigured
    /// The server speaks a newer API; the app needs an update.
    case unsupportedAPI(Int)
}

/// Reconnect delays: 1, 2, 4, 8, 16, then 30 s.
public enum Backoff {
    public static let max = 30

    public static func seconds(attempt: Int) -> Int {
        Swift.min(max, 1 << Swift.min(Swift.max(attempt - 1, 0), 5))
    }
}

/// The live status for the UI: GET /status, then the SSE stream, reconnecting with backoff (1, 2, 4 … 30 s).
@MainActor
@Observable
public final class LiveStore {
    public private(set) var status: Status?
    public private(set) var connection: ConnectionState = .idle
    public private(set) var lastUpdate: Date?
    /// Server clock minus this Mac's clock, seconds — durations are counted on the server's clock, like the board.
    public private(set) var clockOffset: Double = 0
    /// When the connection last left `.live` (nil while live) — the UI waits `Panel.offlineGrace` before saying so.
    public private(set) var offlineSince: Date?
    /// Diagnostics for Settings: how often the stream dropped since launch, and the last reason.
    public private(set) var drops = 0
    public private(set) var lastError: String?
    public private(set) var lastErrorAt: Date?

    /// "Now" on the server's clock (epoch seconds).
    public func serverNow(_ date: Date = Date()) -> Double { date.timeIntervalSince1970 + clockOffset }

    @ObservationIgnored private var loop: Task<Void, Never>?
    private let makeSource: @Sendable () -> (any StatusSource)?
    private let sleep: @Sendable (Int) async throws -> Void

    /// - Parameters:
    ///   - makeSource: builds a client from the current settings; `nil` when there is no token.
    ///   - sleep: waits the given seconds (injected so tests do not wait).
    public init(makeSource: @escaping @Sendable () -> (any StatusSource)?,
                sleep: @escaping @Sendable (Int) async throws -> Void = { try await Task.sleep(for: .seconds($0)) }) {
        self.makeSource = makeSource
        self.sleep = sleep
    }

    /// (Re)connect from scratch — after launch, a settings change or waking from sleep.
    public func start() {
        loop?.cancel()
        loop = Task { [weak self] in await self?.run() }
    }

    public func stop() {
        loop?.cancel()
        loop = nil
        connection = .idle
    }

    func run() async {
        var attempt = 0
        while !Task.isCancelled {
            guard let source = makeSource() else { leaveLive(.noToken); return }
            leaveLive(.connecting)
            var reason = ""
            do {
                apply(try await source.status())
                attempt = 0
                for try await event in source.events() {
                    if case .status(let s) = event { apply(s) }
                    attempt = 0
                }
                reason = "stream ended"
            } catch let e as APIError {
                switch e {
                case .unauthorized: leaveLive(.unauthorized); return
                case .notConfigured: leaveLive(.notConfigured); return
                case .unsupportedAPI(let v): leaveLive(.unsupportedAPI(v)); return
                case .badStatus(let code): reason = "HTTP \(code)"
                case .invalidResponse: reason = "invalid response"
                }
            } catch {
                if Task.isCancelled || error is CancellationError { return }
                reason = (error as? URLError).map(Self.describe) ?? "\(type(of: error))"
            }
            attempt += 1
            drops += 1
            lastError = reason
            lastErrorAt = Date()
            let delay = Backoff.seconds(attempt: attempt)
            leaveLive(.retrying(seconds: delay, reason: reason))
            do { try await sleep(delay) } catch { return }
        }
    }

    /// Readable reason instead of "-1005".
    nonisolated static func describe(_ e: URLError) -> String {
        switch e.code {
        case .networkConnectionLost: return "connection lost"
        case .timedOut: return "timeout"
        case .notConnectedToInternet: return "no network"
        case .cannotFindHost, .dnsLookupFailed: return "host not found"
        case .cannotConnectToHost: return "server unreachable"
        case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate: return "TLS"
        default: return "network \(e.code.rawValue)"
        }
    }

    private func leaveLive(_ state: ConnectionState) {
        if offlineSince == nil { offlineSince = Date() }
        connection = state
    }

    private func apply(_ s: Status) {
        let now = Date()
        status = s
        lastUpdate = now
        if let t = s.serverTime { clockOffset = t - now.timeIntervalSince1970 }
        offlineSince = nil
        connection = .live
    }
}
