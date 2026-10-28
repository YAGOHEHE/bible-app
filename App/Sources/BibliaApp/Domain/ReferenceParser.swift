import Foundation

/// Port de BOOKS / EXTRA_ALIASES / _norm / resolve_book / REF_RE / parse_reference
/// (jingdu-bible-mcp/server.py, código propio del usuario).
enum ReferenceError: Error, Equatable {
    case unknownBook(String)
    case invalidReference(String)
}

enum ReferenceParser {
    /// (número, inglés, español, chino completo, chino corto)
    static let books: [(Int, String, String, String, String)] = [
        (1, "Genesis", "Génesis", "创世记", "创"), (2, "Exodus", "Éxodo", "出埃及记", "出"),
        (3, "Leviticus", "Levítico", "利未记", "利"), (4, "Numbers", "Números", "民数记", "民"),
        (5, "Deuteronomy", "Deuteronomio", "申命记", "申"), (6, "Joshua", "Josué", "约书亚记", "书"),
        (7, "Judges", "Jueces", "士师记", "士"), (8, "Ruth", "Rut", "路得记", "得"),
        (9, "1 Samuel", "1 Samuel", "撒母耳记上", "撒上"), (10, "2 Samuel", "2 Samuel", "撒母耳记下", "撒下"),
        (11, "1 Kings", "1 Reyes", "列王纪上", "王上"), (12, "2 Kings", "2 Reyes", "列王纪下", "王下"),
        (13, "1 Chronicles", "1 Crónicas", "历代志上", "代上"), (14, "2 Chronicles", "2 Crónicas", "历代志下", "代下"),
        (15, "Ezra", "Esdras", "以斯拉记", "拉"), (16, "Nehemiah", "Nehemías", "尼希米记", "尼"),
        (17, "Esther", "Ester", "以斯帖记", "斯"), (18, "Job", "Job", "约伯记", "伯"),
        (19, "Psalms", "Salmos", "诗篇", "诗"), (20, "Proverbs", "Proverbios", "箴言", "箴"),
        (21, "Ecclesiastes", "Eclesiastés", "传道书", "传"), (22, "Song of Songs", "Cantares", "雅歌", "歌"),
        (23, "Isaiah", "Isaías", "以赛亚书", "赛"), (24, "Jeremiah", "Jeremías", "耶利米书", "耶"),
        (25, "Lamentations", "Lamentaciones", "耶利米哀歌", "哀"), (26, "Ezekiel", "Ezequiel", "以西结书", "结"),
        (27, "Daniel", "Daniel", "但以理书", "但"), (28, "Hosea", "Oseas", "何西阿书", "何"),
        (29, "Joel", "Joel", "约珥书", "珥"), (30, "Amos", "Amós", "阿摩司书", "摩"),
        (31, "Obadiah", "Abdías", "俄巴底亚书", "俄"), (32, "Jonah", "Jonás", "约拿书", "拿"),
        (33, "Micah", "Miqueas", "弥迦书", "弥"), (34, "Nahum", "Nahúm", "那鸿书", "鸿"),
        (35, "Habakkuk", "Habacuc", "哈巴谷书", "哈"), (36, "Zephaniah", "Sofonías", "西番雅书", "番"),
        (37, "Haggai", "Hageo", "哈该书", "该"), (38, "Zechariah", "Zacarías", "撒迦利亚书", "亚"),
        (39, "Malachi", "Malaquías", "玛拉基书", "玛"), (40, "Matthew", "Mateo", "马太福音", "太"),
        (41, "Mark", "Marcos", "马可福音", "可"), (42, "Luke", "Lucas", "路加福音", "路"),
        (43, "John", "Juan", "约翰福音", "约"), (44, "Acts", "Hechos", "使徒行传", "徒"),
        (45, "Romans", "Romanos", "罗马书", "罗"), (46, "1 Corinthians", "1 Corintios", "哥林多前书", "林前"),
        (47, "2 Corinthians", "2 Corintios", "哥林多后书", "林后"), (48, "Galatians", "Gálatas", "加拉太书", "加"),
        (49, "Ephesians", "Efesios", "以弗所书", "弗"), (50, "Philippians", "Filipenses", "腓立比书", "腓"),
        (51, "Colossians", "Colosenses", "歌罗西书", "西"), (52, "1 Thessalonians", "1 Tesalonicenses", "帖撒罗尼迦前书", "帖前"),
        (53, "2 Thessalonians", "2 Tesalonicenses", "帖撒罗尼迦后书", "帖后"), (54, "1 Timothy", "1 Timoteo", "提摩太前书", "提前"),
        (55, "2 Timothy", "2 Timoteo", "提摩太后书", "提后"), (56, "Titus", "Tito", "提多书", "多"),
        (57, "Philemon", "Filemón", "腓利门书", "门"), (58, "Hebrews", "Hebreos", "希伯来书", "来"),
        (59, "James", "Santiago", "雅各书", "雅"), (60, "1 Peter", "1 Pedro", "彼得前书", "彼前"),
        (61, "2 Peter", "2 Pedro", "彼得后书", "彼后"), (62, "1 John", "1 Juan", "约翰一书", "约壹"),
        (63, "2 John", "2 Juan", "约翰二书", "约贰"), (64, "3 John", "3 Juan", "约翰三书", "约叁"),
        (65, "Jude", "Judas", "犹大书", "犹"), (66, "Revelation", "Apocalipsis", "启示录", "启"),
    ]

