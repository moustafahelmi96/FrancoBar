import Foundation

struct Word {
    var leading: String      // whitespace before the word, kept as typed
    var prefix: String       // punctuation around the word
    var franco: String       // lowercased lookup key, e.g. "enaharda"
    var suffix: String
    var candidates: [String]
    var chosen = 0

    var arabic: String { candidates.indices.contains(chosen) ? candidates[chosen] : franco }
    var text: String { prefix + arabic + suffix }
}

struct Conversion {
    var source: String
    var words: [Word]
    var trailing: String
    var offline: Bool
    var text: String { words.map { $0.leading + $0.text }.joined() + trailing }
}

/// Franco → Arabic. Order per word: your saved words, then cached Google results,
/// then Google Input Tools (5 candidates), then offline rules.
final class Transliterator {
    static let shared = Transliterator()

    private(set) var dictionary: [String: String] = [:]
    /// True when dictionary.json can't be parsed; saving is refused so hand edits aren't overwritten.
    private(set) var dictionaryBroken = false
    private var cache: [String: [String]] = [:]
    let dictionaryURL: URL
    private let cacheURL: URL

    init(folder: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FrancoBar")) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        dictionaryURL = folder.appendingPathComponent("dictionary.json")
        cacheURL = folder.appendingPathComponent("cache.json")
        cache = Self.load(cacheURL) ?? [:]
        reloadDictionary()
    }

    func reloadDictionary() {
        guard FileManager.default.fileExists(atPath: dictionaryURL.path) else {
            dictionary = [:]
            dictionaryBroken = false
            Self.save(dictionary, to: dictionaryURL)
            return
        }
        if let d: [String: String] = Self.load(dictionaryURL) {
            dictionary = Dictionary(d.map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { a, _ in a })
            dictionaryBroken = false
        } else {
            dictionaryBroken = true
        }
    }

    @discardableResult
    func remember(_ franco: String, as arabic: String) -> Bool {
        reloadDictionary()
        guard !dictionaryBroken, !franco.isEmpty else { return false }
        dictionary[franco] = arabic
        Self.save(dictionary, to: dictionaryURL)
        return true
    }

    @discardableResult
    func forget(_ franco: String) -> Bool {
        reloadDictionary()
        guard !dictionaryBroken else { return false }
        dictionary[franco] = nil
        Self.save(dictionary, to: dictionaryURL)
        return true
    }

    func convert(_ text: String, completion: @escaping (Conversion) -> Void) {
        let (tokens, trailing) = Self.tokenize(text)
        var words = tokens.map { t in
            Word(leading: t.leading, prefix: t.prefix, franco: t.core, suffix: t.suffix, candidates: candidates(for: t.core) ?? [])
        }
        let missing = Set(words.filter { $0.candidates.isEmpty && !$0.franco.isEmpty }.map(\.franco))
        var fetched: [String: [String]?] = [:]
        let lock = NSLock()
        let group = DispatchGroup()
        for w in missing {
            group.enter()
            Self.fetch(w) { result in
                lock.lock(); fetched[w] = result; lock.unlock()
                group.leave()
            }
        }
        group.notify(queue: .main) {
            var offline = false
            for (k, v) in fetched {
                if let v { self.cache[k] = v } else { offline = true }
            }
            if fetched.values.contains(where: { $0 != nil }) { Self.save(self.cache, to: self.cacheURL) }
            for i in words.indices where words[i].candidates.isEmpty && !words[i].franco.isEmpty {
                words[i].candidates = self.candidates(for: words[i].franco) ?? [Self.offline(words[i].franco)]
            }
            completion(Conversion(source: text, words: words, trailing: trailing, offline: offline))
        }
    }

    private func candidates(for core: String) -> [String]? {
        if core.isEmpty { return [] }
        if core.allSatisfy(\.isNumber) && core.count > 1 { return [core] }
        let cached = cache[core]
        if let mine = dictionary[core] { return [mine] + (cached ?? []).filter { $0 != mine } }
        if Self.conjunctions.contains(core) { return ["و"] }
        return cached
    }

    // MARK: Google Input Tools

    static func fetch(_ word: String, completion: @escaping ([String]?) -> Void) {
        var c = URLComponents(string: "https://inputtools.google.com/request")!
        c.queryItems = [.init(name: "text", value: word), .init(name: "itc", value: "ar-t-i0-und"), .init(name: "num", value: "5")]
        var req = URLRequest(url: c.url!)
        req.timeoutInterval = 3
        URLSession.shared.dataTask(with: req) { data, _, _ in completion(data.flatMap(parse)) }.resume()
    }

