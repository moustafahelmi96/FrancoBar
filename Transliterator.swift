import AppKit

struct Word {
    var leading: String      // whitespace before the word, kept as typed
    var prefix: String       // punctuation around the word
    var franco: String       // lowercased lookup key, e.g. "enaharda"
    var original: String     // as typed, e.g. "Install"
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

/// Franco → Arabic. Order per word: your saved words, then English words kept as typed,
/// then cached Google results, then Google Input Tools (5 candidates), then offline rules.
/// The word as typed is always offered as the last alternative.
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
            Word(leading: t.leading, prefix: t.prefix, franco: t.core, original: t.original, suffix: t.suffix, candidates: [])
        }
        let missing = Set(words.map(\.franco).filter { f in
            !f.isEmpty && !Self.isNumber(f) && dictionary[f] == nil && cache[f] == nil && Self.fixed[f] == nil
        })
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
            for i in words.indices { words[i].candidates = self.candidates(for: words[i]) }
            completion(Conversion(source: text, words: words, trailing: trailing, offline: offline))
        }
    }

    private func candidates(for w: Word) -> [String] {
        let f = w.franco
        if f.isEmpty { return [] }
        if Self.isNumber(f) { return [w.original] }
        var list: [String] = []
        if let mine = dictionary[f] { list.append(mine) }
        else if Self.isEnglish(w.original) { list.append(w.original) }
        if let one = Self.fixed[f] { list.append(one) }
        if let better = Self.preferred[f] { list.append(better) }
        // Articles are left alone only before English: "el meeting" → ال meeting
        if f == "el" || f == "il" { list.append("ال") }
        if f == "lel" || f == "lil" { list.append("لل") }
        list += cache[f] ?? []
        if list.isEmpty { list.append(Self.offline(f)) }
        list.append(w.original)
        // A saved "keep in English" entry is stored lowercased; show it the way it was typed.
        list = list.map { $0.lowercased() == f ? w.original : $0 }
        var seen = Set<String>()
        return list.filter { seen.insert($0).inserted }
    }

    /// "el sa3a 5": a number on its own is a number, not خ.
    private static func isNumber(_ f: String) -> Bool { f.allSatisfy(\.isNumber) }

    // MARK: English detection

    /// Franco words of 5+ letters the English spell checker would otherwise accept.
    static let francoWords: Set<String> = [
        "yalla", "bardo", "kont", "keda", "kida", "tayeb", "lessa", "wallah", "walla", "wallahi", "inshallah",
        "habibi", "habiby", "fakes", "mashy", "begad", "lamma", "gamed", "kaman", "haram", "sharia", "madrasa",
        "araby", "sheikh", "laban", "kofta", "kebab", "bared", "aywa", "aiwa", "yaany",
    ]

    /// Up to 4 letters, Franco and English collide all the time (dah, ahh, ya, bas, moot, mesh…),
    /// so short words count as English only if they're on this list of everyday English.
    static let shortEnglish: Set<String> = [
        // 2–3 letters
        "ok", "hi", "app", "bye", "the", "and", "for", "you", "are", "is", "it", "to", "of", "on", "in", "at", "my",
        "me", "so", "up", "if", "or", "but", "not", "all", "can", "how", "why", "who", "our", "out", "now", "too",
        "pc", "ai", "api", "ui", "ux", "cv", "pdf", "url", "web", "bug", "fix", "pr", "job", "gym", "car", "mac",
        "ios", "git", "css", "sql", "aws", "ram", "cpu", "gpu", "usb", "tv", "dm", "vs", "hr", "ceo", "lol", "omg",
        "btw", "eta", "faq", "id", "otp", "sms", "vpn", "yes", "new", "old", "big", "top", "hot", "max", "min",
        "add", "get", "set", "run", "log", "box", "key", "tag", "map", "pin", "dev", "qa", "pm", "am", "kg", "km",
        // 4 letters
        "okay", "will", "just", "also", "with", "this", "that", "from", "have", "what", "when", "then", "more",
        "need", "want", "know", "make", "take", "give", "keep", "find", "only", "your", "they", "them", "were",
        "file", "code", "send", "link", "mail", "call", "task", "team", "test", "game", "plan", "chat",
        "sale", "data", "user", "page", "site", "free", "done", "sure", "cool", "nice", "good", "fine", "best",
        "work", "home", "time", "date", "week", "year", "list", "note", "edit", "save", "copy", "open", "post",
        "like", "live", "show", "help", "info", "demo", "beta", "deal", "cash", "card", "bank", "shop", "food",
        "menu", "room", "flat", "unit", "sign", "push", "pull", "wifi",
        "asap", "zoom", "next", "last", "slot", "spot", "back", "full", "busy", "easy", "fast", "slow", "high",
        "boss", "logo", "font", "icon", "view", "mode", "dark", "item", "cart", "ship", "fees", "rent", "tips",
        "idea", "news", "trip", "club", "golf", "ball", "goal", "move", "stop", "play", "song", "film",
        "deck", "ppt", "doc", "docs", "ipad", "repo", "main", "prod", "host", "port", "line", "text",
    ]

    /// Brands the spell checker doesn't know.
    static let brands: Set<String> = [
        "whatsapp", "instagram", "insta", "facebook", "youtube", "tiktok", "google", "gmail", "linkedin", "netflix",
        "spotify", "uber", "careem", "telegram", "snapchat", "twitter", "github", "figma", "slack", "chatgpt",
        "claude", "iphone", "android", "macbook", "airpods", "playstation", "zoom", "teams", "outlook", "excel",
    ]

    static func isEnglish(_ word: String) -> Bool {
        guard word.count > 1, word.allSatisfy(\.isLetter) else { return false } // digits/apostrophes mean Franco (3, 7, 3')
        // iPhone, API, macOS: capitals after the first letter are a strong English signal.
        if word.dropFirst().contains(where: \.isUppercase) { return true }
        let lower = word.lowercased()
        if brands.contains(lower) { return true }
        if francoWords.contains(lower) || hasTripleLetter(lower) { return false } // ahhh, yaaa
        if lower.count <= 4 { return shortEnglish.contains(lower) }
        let miss = NSSpellChecker.shared.checkSpelling(of: word, startingAt: 0, language: "en", wrap: false,
                                                       inSpellDocumentWithTag: 0, wordCount: nil)
        return miss.location == NSNotFound
    }

    private static func hasTripleLetter(_ s: String) -> Bool {
        let c = Array(s)
        return c.indices.dropFirst(2).contains { c[$0] == c[$0 - 1] && c[$0] == c[$0 - 2] }
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

    struct Token { var leading = "", prefix = "", core = "", original = "", suffix = "" }

    /// Written apart in Franco but attached in Arabic: "el beit" → البيت, "lel beit" → للبيت (merged before lookup),
    /// "w ana" → وأنا, "b el 3arabi" → بالعربي (prefix glued to the next word).
    static let articles: Set<String> = ["el", "il", "lel", "lil"]
    static let prefixes: [String: String] = ["w": "و", "we": "و", "b": "ب", "l": "ل"]
    /// Little words with one right answer, never looked up.
    static let fixed: [String: String] = ["w": "و", "we": "و", "b": "ب", "l": "ل", "fi": "في"]
    /// Everyday words where Google's first guess is wrong (kolo → قوله); its guesses stay as alternatives.
    static let preferred: [String: String] = [
        "kolo": "كله", "kollo": "كله", "kolha": "كلها", "kolohom": "كلهم", "kolena": "كلنا",
        "abl": "قبل", "2abl": "قبل", "ba3d": "بعد", "3ala": "على",
    ]
    /// Contractions Google gets wrong when merged (felbeit → فلبية): split them first, "fel beit" → في البيت.
    static let contractions: [String: [String]] = [
        "fel": ["fi", "el"], "fil": ["fi", "el"], "fl": ["fi", "el"],
        "wel": ["w", "el"], "wil": ["w", "el"],
        "bel": ["b", "el"], "bil": ["b", "el"],
        "3al": ["3ala", "el"],
    ]

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

        tokens = tokens.flatMap { t -> [Token] in
            guard let parts = contractions[t.core] else { return [t] }
            var first = t, second = t
            first.core = parts[0]; first.original = parts[0]; first.suffix = ""
            second.core = parts[1]; second.original = parts[1]; second.prefix = ""; second.leading = " "
            return [first, second]
        }

        var i = 0
        while i + 1 < tokens.count {
            let a = tokens[i], b = tokens[i + 1]
            let joinable = a.suffix.isEmpty && b.prefix.isEmpty && !b.core.isEmpty && b.leading == " " && !isEnglish(b.original)
            if joinable && articles.contains(a.core) {
                tokens[i + 1].core = a.core + b.core
                tokens[i + 1].original = a.original + " " + b.original
                tokens[i + 1].prefix = a.prefix
                tokens[i + 1].leading = a.leading
                tokens.remove(at: i)
                continue
            }
            // A prefix also attaches to an English word's article: "w el zoom" → وال zoom.
            let attaches = a.suffix.isEmpty && b.prefix.isEmpty && b.leading == " " && (!isEnglish(b.original) || articles.contains(b.core))
            if attaches && prefixes[a.core] != nil { tokens[i + 1].leading = "" }
            i += 1
        }
        return (tokens, space)
    }

    private static func split(_ raw: String, leading: String) -> Token {
        let isCore: (Character) -> Bool = { $0.isLetter || $0.isNumber || $0 == "'" }
        guard let first = raw.firstIndex(where: isCore), let last = raw.lastIndex(where: isCore) else {
            return Token(leading: leading, prefix: punctuation(raw))
        }
        let core = String(raw[first...last])
        return Token(leading: leading,
                     prefix: punctuation(String(raw[..<first])),
                     core: core.lowercased(),
                     original: core,
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
