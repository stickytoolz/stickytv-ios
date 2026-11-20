import Foundation

/// A provider's movie or show name, tidied for posters: "EN - The Matrix (1999) [4K]" → "The Matrix", 1999, 4K.
public struct CleanTitle: Hashable {
    public let title: String
    public let year: String?
    public let quality: String?
}

private let cleanCache = NSCache<NSString, Box>()
private final class Box { let v: CleanTitle; init(_ v: CleanTitle) { self.v = v } }

public func cleanTitle(_ raw: String) -> CleanTitle {
    if let b = cleanCache.object(forKey: raw as NSString) { return b.v }
    let v = TitleTidy.tidy(raw)
    cleanCache.setObject(Box(v), forKey: raw as NSString)
    return v
}

/// Letter by letter, the same rules as the Fire TV app.
enum TitleTidy {
    static let tags: Set<String> = ["4k", "uhd", "2160p", "fhd", "1080p", "hd", "720p", "sd", "hevc", "x265", "multi", "sub", "dub"]
    static let q4k: Set<String> = ["4k", "uhd", "2160p"]
    static let qhd: Set<String> = ["fhd", "1080p", "hd", "720p"]

    static func isW(_ c: Character) -> Bool { c.isASCII && (c.isLetter || c.isNumber || c == "_") }
    static func isL(_ c: Character) -> Bool { c.isASCII && c.isLetter }
    static func isWs(_ c: Character) -> Bool { c == " " || c == "\t" || c == "\n" || c == "\u{0B}" || c == "\u{0C}" || c == "\r" }
    static func isDigit(_ c: Character) -> Bool { c >= "0" && c <= "9" }
    static func yearAt(_ t: [Character], _ i: Int) -> Bool {
        i + 4 <= t.count && ((t[i] == "1" && t[i + 1] == "9") || (t[i] == "2" && t[i + 1] == "0")) && isDigit(t[i + 2]) && isDigit(t[i + 3])
    }
    static func bracketYear(_ t: [Character], _ i: Int) -> Bool {
        (t[i] == "(" || t[i] == "[") && yearAt(t, i + 1) && i + 5 < t.count && (t[i + 5] == ")" || t[i + 5] == "]")
    }
    static func isSep(_ c: Character) -> Bool { c == "-" || c == ":" || c == "|" }

    /// "|EN|" or "EN - " at the start (two or three letters, then - : or |, then a space).
    static func dropLang(_ t: [Character]) -> [Character] {
        if t.count >= 4 && t[0] == "|" {
            var i = 1
            while i < t.count && isL(t[i]) && i - 1 < 3 { i += 1 }
            if (2...3).contains(i - 1) && i < t.count && t[i] == "|" { return Array(t[(i + 1)...]) }
        }
        var i = 0
        while i < t.count && isL(t[i]) && i < 3 { i += 1 }
        if i < 2 { return t }
        var j = i
        while j < t.count && isWs(t[j]) { j += 1 }
        if j >= t.count || !isSep(t[j]) {
            if i == 3 {
                var k = 2
                while k < t.count && isWs(t[k]) { k += 1 }
                if k < t.count && isSep(t[k]) && k + 1 < t.count && isWs(t[k + 1]) {
                    var e = k + 1
                    while e < t.count && isWs(t[e]) { e += 1 }
                    return Array(t[e...])
                }
            }
            return t
        }
        if j + 1 >= t.count || !isWs(t[j + 1]) { return t }
        var e = j + 1
        while e < t.count && isWs(t[e]) { e += 1 }
        return Array(t[e...])
    }

    static func findYear(_ t: [Character]) -> String? {
        for i in t.indices {
            if bracketYear(t, i) { return String(t[(i + 1)..<(i + 5)]) }
            if isWs(t[i]) && i + 5 == t.count && yearAt(t, i + 1) { return String(t[(i + 1)..<(i + 5)]) }
        }
        return nil
    }

    static func dropYears(_ t: [Character]) -> [Character] {
        var out: [Character] = []; out.reserveCapacity(t.count)
        var i = 0
        while i < t.count {
            if bracketYear(t, i) { out.append(" "); i += 6; continue }
            if isWs(t[i]) && i + 5 == t.count && yearAt(t, i + 1) { out.append(" "); i += 5; continue }
            out.append(t[i]); i += 1
        }
        return out
    }

    static func dropTags(_ t: [Character]) -> [Character] {
        var out: [Character] = []; out.reserveCapacity(t.count)
        var i = 0
        while i < t.count {
            if isW(t[i]) && (i == 0 || !isW(t[i - 1])) {
                var e = i
                while e < t.count && isW(t[e]) { e += 1 }
                if tags.contains(String(t[i..<e]).lowercased()) {
                    if let last = out.last, last == "(" || last == "[", i > 0, t[i - 1] == "(" || t[i - 1] == "[" { out.removeLast() }
                    out.append(" ")
                    i = (e < t.count && (t[e] == ")" || t[e] == "]")) ? e + 1 : e
                    continue
                }
                out.append(contentsOf: t[i..<e]); i = e; continue
            }
            out.append(t[i]); i += 1
        }
        return out
    }

    static func hasWord(_ t: [Character], _ set: Set<String>) -> Bool {
        var i = 0
        while i < t.count {
            if !isW(t[i]) { i += 1; continue }
            var e = i
            while e < t.count && isW(t[e]) { e += 1 }
            if set.contains(String(t[i..<e]).lowercased()) { return true }
            i = e
        }
        return false
    }

    static func collapse(_ t: [Character]) -> String {
        var s = ""; var sp = false
        for c in t {
            if isWs(c) { sp = true; continue }
            if sp && !s.isEmpty { s.append(" ") }
            sp = false; s.append(c)
        }
        return s
    }

    static func tidy(_ raw: String) -> CleanTitle {
        var t = dropLang(Array(raw.trimmingCharacters(in: .whitespacesAndNewlines)))
        let year = findYear(t)
        let q: String? = hasWord(t, q4k) ? "4K" : hasWord(t, qhd) ? "HD" : nil
        t = dropTags(dropYears(t))
        var s = collapse(t).trimmingCharacters(in: .whitespaces)
        while let l = s.last, isSep(l) { s.removeLast() }
        s = s.trimmingCharacters(in: .whitespaces)
        return CleanTitle(title: s.isEmpty ? raw : s, year: year, quality: q)
    }
}