    static let extraAliases: [String: Int] = [
        "gn": 1, "gen": 1, "ex": 2, "exo": 2, "lv": 3, "lev": 3, "nm": 4, "num": 4, "dt": 5, "deut": 5,
        "jos": 6, "jue": 7, "sal": 19, "ps": 19, "psalm": 19, "pr": 20, "prov": 20, "is": 23, "isa": 23,
        "jer": 24, "ez": 26, "dn": 27, "mt": 40, "mat": 40, "mc": 41, "mr": 41, "mk": 41, "lc": 42, "lk": 42,
        "jn": 43, "jhn": 43, "hch": 44, "ro": 45, "rom": 45, "1co": 46, "2co": 47, "ga": 48, "gal": 48,
        "ef": 49, "eph": 49, "fil": 50, "phil": 50, "col": 51, "heb": 58, "stg": 59, "jas": 59,
        "1p": 60, "1pe": 60, "2p": 61, "2pe": 61, "1jn": 62, "2jn": 63, "3jn": 64, "ap": 66, "apoc": 66,
        "rev": 66, "约翰壹书": 62, "约翰贰书": 63, "约翰叁书": 64, "约一": 62, "约二": 63, "约三": 64,
    ]

    /// minúsculas, sin acentos, sin espacios ni puntos.
    static func norm(_ s: String) -> String {
        let decomposed = s.lowercased().decomposedStringWithCompatibilityMapping
        var out = String.UnicodeScalarView()
        for u in decomposed.unicodeScalars {
            if u.properties.generalCategory == .nonspacingMark { continue }
            if u.properties.isWhitespace || u == "." { continue }
            out.append(u)
        }
        return String(out)
    }

    static let aliases: [String: Int] = {
        var d: [String: Int] = [:]
        for b in books {
            for n in [b.1, b.2, b.3, b.4] { d[norm(n)] = b.0 }
        }
        for (k, v) in extraAliases { d[norm(k)] = v }
        return d
    }()

    static func resolveBook(_ name: String) throws -> Int {
        let key = norm(name)
        if !key.isEmpty, key.allSatisfy({ $0.isASCII && $0.isNumber }), let n = Int(key), (1...66).contains(n) {
            return n
        }
        if let n = aliases[key] { return n }
        if !key.isEmpty {
            let hits = Set(aliases.filter { $0.key.hasPrefix(key) }.map(\.value))
            if hits.count == 1, let n = hits.first { return n }
        }
        throw ReferenceError.unknownBook(name)
    }

    // ^\s*(book.+?)\s*(ch\d+)(?:\s*[:：.,]\s*(v1\d+)(?:\s*[-–~]\s*(v2\d+))?)?\s*$
    private static let refRegex = try! NSRegularExpression(
        pattern: #"^\s*(.+?)\s*(\d+)(?:\s*[:：.,]\s*(\d+)(?:\s*[-–~]\s*(\d+))?)?\s*$"#
    )

    static func parse(_ ref: String) throws -> BibleRef {
        let ns = ref as NSString
        guard let m = refRegex.firstMatch(in: ref, range: NSRange(location: 0, length: ns.length)) else {
            throw ReferenceError.invalidReference(ref)
        }
        func group(_ i: Int) -> String? {
            let r = m.range(at: i)
            return r.location == NSNotFound ? nil : ns.substring(with: r)
        }
        let book = try resolveBook(group(1) ?? "")
        guard let ch = group(2).flatMap({ Int($0) }) else { throw ReferenceError.invalidReference(ref) }
        let v1 = group(3).flatMap { Int($0) }
        let v2 = group(4).flatMap { Int($0) } ?? v1
        return BibleRef(book: book, chapter: ch, verseFrom: v1, verseTo: v2)
    }
}
