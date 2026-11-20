import Foundation

/// Reads an XMLTV guide (the provider's xmltv.php, or a backup guide) and matches it to the playlist, with the
/// Fire TV app's rules: by the provider's guide id first, and by channel name for channels that have none.
public struct GuideResult {
    public var programs: [String: [Program]]          // guide channel id (lower case) → its programmes, in order
    public var nameLinks: [String: String]            // playlist channel name key → guide channel id
    public var channelsSeen = 0
    public var programmesSeen = 0
    public var programmesKept = 0
}

public enum GuideText {
    static func isAZ(_ c: Character) -> Bool { c >= "a" && c <= "z" }
    static func isDigit(_ c: Character) -> Bool { c >= "0" && c <= "9" }
    static func isWord(_ c: Character) -> Bool { isAZ(c) || (c >= "A" && c <= "Z") || isDigit(c) || c == "_" }

    /// Runs of word characters (letters, digits, _).
    static func wordRuns(_ s: String) -> [String] {
        var out: [String] = []; var cur = ""
        for c in s { if isWord(c) { cur.append(c) } else if !cur.isEmpty { out.append(cur); cur = "" } }
        if !cur.isEmpty { out.append(cur) }
        return out
    }
    /// Runs of a–z / 0–9.
    static func alnumRuns(_ s: String) -> [String] {
        var out: [String] = []; var cur = ""
        for c in s { if isAZ(c) || isDigit(c) { cur.append(c) } else if !cur.isEmpty { out.append(cur); cur = "" } }
        if !cur.isEmpty { out.append(cur) }
        return out
    }
    /// "US: ", "UK | ", "[CA] - " at the start, taken off.
    static func dropCountryTag(_ str: String) -> String {
        let s = Array(str); var i = 0
        while i < s.count && s[i].isWhitespace { i += 1 }
        if i < s.count && (s[i] == "[" || s[i] == "(") { i += 1 }
        let a = i
        while i < s.count && isAZ(s[i]) && i - a < 3 { i += 1 }
        if i - a < 2 { return str }
        if i < s.count && isAZ(s[i]) { return str }
        if i < s.count && (s[i] == "]" || s[i] == ")") { i += 1 }
        while i < s.count && s[i].isWhitespace { i += 1 }
        if i >= s.count || (s[i] != ":" && s[i] != "|" && s[i] != "-") { return str }
        i += 1
        while i < s.count && s[i].isWhitespace { i += 1 }
        return String(s[i...])
    }
    static func noAccents(_ s: String) -> String { s.allSatisfy(\.isASCII) ? s : s.folding(options: .diacriticInsensitive, locale: nil) }
    /// Every "(...)" replaced by a space.
    static func withoutBrackets(_ str: String) -> String {
        guard str.contains("(") else { return str }
        let s = Array(str); var out = ""; var i = 0
        while i < s.count {
            if s[i] == "(", let j = s[(i + 1)...].firstIndex(of: ")") { out.append(" "); i = j + 1; continue }
            out.append(s[i]); i += 1
        }
        return out
    }
    /// What's inside the first "(...)" that has something in it.
    static func firstBracketed(_ str: String) -> String? {
        let s = Array(str); var i = s.firstIndex(of: "(")
        while let a = i {
            guard let j = s[(a + 1)...].firstIndex(of: ")") else { return nil }
            if j > a + 1 { return String(s[(a + 1)..<j]) }
            i = s[(a + 1)...].firstIndex(of: "(")
        }
        return nil
    }
    /// A guide id's country ending taken off: "ESPN.HD.us2" → "ESPN.HD".
    static func dropIdCountry(_ str: String) -> String {
        let id = Array(str); var e = id.count
        if e > 0 && isDigit(id[e - 1]) { e -= 1 }
        var k = e
        func letter(_ c: Character) -> Bool { isAZ(c) || (c >= "A" && c <= "Z") }
        while k > 0 && letter(id[k - 1]) && e - k < 3 { k -= 1 }
        if k > 0 && letter(id[k - 1]) { return str }
        let n = e - k
        return (2...3).contains(n) && k > 0 && id[k - 1] == "." ? String(id[..<(k - 1)]) : str
    }
    static func collapseSpaces(_ s: String) -> String {
        var out = ""; var space = false
        for c in s { if c.isWhitespace { space = !out.isEmpty; continue }; if space { out.append(" "); space = false }; out.append(c) }
        return out
    }
}

