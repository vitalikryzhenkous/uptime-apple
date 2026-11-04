import XCTest
@testable import UptimeKit

final class StringsTests: XCTestCase {
    /// Intl.PluralRules (what board.js uses) for 0…111, one char per number: o=one f=few m=many t=other.
    /// Generated with node; the Swift rules must match it exactly.
    private let cldr: [String: String] = [
        "ru": "mofffmmmmmmmmmmmmmmmmofffmmmmmmofffmmmmmmofffmmmmmmofffmmmmmmofffmmmmmmofffmmmmmmofffmmmmmmofffmmmmmmofffmmmmmmm",
        "uk": "mofffmmmmmmmmmmmmmmmmofffmmmmmmofffmmmmmmofffmmmmmmofffmmmmmmofffmmmmmmofffmmmmmmofffmmmmmmofffmmmmmmofffmmmmmmm",
        "pl": "mofffmmmmmmmmmmmmmmmmmfffmmmmmmmfffmmmmmmmfffmmmmmmmfffmmmmmmmfffmmmmmmmfffmmmmmmmfffmmmmmmmfffmmmmmmmfffmmmmmmm",
        "en": "totttttttttttttttttttttttttttttttttttttttttttttttttttttttttttttttttttttttttttttttttttttttttttttttttttttttttttttt",
    ]

    func testPluralFormsMatchIntl() {
        let letter = ["one": "o", "few": "f", "many": "m", "other": "t"]
        for (lang, expected) in cldr {
            let got = (0..<112).map { letter[Strings.pluralForm(lang: lang, count: $0)]! }.joined()
            XCTAssertEqual(got, expected, lang)
        }
        XCTAssertEqual(Strings.pluralForm(lang: "ru-RU", count: 21), "one")
        XCTAssertEqual(Strings.pluralForm(lang: "de", count: 1), "one")
        XCTAssertEqual(Strings.pluralForm(lang: "de", count: 2), "other")
    }

    private let ru = Strings(lang: "ru", table: [
        "ctx.turns.one": "≈{n} ход до заполнения",
        "ctx.turns.few": "≈{n} хода до заполнения",
        "ctx.turns.many": "≈{n} ходов до заполнения",
        "ctx.turns.other": "≈{n} хода до заполнения",
        "subs.run.other": "{n} работают",
        "notify.done.title": "{who}: агент закончил ход",
        "persona.hungry.1": "Миска пуста: {n} коммитов.",
        "x.two": "{a} и {a}, {b}",
    ])

    func testTp() {
        XCTAssertEqual(ru.tp("ctx.turns", count: 1), "≈1 ход до заполнения")
        XCTAssertEqual(ru.tp("ctx.turns", count: 3), "≈3 хода до заполнения")
        XCTAssertEqual(ru.tp("ctx.turns", count: 87), "≈87 ходов до заполнения")
        XCTAssertEqual(ru.tp("ctx.turns", count: 21), "≈21 ход до заполнения")
        // only .other exists → used for every count
        XCTAssertEqual(ru.tp("subs.run", count: 1), "1 работают")
        // nothing at all → the key is visible, like the board
        XCTAssertEqual(ru.tp("nope", count: 2), "nope.other")
    }

    func testTrFillsAndFallsBack() {
        XCTAssertEqual(ru.tr("notify.done.title", ["who": .string("demo")]), "demo: агент закончил ход")
        XCTAssertEqual(ru.tr("x.two", ["a": .number(1), "b": .bool(true)]), "1 и 1, true")
        XCTAssertEqual(ru.tr("missing"), "missing")
        XCTAssertEqual(ru.tr("missing", fallback: "server text"), "server text")
        XCTAssertEqual(ru.tr("notify.done.title"), "{who}: агент закончил ход") // no vars → left as is
    }

    func testServerTexts() throws {
        let s = try UptimeJSON.status(from: Data(#"""
        {"api": 1,
         "nikolai": [{"id": "a", "kind": "mood", "key": "persona.hungry.1", "vars": {"n": 0}, "text": "server"},
                     {"id": "b", "kind": "mood", "key": "persona.unknown", "vars": {}, "text": "server fallback"},
                     {"id": "c", "kind": "mood", "text": "no key"}],
         "notifications": [{"id": "n1", "kind": "done", "title_key": "notify.done.title", "body_key": "nope",
                            "vars": {"who": "demo"}, "title": "t", "body": "server body"}]}
        """#.utf8))
        XCTAssertEqual(ru.text(for: s.nikolai![0]), "Миска пуста: 0 коммитов.")
        XCTAssertEqual(ru.text(for: s.nikolai![1]), "server fallback")
        XCTAssertEqual(ru.text(for: s.nikolai![2]), "no key")
        XCTAssertEqual(ru.title(for: s.notifications![0]), "demo: агент закончил ход")
        XCTAssertEqual(ru.body(for: s.notifications![0]), "server body")
    }

    func testDecodeLocaleSkipsNonStrings() throws {
        let s = try Strings(lang: "en", data: Data(#"{"a": "A", "b": 2, "c": null}"#.utf8))
        XCTAssertEqual(s.table, ["a": "A"])
    }

    func testLangCodes() {
        for ok in ["ru", "en", "pl", "fil", "pt-BR"] { XCTAssertTrue(Strings.isValidCode(ok), ok) }
        for bad in ["", "RU", "r", "../x", "ru/../../etc", "pt-br", "english"] { XCTAssertFalse(Strings.isValidCode(bad), bad) }
    }

    func testResolveLanguage() throws {
        let ext = try JSONDecoder().decode(ExtInfo.self, from: Data(#"""
        {"langs": [{"code": "en", "name": "English"}, {"code": "ru", "name": "Русский"}],
         "default_lang": "ru", "persona": {"name": "Buddy"}, "themes": [], "persona_packs": []}
        """#.utf8))
        XCTAssertEqual(ext.resolve(preferred: "en"), "en")
        XCTAssertEqual(ext.resolve(preferred: nil), "ru")
        XCTAssertEqual(ext.resolve(preferred: "pl"), "ru") // not offered → board default
        XCTAssertEqual(ext.persona?.name, "Buddy")
    }
}
