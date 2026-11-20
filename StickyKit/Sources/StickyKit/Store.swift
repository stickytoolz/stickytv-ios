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
