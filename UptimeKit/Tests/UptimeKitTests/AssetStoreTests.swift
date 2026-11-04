import XCTest
@testable import UptimeKit

/// Serves fixed bodies by path; a missing path fails like a network error.
private struct FakeAssets: AssetSource {
    let files: [String: String]
    func data(path: String) async throws -> Data {
        guard let body = files[path] else { throw URLError(.notConnectedToInternet) }
        return Data(body.utf8)
    }
}

private let extJSON = #"{"langs": [{"code": "en", "name": "English"}, {"code": "ru", "name": "Русский"}], "default_lang": "ru"}"#
private let spritesJSON = #"{"size": [1, 1], "colors": {"o": "#000000"}, "classes": {}, "poses": {"sit": ["o"]}, "overlays": {}, "marks": {}}"#

final class AssetStoreTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appending(path: "uptime-tests-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    @MainActor
    func testRefreshLoadsAndCaches() async {
        let source = FakeAssets(files: [
            "api/v1/ext": extJSON,
            "locales/ru.json": #"{"hello": "Привет"}"#,
            "locales/en.json": #"{"hello": "Hello"}"#,
            "sprites.json": spritesJSON,
        ])
        let store = AssetStore(cache: ResourceCache(directory: dir))
        XCTAssertNil(store.sprites)

        await store.refresh(from: source, preferred: nil) // board default
        XCTAssertEqual(store.strings.lang, "ru")
        XCTAssertEqual(store.strings.tr("hello"), "Привет")
        XCTAssertEqual(store.sprites?.rows(pose: "sit"), ["o"])
        XCTAssertEqual(store.ext?.langs.count, 2)

        await store.refresh(from: source, preferred: "en")
        XCTAssertEqual(store.strings.tr("hello"), "Hello")

        // a new store starts from the disk cache: last language, sprites, ext — before any network
        let cold = AssetStore(cache: ResourceCache(directory: dir))
        XCTAssertEqual(cold.strings.lang, "en")
        XCTAssertEqual(cold.strings.tr("hello"), "Hello")
        XCTAssertEqual(cold.sprites?.rows(pose: "sit"), ["o"])
        XCTAssertEqual(cold.ext?.defaultLang, "ru")
    }

    @MainActor
    func testFailuresKeepWhatIsLoaded() async {
        let store = AssetStore(cache: ResourceCache(directory: dir))
        await store.refresh(from: FakeAssets(files: [
            "api/v1/ext": extJSON, "locales/ru.json": #"{"hello": "Привет"}"#, "sprites.json": spritesJSON,
        ]), preferred: nil)

        await store.refresh(from: FakeAssets(files: ["sprites.json": "not json"]), preferred: nil) // server down / broken
        XCTAssertEqual(store.strings.tr("hello"), "Привет")
        XCTAssertNotNil(store.sprites)
        XCTAssertEqual(store.ext?.defaultLang, "ru")
    }

    @MainActor
    func testUnsafeLanguageIsNotRequested() async {
        let store = AssetStore(cache: nil)
        await store.refresh(from: FakeAssets(files: ["locales/../x.json": #"{"hello": "bad"}"#]), preferred: "../x")
        XCTAssertEqual(store.strings, .empty)
    }
}
