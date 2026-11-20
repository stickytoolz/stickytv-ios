import Foundation

/// Settings and personal lists (logins, favourites, recently watched, resume points), kept in UserDefaults.
public final class Prefs {
    let d: UserDefaults
    public init(defaults: UserDefaults = .standard) { d = defaults }

    private func codable<T: Codable>(_ key: String) -> T? { d.data(forKey: key).flatMap { try? JSONDecoder().decode(T.self, from: $0) } }
    private func setCodable<T: Codable>(_ key: String, _ v: T?) { if let v, let data = try? JSONEncoder().encode(v) { d.set(data, forKey: key) } else { d.removeObject(forKey: key) } }

    // logins
    public var accounts: [Account] { get { codable("accounts") ?? [] } set { setCodable("accounts", newValue) } }
    public var activeAccountId: String? { get { d.string(forKey: "activeAccount") } set { d.set(newValue, forKey: "activeAccount") } }
    public var activeAccount: Account? { accounts.first { $0.id == activeAccountId } ?? accounts.first }
    public func saveAccount(_ a: Account) {
        var list = accounts.filter { $0.id != a.id }
        list.insert(a, at: 0)
        accounts = list
        activeAccountId = a.id
    }
    public func removeAccount(_ a: Account) {
        accounts = accounts.filter { $0.id != a.id }
        if activeAccountId == a.id { activeAccountId = accounts.first?.id }
    }

    // favourites ("live:12", "movie:5", "series:9"), in the order added
    public var favorites: [String] { get { d.stringArray(forKey: "favorites") ?? [] } set { d.set(newValue, forKey: "favorites") } }
    public func isFavorite(_ key: String) -> Bool { favorites.contains(key) }
    @discardableResult public func toggleFavorite(_ key: String) -> Bool {
        var f = favorites
        if let i = f.firstIndex(of: key) { f.remove(at: i); favorites = f; return false }
        f.append(key); favorites = f; return true
    }

    // recently watched channels (newest first, 20 kept)
    public var recentChannels: [Int] { get { (d.array(forKey: "recentChannels") as? [Int]) ?? [] } set { d.set(Array(newValue.prefix(20)), forKey: "recentChannels") } }
    public func watched(_ channelId: Int) { recentChannels = [channelId] + recentChannels.filter { $0 != channelId } }
    public var lastChannel: Int { get { d.object(forKey: "lastChannel") as? Int ?? -1 } set { d.set(newValue, forKey: "lastChannel") } }

    // resume points for movies and episodes (seconds)
    public func position(_ key: String) -> Double { d.double(forKey: "pos." + key) }
    public func duration(_ key: String) -> Double { d.double(forKey: "dur." + key) }
    public func savePosition(_ key: String, _ pos: Double, _ dur: Double) {
        // nearly finished counts as watched: start over next time
        if dur > 0 && pos > dur - 60 { d.removeObject(forKey: "pos." + key) } else { d.set(pos, forKey: "pos." + key) }
        if dur > 0 { d.set(dur, forKey: "dur." + key) }
    }

    // My Teams: their games come first on Sports and Home
    public var myTeams: [Team] { get { codable("myTeams") ?? [] } set { setCodable("myTeams", newValue) } }
    public func toggleTeam(_ t: Team) {
        var list = myTeams
        if let i = list.firstIndex(where: { $0.key == t.key }) { list.remove(at: i) } else { list.append(t) }
        myTeams = list
    }