public enum GuideMatch {
    static let quality: Set<String> = ["fhd", "uhd", "hd", "sd", "4k", "hevc", "h265", "50fps", "60fps", "backup", "vip", "east", "feed"]
    static let filler: Set<String> = ["channel", "network", "tv", "television", "the", "canal", "hd", "uhd", "fhd", "sd", "4k", "east", "feed", "us", "uk", "ca", "and"]
    static let aliases: [String: String] = [
        "hgtv": "homegarden", "hgtvcanada": "homegarden", "tlc": "thelearning", "a e": "ae", "ae": "aande",
        "skysportsmainevent": "skyspmainev", "skysportspremierleague": "skysppl", "skysportsfootball": "skyspfootball",
        "skysportsf1": "skyspf1", "skysportsnews": "skyspnews", "bbcone": "bbc1", "bbctwo": "bbc2", "itv1": "itv",
    ]

    /// Lower-case letters and digits only, country tags and quality words removed: "US| ESPN HD" == "ESPN".
    public static func normalizeName(_ name: String) -> String {
        let n = GuideText.dropCountryTag(name.lowercased()).replacingOccurrences(of: "h.265", with: "h265")
        var out = ""
        for w in GuideText.wordRuns(n) where !quality.contains(w) {
            for c in w where GuideText.isAZ(c) || GuideText.isDigit(c) { out.append(c) }
        }
        return out
    }

    static func words(_ name: String) -> [String] {
        var n = GuideText.noAccents(name.lowercased())
        n = GuideText.dropCountryTag(n).replacingOccurrences(of: "&", with: " ").replacingOccurrences(of: "+", with: " plus ")
        return GuideText.alnumRuns(n).filter { !$0.isEmpty && !($0.count == 1 && $0.first!.isLetter) }
            .map { $0.count > 5 && $0.hasSuffix("hd") ? String($0.dropLast(2)) : $0 }
    }

    /// Keys a playlist channel can be found under.
    public static func keysFor(_ name: String) -> Set<String> {
        let w = words(name)
        let looseJoined = w.filter { !filler.contains($0) }.joined()
        let loose: String? = looseJoined.count >= 3 ? looseJoined : nil
        return Set([normalizeName(name), loose, loose.flatMap { aliases[$0] }].compactMap { $0 }.filter { $0.count >= 2 })
    }

    /// Keys to try for a guide channel, best first (rank 0 = closest).
    static func guideKeys(_ names: [String]) -> [(String, Int)] {
        let main = names.map(GuideText.withoutBrackets)
        let inner = names.compactMap(GuideText.firstBracketed)
        var out: [String: Int] = [:]; var order: [String] = []
        func add(_ k: String?, _ rank: Int) {
            guard let k, !k.isEmpty else { return }
            if let r = out[k] { if rank < r { out[k] = rank } } else { out[k] = rank; order.append(k) }
        }
        let noted = names.map { $0.contains("(") }
        for (i, n) in main.enumerated() { add(normalizeName(n), noted[i] ? 1 : 0) }
        for (i, n) in main.enumerated() { let j = words(n).filter { !filler.contains($0) }.joined(); add(j.count >= 3 ? j : nil, noted[i] ? 2 : 1) }
        for n in inner { add(normalizeName(n), 2); let j = words(n).filter { !filler.contains($0) }.joined(); add(j.count >= 3 ? j : nil, 2) }
        for n in main + inner {
            let w = words(n).filter { !filler.contains($0) }
            var k = w.count - 1
            while k >= 1 {
                let key = w.prefix(k).joined()
                if k >= 2 || key.count >= 5 { add(key, 3) } else if key.count >= 3 { add(key, 4) }
                k -= 1
            }
        }
        return order.map { ($0, out[$0]!) }.sorted { $0.1 < $1.1 }
    }

    /// "ESPN.HD.us2" → "ESPN HD".
    public static func idToName(_ id: String) -> String {
        GuideText.dropIdCountry(id).replacingOccurrences(of: ".", with: " ").replacingOccurrences(of: "_", with: " ")
    }
}

/// XMLTV times: "20261102183000 +0000" (the zone may be missing: UTC then; seconds may be missing).
public func parseXmltvTime(_ raw: String?) -> Date? {
    guard var t = raw?.trimmingCharacters(in: .whitespaces) else { return nil }
    let digits = t.prefix { $0.isNumber }
    if digits.count == 12 { t = String(digits) + "00" + t.dropFirst(12) }
    let a = Array(t)
    guard a.count >= 14, a[0..<14].allSatisfy({ $0 >= "0" && $0 <= "9" }) else { return nil }
    func num(_ r: Range<Int>) -> Int { Int(String(a[r]))! }
    var c = DateComponents()
    c.year = num(0..<4); c.month = num(4..<6); c.day = num(6..<8); c.hour = num(8..<10); c.minute = num(10..<12); c.second = num(12..<14)
    c.timeZone = TimeZone(identifier: "UTC")
    var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
    guard var d = cal.date(from: c) else { return nil }
    let zone = String(a.dropFirst(14)).trimmingCharacters(in: .whitespaces).prefix(5)
    if zone.count == 5, let sign = zone.first, sign == "+" || sign == "-", let hh = Int(zone.dropFirst().prefix(2)), let mm = Int(zone.suffix(2)) {
        let off = Double(hh * 3600 + mm * 60) * (sign == "+" ? 1 : -1)
        d = d.addingTimeInterval(-off)
    }
    return d
}