    // ["SUCCESS",[["enaharda",["انهاردة","انهارده",…],[],{…}]]]
    static func parse(_ data: Data) -> [String]? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [Any],
              root.first as? String == "SUCCESS",
              let seg = (root.last as? [[Any]])?.first, seg.count > 1,
              let list = seg[1] as? [String], !list.isEmpty else { return nil }
        return list
    }

    // MARK: Tokenizing

    struct Token { var leading = "", prefix = "", core = "", suffix = "" }

    /// Written apart in Franco but attached in Arabic: "el beit" → البيت (merged before lookup),
    /// "w ana" → وأنا (و is glued to the next word).
    static let articles: Set<String> = ["el", "il"]
    static let conjunctions: Set<String> = ["w", "we"]

    static func tokenize(_ text: String) -> ([Token], String) {
        var tokens: [Token] = []
        var space = ""
        var word = ""
        func flush() {
            guard !word.isEmpty else { return }
            tokens.append(split(word, leading: space))
            word = ""; space = ""
        }
        for ch in text {
            if ch.isWhitespace { flush(); space.append(ch) } else { word.append(ch) }
        }
        flush()

        var i = 0
        while i + 1 < tokens.count {
            let a = tokens[i], b = tokens[i + 1]
            let joinable = a.suffix.isEmpty && b.prefix.isEmpty && !b.core.isEmpty && b.leading == " "
            if joinable && articles.contains(a.core) {
                tokens[i + 1].core = a.core + b.core
                tokens[i + 1].prefix = a.prefix
                tokens[i + 1].leading = a.leading
                tokens.remove(at: i)
                continue
            }
            if joinable && conjunctions.contains(a.core) { tokens[i + 1].leading = "" }
            i += 1
        }
        return (tokens, space)
    }

    private static func split(_ raw: String, leading: String) -> Token {
        let isCore: (Character) -> Bool = { $0.isLetter || $0.isNumber || $0 == "'" }
        guard let first = raw.firstIndex(where: isCore), let last = raw.lastIndex(where: isCore) else {
            return Token(leading: leading, prefix: punctuation(raw))
        }
        return Token(leading: leading,
                     prefix: punctuation(String(raw[..<first])),
                     core: String(raw[first...last]).lowercased(),
                     suffix: punctuation(String(raw[raw.index(after: last)...])))
    }

    private static func punctuation(_ s: String) -> String {
        s.replacingOccurrences(of: "?", with: "؟").replacingOccurrences(of: ",", with: "،").replacingOccurrences(of: ";", with: "؛")
    }

    // MARK: Offline rules (fallback with no internet)

    static let multi: [(String, String)] = [
        ("3'", "غ"), ("7'", "خ"), ("6'", "ظ"), ("9'", "ض"),
        ("sh", "ش"), ("kh", "خ"), ("gh", "غ"), ("th", "ث"),
        ("aa", "ا"), ("ee", "ي"), ("ii", "ي"), ("oo", "و"), ("ou", "و"), ("uu", "و"),
    ]
    static let letters: [Character: String] = [
        "2": "ء", "3": "ع", "5": "خ", "6": "ط", "7": "ح", "8": "ق", "9": "ص",
        "b": "ب", "p": "ب", "t": "ت", "g": "ج", "j": "ج", "h": "ه", "d": "د", "r": "ر",
        "z": "ز", "s": "س", "f": "ف", "v": "ف", "q": "ق", "k": "ك", "c": "ك", "l": "ل",
        "m": "م", "n": "ن", "w": "و", "y": "ي", "x": "كس", "i": "ي", "o": "و", "u": "و",
    ]
    static let vowels: Set<Character> = ["a", "e", "i", "o", "u"]

    /// Short vowels are mostly dropped like in written Arabic; "a" becomes ا when it's
    /// word-final, before a final consonant (kalam → كلام), or before y/w + consonant (3ayz → عايز).
    static func offline(_ word: String) -> String {
        let chars = Array(word)
        var out = ""
        var i = 0
        while i < chars.count {
            let rest = String(chars[i...])
            if let (k, v) = multi.first(where: { rest.hasPrefix($0.0) }) {
                if i == 0 && vowels.contains(chars[0]) { out += "ا" }
                out += v
                i += k.count
                continue
            }
            let ch = chars[i]
            let tail = chars[(i + 1)...]
            if i == 0 && vowels.contains(ch) {
                out += "ا"
            } else if ch == "a" {
                if tail.isEmpty || isFinalConsonant(tail) || isLongBeforeGlide(tail) { out += "ا" }
            } else if ch == "e" {
                if tail.isEmpty { out += "ه" }
            } else {
                out += letters[ch] ?? String(ch)
            }
            i += 1
        }
        if out.hasPrefix("ء") { out = "أ" + out.dropFirst() }
        return out
    }

    private static func isFinalConsonant(_ tail: ArraySlice<Character>) -> Bool {
        !tail.contains(where: vowels.contains) && (tail.count == 1 || multi.contains { $0.0 == String(tail) })
    }

    private static func isLongBeforeGlide(_ tail: ArraySlice<Character>) -> Bool {
        guard tail.count > 1, let g = tail.first, "yw".contains(g) else { return false }
        return !vowels.contains(tail[tail.startIndex + 1])
    }

    // MARK: Files

    private static func load<T: Decodable>(_ url: URL) -> T? {
        (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }

    private static func save<T: Encodable>(_ value: T, to url: URL) {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try? e.encode(value).write(to: url, options: .atomic)
    }
}
