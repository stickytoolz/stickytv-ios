import Foundation

/// A provider login (Xtream Codes).
public struct Account: Codable, Hashable, Identifiable {
    public var name: String
    public var server: String
    public var username: String
    public var password: String
    public var id: String { "\(username)@\(server)" }
    public init(name: String, server: String, username: String, password: String) {
        self.name = name; self.server = server; self.username = username; self.password = password
    }
}

public struct AccountInfo: Codable, Hashable {
    public var status: String
    public var expires: Date?            // nil = never
    public var maxConnections: Int
    public var activeConnections: Int
    public var isTrial: Bool
    public var timezone: String?
}

public enum Kind: String, Codable { case live, movie, series }

public struct Category: Codable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var kind: Kind
    public init(id: String, name: String, kind: Kind) { self.id = id; self.name = name; self.kind = kind }
}

public struct Channel: Codable, Hashable, Identifiable {
    public var id: Int
    public var num: Int
    public var name: String
    public var logo: String?
    public var epgId: String?
    public var categoryId: String
    public var hasArchive: Bool
    public init(id: Int, num: Int, name: String, logo: String?, epgId: String?, categoryId: String, hasArchive: Bool) {
        self.id = id; self.num = num; self.name = name; self.logo = logo; self.epgId = epgId; self.categoryId = categoryId; self.hasArchive = hasArchive
    }
}

public struct Movie: Codable, Hashable, Identifiable {
    public var id: Int
    public var name: String
    public var poster: String?
    public var rating: Double
    public var added: Int64
    public var categoryId: String
    public var ext: String
    public var tmdb: Int = 0
    public init(id: Int, name: String, poster: String?, rating: Double, added: Int64, categoryId: String, ext: String, tmdb: Int = 0) {
        self.id = id; self.name = name; self.poster = poster; self.rating = rating; self.added = added; self.categoryId = categoryId; self.ext = ext; self.tmdb = tmdb
    }
}

public struct Series: Codable, Hashable, Identifiable {
    public var id: Int
    public var name: String
    public var cover: String?
    public var backdrop: String?
    public var plot: String?
    public var genre: String?
    public var year: String?
    public var rating: Double
    public var categoryId: String
    public var updated: Int64
    public var tmdb: Int = 0
    public init(id: Int, name: String, cover: String?, backdrop: String?, plot: String?, genre: String?, year: String?, rating: Double,
                categoryId: String, updated: Int64, tmdb: Int = 0) {
        self.id = id; self.name = name; self.cover = cover; self.backdrop = backdrop; self.plot = plot; self.genre = genre; self.year = year
        self.rating = rating; self.categoryId = categoryId; self.updated = updated; self.tmdb = tmdb
    }
}

public struct MovieDetail: Codable, Hashable {
    public var plot: String?
    public var cast: String?
    public var director: String?
    public var genre: String?
    public var year: String?
    public var duration: String?
    public var backdrop: String?
    public var tmdb: Int = 0
    public var trailer: String?         // YouTube video id
}

public struct Episode: Codable, Hashable, Identifiable {
    public var id: String
    public var season: Int
    public var number: Int
    public var title: String
    public var plot: String?
    public var image: String?
    public var durationSecs: Int
    public var ext: String
}

public struct SeriesDetail: Codable, Hashable {
    public var plot: String?
    public var cast: String?
    public var genre: String?
    public var year: String?
    public var backdrop: String?
    public var seasons: [Int: [Episode]]
    public var tmdb: Int = 0
    public var trailer: String?
}

/// A programme on a channel. Times already shifted by the user's guide offset.
public struct Program: Codable, Hashable {
    public var title: String
    public var desc: String?
    public var start: Date
    public var end: Date
    public var category: String?
    public init(title: String, desc: String?, start: Date, end: Date, category: String? = nil) {
        self.title = title; self.desc = desc; self.start = start; self.end = end; self.category = category
    }
    public func isLive(_ now: Date) -> Bool { now >= start && now < end }
    public func progress(_ now: Date) -> Double {
        let total = max(end.timeIntervalSince(start), 1)
        return min(max(now.timeIntervalSince(start) / total, 0), 1)
    }
}
