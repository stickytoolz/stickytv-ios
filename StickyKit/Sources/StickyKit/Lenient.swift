import Foundation

/// Panels are sloppy about types: every field is read leniently (a string, a number or a boolean; "null" means nothing).
public typealias JSONObj = [String: Any]

extension Dictionary where Key == String, Value == Any {
    /// The field as text, whatever the panel sent; nil for missing, null, "" or "null".
    func str(_ key: String) -> String? {
        switch self[key] {
        case let s as String:
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty || t == "null" ? nil : t
        case let n as NSNumber:
            // booleans come through as NSNumber too
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return n.boolValue ? "true" : "false" }
            return n.stringValue
        default: return nil
        }
    }
    func obj(_ key: String) -> JSONObj? { self[key] as? JSONObj }

    /// The first http picture of a field that may be a list or a single address (backdrop_path).
    func firstImage(_ key: String) -> String? {
        switch self[key] {
        case let a as [Any]: return a.compactMap { $0 as? String }.first { $0.hasPrefix("http") }
        case let s as String: return s.hasPrefix("http") ? s : nil
        default: return nil
        }
    }
}

/// A whole number from "12", 12, "12.0" or 12.0; nil for "", "abc", nil.
func wholeNumber(_ s: String?) -> Int? {
    guard let t = s?.trimmingCharacters(in: .whitespaces), !t.isEmpty else { return nil }
    if let i = Int(t) { return i }
    if let d = Double(t), d == d.rounded(), abs(d) < 2e9 { return Int(d) }
    return nil
}

/// A category id: "12.0" → "12"; anything else as it is.
func catId(_ s: String?) -> String {
    guard let t = s?.trimmingCharacters(in: .whitespaces) else { return "" }
    if let d = Double(t), d == d.rounded(), abs(d) < 9e15 { return String(Int64(d)) }
    return t
}

/// A TMDB id from the provider ("12345", "12345.0"; anything else is 0).
public func tmdbId(_ s: String?) -> Int {
    guard let t = s?.trimmingCharacters(in: .whitespaces) else { return 0 }
    let head = t.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? t
    guard let n = Int(head), n > 0 else { return 0 }
    return n
}

/// The YouTube video id from a provider's trailer field: a bare id, a watch link, a youtu.be or embed link.
public func youtubeId(_ s: String?) -> String? {
    guard let t = s?.trimmingCharacters(in: .whitespaces), !t.isEmpty, t.lowercased() != "null" else { return nil }
    var rest = t
    if let r = t.range(of: "v=") { rest = String(t[r.upperBound...]) }
    else if let r = t.range(of: "youtu.be/") { rest = String(t[r.upperBound...]) }
    else if let r = t.range(of: "/embed/") { rest = String(t[r.upperBound...]) }
    let id = String(rest.prefix { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" })
    return (8...16).contains(id.count) ? id : nil
}

/// Control characters and runs of white space made one space, ends trimmed. Names can be blank, "null" or absurdly long.
public func cleanName(_ s: String?) -> String? {
    guard let s else { return nil }
    var out = ""
    out.reserveCapacity(s.count)
    var space = false
    for ch in s.unicodeScalars {
        if ch.value < 0x20 || ch.value == 0x7F || CharacterSet.whitespacesAndNewlines.contains(ch) { space = !out.isEmpty; continue }
        if space { out.append(" "); space = false }
        out.unicodeScalars.append(ch)
    }
    if out.isEmpty || out.lowercased() == "null" { return nil }
    return out.count > 120 ? String(out.prefix(117)) + "…" : out
}