/// Streams the guide with Foundation's XMLParser (never the whole file in memory as one text).
public final class GuideParser: NSObject, XMLParserDelegate {
    var wanted: Set<String>
    let from: Date, to: Date, offset: TimeInterval
    let names: Set<String>
    var result = GuideResult(programs: [:], nameLinks: [:])
    private var linkRank: [String: Int] = [:]
    private var strings: [String: String] = [:]

    // the element being read
    private var inChannel: String?
    private var shown: [String] = []
    private var progChannel: String?, progStart: Date?, progStop: Date?
    private var title: String?, desc: String?, category: String?
    private var buffer = ""
    private var capture = false

    public init(wanted: Set<String>, from: Date, to: Date, offsetHours: Int = 0, names: Set<String> = []) {
        self.wanted = Set(wanted.map { $0.lowercased() })
        self.from = from; self.to = to; offset = TimeInterval(offsetHours * 3600); self.names = names
    }

    public func parse(_ data: Data) -> GuideResult { finish(XMLParser(data: data)) }
    public func parse(stream: InputStream) -> GuideResult { finish(XMLParser(stream: stream)) }

    private func finish(_ p: XMLParser) -> GuideResult {
        p.delegate = self
        p.shouldProcessNamespaces = false
        p.shouldResolveExternalEntities = false
        _ = p.parse()            // a damaged guide keeps whatever was read before the damage
        for (k, list) in result.programs {
            let sorted = list.sorted { $0.start < $1.start }
            var clean: [Program] = []
            for pr in sorted {
                if let last = clean.last, last.start == pr.start { continue }
                if let last = clean.last, last.end > pr.start { clean[clean.count - 1].end = pr.start }
                if pr.end > pr.start && pr.end.timeIntervalSince(pr.start) < 48 * 3600 { clean.append(pr) }
            }
            result.programs[k] = clean
        }
        return result
    }

    private func intern(_ s: String?) -> String? {
        guard let s else { return nil }
        if let v = strings[s] { return v }
        strings[s] = s; return s
    }

    public func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes a: [String: String] = [:]) {
        switch name {
        case "channel":
            result.channelsSeen += 1
            inChannel = a["id"]; shown = []
        case "display-name" where inChannel != nil:
            buffer = ""; capture = true
        case "programme":
            result.programmesSeen += 1
            let ch = a["channel"]?.lowercased()
            let start = parseXmltvTime(a["start"])
            let stop = parseXmltvTime(a["stop"]) ?? start?.addingTimeInterval(3600)
            if let ch, let start, let stop, wanted.contains(ch), stop.addingTimeInterval(offset) > from, start.addingTimeInterval(offset) < to {
                progChannel = ch; progStart = start; progStop = stop; title = nil; desc = nil; category = nil
            } else { progChannel = nil }
        case "title", "desc", "category":
            if progChannel != nil { buffer = ""; capture = true }
        default: break
        }
    }

    public func parser(_ parser: XMLParser, foundCharacters string: String) { if capture { buffer += string } }
    public func parser(_ parser: XMLParser, foundCDATA data: Data) { if capture, let s = String(data: data, encoding: .utf8) { buffer += s } }

    public func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        switch name {
        case "display-name" where inChannel != nil:
            shown.append(GuideText.collapseSpaces(buffer)); capture = false
        case "channel":
            if let id = inChannel, !names.isEmpty {
                // channels the provider gave no guide id get matched up by name; a closer match found later replaces a looser one
                let lid = id.lowercased()
                if let hit = GuideMatch.guideKeys(shown + [GuideMatch.idToName(id)]).first(where: { names.contains($0.0) && $0.1 < (linkRank[$0.0] ?? 99) }) {
                    result.nameLinks[hit.0] = lid; linkRank[hit.0] = hit.1; wanted.insert(lid)
                }
            }
            inChannel = nil
        case "title" where progChannel != nil:
            if title == nil { title = GuideText.collapseSpaces(buffer) }; capture = false
        case "desc" where progChannel != nil:
            if desc == nil { desc = String(GuideText.collapseSpaces(buffer).prefix(400)) }; capture = false
        case "category" where progChannel != nil:
            if category == nil { category = GuideText.collapseSpaces(buffer) }; capture = false
        case "programme":
            if let ch = progChannel, let s = progStart, let e = progStop {
                result.programmesKept += 1
                var list = result.programs[ch] ?? []
                if list.count < 400 {
                    list.append(Program(title: intern(title) ?? "", desc: desc, start: s.addingTimeInterval(offset), end: e.addingTimeInterval(offset), category: intern(category)))
                    result.programs[ch] = list
                }
            }
            progChannel = nil
        default: break
        }
    }
}
