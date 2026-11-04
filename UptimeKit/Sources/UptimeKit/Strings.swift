import Foundation

/// The board's strings in one language (`GET /locales/<lang>.json`): flat keys, `{placeholders}`,
/// plurals as `key.one / .few / .many / .other`. Mirrors tr()/tp() in uptime-board/web/board.js.
public struct Strings: Sendable, Equatable {
    public let lang: String
    public let table: [String: String]

    public static let empty = Strings(lang: "ru", table: [:])

    public init(lang: String, table: [String: String]) {
        self.lang = lang
        self.table = table
    }

    /// Decodes a locale file; non-string values are skipped.
    public init(lang: String, data: Data) throws {
        let raw = try JSONDecoder().decode([String: JSONValue].self, from: data)
        var table: [String: String] = [:]
        for (k, v) in raw { if case .string(let s) = v { table[k] = s } }
        self.init(lang: lang, table: table)
    }

    /// A language code the server accepts (same rule as server/i18n.py LANG_RE); also keeps it safe in a URL path.
    public static func isValidCode(_ code: String) -> Bool {
        code.range(of: #"^[a-z]{2,3}(-[A-Z]{2})?$"#, options: .regularExpression) != nil
    }

    /// The text for `key` with `{name}` filled from `vars`. A missing key gives `fallback`
    /// (the server's own text) or, like the board, the key itself — a gap is visible, never blank.
    public func tr(_ key: String, _ vars: [String: JSONValue] = [:], fallback: String? = nil) -> String {
        guard let template = table[key] else { return fallback ?? key }
        return Self.fill(template, vars)
    }

    /// Plural form of `key` for `count`; `{n}` is the count.
    public func tp(_ key: String, count: Int, _ vars: [String: JSONValue] = [:]) -> String {
        let form = Self.pluralForm(lang: lang, count: count)
        let full = table[key + "." + form] != nil ? key + "." + form : key + ".other"
        var v = vars
        v["n"] = .number(Double(count))
        return tr(full, v)
    }

    /// CLDR plural category for integers, as board.js computes it without Intl.
    public static func pluralForm(lang: String, count: Int) -> String {
        let base = lang.split(separator: "-").first.map(String.init) ?? lang
        let n = abs(count), m10 = n % 10, m100 = n % 100
        let few = (2...4).contains(m10) && !(12...14).contains(m100)
        switch base {
        case "ru", "uk":
            if m10 == 1 && m100 != 11 { return "one" }
            return few ? "few" : "many"
        case "pl":
            if n == 1 { return "one" }
            return few ? "few" : "many"
        default:
            return n == 1 ? "one" : "other"
        }
    }

    static func fill(_ template: String, _ vars: [String: JSONValue]) -> String {
        guard !vars.isEmpty, template.contains("{") else { return template }
        var s = template
        for (name, value) in vars { s = s.replacingOccurrences(of: "{\(name)}", with: value.text) }
        return s
    }

    // MARK: server texts

    /// One of the cat's lines in this language (falls back to the server's text).
    public func text(for line: CatLine) -> String {
        guard let key = line.key else { return line.text ?? "" }
        return tr(key, line.vars ?? [:], fallback: line.text)
    }

    public func title(for n: AppNotification) -> String {
        guard let key = n.titleKey else { return n.title ?? "" }
        return tr(key, n.vars ?? [:], fallback: n.title)
    }

    public func body(for n: AppNotification) -> String {
        guard let key = n.bodyKey else { return n.body ?? "" }
        return tr(key, n.vars ?? [:], fallback: n.body)
    }
}

/// `GET /api/v1/ext`: what the board offers (languages; themes and persona packs are not used by the app yet).
public struct ExtInfo: Decodable, Sendable, Equatable {
    public struct Lang: Decodable, Sendable, Equatable, Identifiable {
        public let code: String
        public let name: String
        public var id: String { code }
    }

    public let langs: [Lang]
    public let defaultLang: String?
    public let persona: Persona?

    enum CodingKeys: String, CodingKey {
        case langs, persona
        case defaultLang = "default_lang"
    }

    /// The language to load: the user's choice if the board has it, else the board's default, else the first one.
    public func resolve(preferred: String?) -> String {
        let codes = langs.map(\.code)
        if let p = preferred, codes.contains(p) { return p }
        if let d = defaultLang, codes.contains(d) || codes.isEmpty { return d }
        return codes.first ?? "ru"
    }
}
