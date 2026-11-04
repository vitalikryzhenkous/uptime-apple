import Foundation
import Observation

/// Fetches static resources from the board: `api/v1/ext`, `locales/<lang>.json`, `sprites.json`.
public protocol AssetSource: Sendable {
    func data(path: String) async throws -> Data
}

extension APIClient: AssetSource {
    public func data(path: String) async throws -> Data {
        let (data, response) = try await session.data(for: request(path))
        try Self.check(response)
        return data
    }
}

/// Raw files kept on disk, so the app starts translated and with Buddy drawn even before the server answers.
public struct ResourceCache: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// `~/Library/Application Support/<bundle id>/cache` (inside the sandbox container for the app).
    public static func standard() -> ResourceCache? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let id = Bundle.main.bundleIdentifier ?? "uptime"
        return ResourceCache(directory: base.appending(path: id).appending(path: "cache"))
    }

    private func url(_ name: String) -> URL { directory.appending(path: name + ".json") }

    public func load(_ name: String) -> Data? { try? Data(contentsOf: url(name)) }

    public func save(_ name: String, _ data: Data) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: url(name), options: .atomic)
    }
}

/// Strings and sprites for the UI. Starts from the disk cache; `refresh` fetches fresh copies
/// (at launch, when the board's build changes, when the user picks another language).
@MainActor
@Observable
public final class AssetStore {
    public private(set) var strings: Strings
    public private(set) var sprites: Sprites?
    public private(set) var ext: ExtInfo?

    @ObservationIgnored private let cache: ResourceCache?

    public init(cache: ResourceCache?) {
        self.cache = cache
        let lang = cache?.load("lang").flatMap { String(data: $0, encoding: .utf8) }.flatMap {
            Strings.isValidCode($0) ? $0 : nil
        }
        if let lang, let data = cache?.load("locale-\(lang)"), let s = try? Strings(lang: lang, data: data) {
            strings = s
        } else {
            strings = .empty
        }
        sprites = cache?.load("sprites").flatMap { try? Sprites.decode($0) }
        ext = cache?.load("ext").flatMap { try? JSONDecoder().decode(ExtInfo.self, from: $0) }
    }

    /// Each part is independent: a failed request keeps what is already loaded.
    /// - Parameter preferred: the user's language, `nil` = the board's default.
    public func refresh(from source: any AssetSource, preferred: String?) async {
        if let data = try? await source.data(path: "api/v1/ext"),
           let info = try? JSONDecoder().decode(ExtInfo.self, from: data) {
            ext = info
            cache?.save("ext", data)
        }
        let lang = ext?.resolve(preferred: preferred) ?? preferred ?? strings.lang
        if Strings.isValidCode(lang),
           let data = try? await source.data(path: "locales/\(lang).json"),
           let s = try? Strings(lang: lang, data: data) {
            strings = s
            cache?.save("locale-\(lang)", data)
            cache?.save("lang", Data(lang.utf8))
        }
        if let data = try? await source.data(path: "sprites.json"), let sp = try? Sprites.decode(data) {
            sprites = sp
            cache?.save("sprites", data)
        }
    }
}