    /// Categories hidden from the lists ("live:12", "movie:3", "series:4").
    public var hiddenCategories: Set<String> { get { Set(d.stringArray(forKey: "hiddenCats") ?? []) } set { d.set(Array(newValue), forKey: "hiddenCats") } }
    /// Home rows turned off (see HomeRow in the app).
    public var hiddenHomeRows: Set<String> { get { Set(d.stringArray(forKey: "hiddenHomeRows") ?? []) } set { d.set(Array(newValue), forKey: "hiddenHomeRows") } }
    /// Open straight into the last channel when the app starts.
    public var autoplayLast: Bool { get { d.bool(forKey: "autoplayLast") } set { d.set(newValue, forKey: "autoplayLast") } }
    /// Live scores on the game cards (from ESPN).
    public var liveScores: Bool { get { d.object(forKey: "liveScores") as? Bool ?? true } set { d.set(newValue, forKey: "liveScores") } }
    /// Seconds the channel info stays on screen in full-screen live TV.
    public var overlaySecs: Int { get { (d.object(forKey: "overlaySecs") as? Int) ?? 5 } set { d.set(newValue, forKey: "overlaySecs") } }

    /// The player for live TV: "vlc-ts" (VLC with MPEG-TS, what works on the Fire TV — the default), "vlc-hls" (VLC with
    /// HLS) or "apple-hls" (the iPhone's own player with HLS).
    public var playerEngine: String { get { d.string(forKey: "playerEngine") ?? "vlc-ts" } set { d.set(newValue, forKey: "playerEngine") } }
    public static let playerEngines: [(id: String, name: String)] = [("vlc-ts", "VLC · MPEG-TS"), ("vlc-hls", "VLC · HLS"), ("apple-hls", "Apple · HLS")]
    /// The stream format the chosen player asks for.
    public var liveFormat: String { playerEngine == "vlc-ts" ? "ts" : "m3u8" }
    /// Buffer: 0 Low (fast channel changes), 1 Normal (the player decides), 2 High (slow internet).
    public var bufferMode: Int { get { (d.object(forKey: "bufferMode") as? Int) ?? 1 } set { d.set(newValue, forKey: "bufferMode") } }
    /// Weak-signal cushion: after a dropout, save 8, then 15, then 25 seconds ahead before carrying on.
    public var cushion: Bool { get { d.bool(forKey: "cushion") } set { d.set(newValue, forKey: "cushion") } }

    // settings
    public var guideOffsetHours: Int { get { d.integer(forKey: "epgOffsetHours") } set { d.set(newValue, forKey: "epgOffsetHours") } }
    public var clock24: Bool { get { d.bool(forKey: "clock24") } set { d.set(newValue, forKey: "clock24") } }
    public var tmdbKey: String { get { d.string(forKey: "tmdbKey") ?? "" } set { d.set(newValue, forKey: "tmdbKey") } }

    public static func liveKey(_ c: Channel) -> String { "live:\(c.id)" }
    public static func movieKey(_ m: Movie) -> String { "movie:\(m.id)" }
    public static func seriesKey(_ s: Series) -> String { "series:\(s.id)" }
    public static func episodeKey(_ e: Episode) -> String { "ep:\(e.id)" }
}

/// The playlist saved on the phone, so the app opens instantly and refreshes from the provider in the background.
public struct PlaylistData: Codable {
    public var info: AccountInfo?
    public var liveCats: [Category] = []
    public var movieCats: [Category] = []
    public var seriesCats: [Category] = []
    public var channels: [Channel] = []
    public var movies: [Movie] = []
    public var series: [Series] = []
    public var savedAt: Date = Date()
    public init() {}
}

public struct PlaylistCache {
    let file: URL
    public init(account: Account, folder: URL? = nil) {
        let dir = folder ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("playlist")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let name = account.id.unicodeScalars.reduce(UInt32(5381)) { ($0 &* 33) &+ $1.value }
        file = dir.appendingPathComponent("p\(name).json")
    }
    public func read() -> PlaylistData? { (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode(PlaylistData.self, from: $0) } }
    public func write(_ p: PlaylistData) { if let data = try? JSONEncoder().encode(p) { try? data.write(to: file, options: .atomic) } }
    public var age: TimeInterval { ((try? FileManager.default.attributesOfItem(atPath: file.path))?[.modificationDate] as? Date).map { Date().timeIntervalSince($0) } ?? .infinity }
    public func delete() { try? FileManager.default.removeItem(at: file) }
}
