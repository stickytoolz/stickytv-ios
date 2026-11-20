import Foundation

public struct StickyError: LocalizedError {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

/// Talks to an Xtream Codes compatible panel (same rules as the Fire TV app).
public final class XtreamAPI {
    public let account: Account
    public let base: String
    let userAgent: String
    let session: URLSession

    public static let defaultAgent = "IPTVSmartersPro"

    public init(account: Account, userAgent: String = XtreamAPI.defaultAgent, session: URLSession? = nil) {
        self.account = account
        self.base = XtreamAPI.normalizeServer(account.server)
        self.userAgent = userAgent
        self.session = session ?? {
            let c = URLSessionConfiguration.default
            c.timeoutIntervalForRequest = 60
            c.timeoutIntervalForResource = 300
            c.httpMaximumConnectionsPerHost = 4
            return URLSession(configuration: c)
        }()
    }

    // MARK: addresses

    func api(_ action: String? = nil, _ extra: [(String, String)] = []) -> URL {
        var c = URLComponents(string: "\(base)/player_api.php")!
        var q = [URLQueryItem(name: "username", value: account.username), URLQueryItem(name: "password", value: account.password)]
        if let action { q.append(URLQueryItem(name: "action", value: action)) }
        q += extra.map { URLQueryItem(name: $0.0, value: $0.1) }
        c.queryItems = q
        return c.url!
    }

    private func seg(_ s: String) -> String { s.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?#"))) ?? s }

    /// "m3u8" (HLS, what iPhones play) or "ts".
    public func liveURL(_ id: Int, format: String = "m3u8") -> URL { URL(string: "\(base)/live/\(seg(account.username))/\(seg(account.password))/\(id).\(format)")! }
    public func movieURL(_ m: Movie) -> URL { URL(string: "\(base)/movie/\(seg(account.username))/\(seg(account.password))/\(m.id).\(m.ext)")! }
    public func episodeURL(_ e: Episode) -> URL { URL(string: "\(base)/series/\(seg(account.username))/\(seg(account.password))/\(e.id).\(e.ext)")! }
    public func xmltvURL() -> URL {
        var c = URLComponents(string: "\(base)/xmltv.php")!
        c.queryItems = [URLQueryItem(name: "username", value: account.username), URLQueryItem(name: "password", value: account.password)]
        return c.url!
    }

    /// Accepts "host:port", "http://host:port/", or a pasted get.php / player_api.php link.
    public static func normalizeServer(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if !s.lowercased().hasPrefix("http://") && !s.lowercased().hasPrefix("https://") { s = "http://" + s }
        guard let u = URLComponents(string: s), let host = u.host, !host.isEmpty else { return s.trimmingCharacters(in: CharacterSet(charactersIn: "/")) }
        let port = u.port.map { ":\($0)" } ?? ""
        var path = u.path
        while path.hasSuffix("/") { path.removeLast() }
        // keep a panel sub-folder ("http://host/panel"), drop a pasted file name (get.php, player_api.php, ...)
        if let last = path.split(separator: "/").last, last.contains(".") {
            path = String(path[..<path.index(path.endIndex, offsetBy: -last.count - 1)])
        }
        return "\((u.scheme ?? "http").lowercased())://\(host)\(port)\(path)"
    }

    /// If someone pastes a full M3U link, pull the login out of it.
    public static func parseM3uLink(_ raw: String) -> Account? {
        guard let u = URLComponents(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              let user = u.queryItems?.first(where: { $0.name == "username" })?.value,
              let pass = u.queryItems?.first(where: { $0.name == "password" })?.value else { return nil }
        return Account(name: u.host ?? "Server", server: normalizeServer(raw), username: user, password: pass)
    }

    // MARK: fetching

    func get(_ url: URL, json: Bool = true) async throws -> Data {
        var req = URLRequest(url: url)
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let (data, resp) = try await session.data(for: req)
        if let h = resp as? HTTPURLResponse, !(200..<300).contains(h.statusCode) { throw StickyError("Server answered \(h.statusCode)") }
        if json, let first = data.first(where: { !($0 == 0x20 || $0 == 0x0A || $0 == 0x0D || $0 == 0x09 || $0 == 0xEF || $0 == 0xBB || $0 == 0xBF) }),
           first != UInt8(ascii: "["), first != UInt8(ascii: "{") {
            throw StickyError("the server sent a web page instead of data")
        }
        return data
    }

    /// Tries again (after 1 s, then 3 s) when the panel fails, times out or sends a web page instead of data.
    func retrying<T>(_ what: String, _ block: () async throws -> T) async throws -> T {
        var last: Error?
        for attempt in 0..<3 {
            if attempt > 0 { try await Task.sleep(nanoseconds: attempt == 1 ? 1_000_000_000 : 3_000_000_000) }
            do { return try await block() } catch is CancellationError { throw CancellationError() } catch { last = error }
        }
        throw StickyError("Couldn't load \(what) (\(last?.localizedDescription ?? "no answer")). Try again in a minute.")
    }

    /// The items of a list the panel sent as an array, or as an object of objects.
    static func objects(_ data: Data) -> [JSONObj] {
        guard let any = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else { return [] }
        if let a = any as? [Any] { return a.compactMap { $0 as? JSONObj } }
        if let o = any as? JSONObj { return o.values.compactMap { $0 as? JSONObj } }
        return []
    }
    static func object(_ data: Data) -> JSONObj { (try? JSONSerialization.jsonObject(with: data)) as? JSONObj ?? [:] }

    public func login() async throws -> AccountInfo {
        let data = try await retrying("your account") { try await get(api(), json: false) }
        guard let o = (try? JSONSerialization.jsonObject(with: data)) as? JSONObj else { throw StickyError("This doesn't look like an Xtream server. Check the URL.") }
        guard let u = o.obj("user_info"), ["1", "true", "1.0"].contains(u.str("auth") ?? "") else { throw StickyError("Wrong username or password.") }
        let status = u.str("status") ?? "Active"
        if status.lowercased() != "active" { throw StickyError("Account is \(status).") }
        return AccountInfo(
            status: status,
            expires: (u.str("exp_date").flatMap { Double($0) }).flatMap { $0 > 0 ? Date(timeIntervalSince1970: $0) : nil },
            maxConnections: wholeNumber(u.str("max_connections")) ?? 1,
            activeConnections: wholeNumber(u.str("active_cons")) ?? 0,
            isTrial: u.str("is_trial") == "1",
            timezone: o.obj("server_info")?.str("timezone"))
    }

    public func categories(_ kind: Kind) async throws -> [Category] {
        let action = switch kind { case .live: "get_live_categories"; case .movie: "get_vod_categories"; case .series: "get_series_categories" }
        let data = try await retrying("categories") { try await get(api(action)) }
        var seen = Set<String>()
        return XtreamAPI.objects(data).compactMap { o -> Category? in
            guard let raw = o.str("category_id") else { return nil }
            let id = catId(raw)
            guard seen.insert(id).inserted else { return nil }
            return Category(id: id, name: cleanName(o.str("category_name")) ?? "Other", kind: kind)
        }
    }

    public func channels() async throws -> [Channel] {
        let data = try await retrying("channels") { try await get(api("get_live_streams")) }
        return XtreamAPI.parseChannels(data)
    }

    static func parseChannels(_ data: Data) -> [Channel] {
        var seen = Set<Int>()
        return objects(data).compactMap { o in
            guard let id = wholeNumber(o.str("stream_id")), seen.insert(id).inserted else { return nil }
            return Channel(id: id, num: max(wholeNumber(o.str("num")) ?? 0, 0), name: cleanName(o.str("name")) ?? "Channel \(id)",
                           logo: o.str("stream_icon").flatMap { $0.hasPrefix("http") ? $0 : nil },
                           epgId: o.str("epg_channel_id"), categoryId: catId(o.str("category_id")),
                           hasArchive: ["1", "true"].contains(o.str("tv_archive") ?? ""))
        }
    }

    public func movies() async throws -> [Movie] {
        let data = try await retrying("movies") { try await get(api("get_vod_streams")) }
        return XtreamAPI.parseMovies(data)
    }

    static func parseMovies(_ data: Data) -> [Movie] {
        var seen = Set<Int>()
        return objects(data).compactMap { o in
            guard let id = wholeNumber(o.str("stream_id")), seen.insert(id).inserted else { return nil }
            let ext = o.str("container_extension").flatMap { (2...5).contains($0.count) && $0.allSatisfy { $0.isLetter || $0.isNumber } ? $0 : nil } ?? "mp4"
            return Movie(id: id, name: cleanName(o.str("name")) ?? "Movie \(id)", poster: o.str("stream_icon").flatMap { $0.hasPrefix("http") ? $0 : nil },
                         rating: o.str("rating").flatMap(Double.init).flatMap { (0...10).contains($0) ? $0 : nil } ?? 0,
                         added: Int64(o.str("added") ?? "") ?? 0, categoryId: catId(o.str("category_id")), ext: ext,
                         tmdb: tmdbId(o.str("tmdb") ?? o.str("tmdb_id")))
        }
    }

    public func series() async throws -> [Series] {
        let data = try await retrying("shows") { try await get(api("get_series")) }
        return XtreamAPI.parseSeries(data)
    }

    static func parseSeries(_ data: Data) -> [Series] {
        var seen = Set<Int>()
        return objects(data).compactMap { o in
            guard let id = wholeNumber(o.str("series_id")), seen.insert(id).inserted else { return nil }
            let y = (o.str("releaseDate") ?? o.str("release_date")).map { String($0.prefix(4)) }.flatMap { $0.count == 4 && $0.allSatisfy(\.isNumber) ? $0 : nil }
            return Series(id: id, name: cleanName(o.str("name")) ?? "Series \(id)", cover: o.str("cover").flatMap { $0.hasPrefix("http") ? $0 : nil },
                          backdrop: o.firstImage("backdrop_path"), plot: o.str("plot"), genre: o.str("genre"), year: y,
                          rating: o.str("rating").flatMap(Double.init).flatMap { (0...10).contains($0) ? $0 : nil } ?? 0,
                          categoryId: catId(o.str("category_id")), updated: Int64(o.str("last_modified") ?? "") ?? 0,
                          tmdb: tmdbId(o.str("tmdb") ?? o.str("tmdb_id")))
        }
    }

    public func movieDetail(_ id: Int) async throws -> MovieDetail {
        let o = XtreamAPI.object(try await retrying("the movie details") { try await get(api("get_vod_info", [("vod_id", String(id))])) })
        let i = o.obj("info") ?? [:]
        return MovieDetail(plot: i.str("plot") ?? i.str("description"), cast: i.str("cast") ?? i.str("actors"), director: i.str("director"),
                           genre: i.str("genre"), year: (i.str("releasedate") ?? i.str("release_date")).map { String($0.prefix(4)) },
                           duration: i.str("duration"), backdrop: i.firstImage("backdrop_path") ?? i.str("movie_image"),
                           tmdb: tmdbId(i.str("tmdb_id") ?? i.str("tmdb") ?? o.obj("movie_data")?.str("tmdb_id")),
                           trailer: youtubeId(i.str("youtube_trailer") ?? i.str("trailer")))
    }

    public func seriesDetail(_ id: Int) async throws -> SeriesDetail {
        let o = XtreamAPI.object(try await retrying("the episodes") { try await get(api("get_series_info", [("series_id", String(id))])) })
        return XtreamAPI.parseSeriesDetail(o)
    }

    static func parseSeriesDetail(_ o: JSONObj) -> SeriesDetail {
        let i = o.obj("info") ?? [:]
        var seasons: [Int: [Episode]] = [:]
        func add(_ e: JSONObj, _ seasonKey: Int) {
            let info = e.obj("info") ?? [:]
            let s = wholeNumber(e.str("season")) ?? seasonKey
            guard let rawId = e.str("id") else { return }
            let epId = Double(rawId).map { String(Int64($0)) } ?? rawId
            let ext = e.str("container_extension").flatMap { (2...5).contains($0.count) ? $0 : nil } ?? "mp4"
            seasons[s, default: []].append(Episode(id: epId, season: s, number: wholeNumber(e.str("episode_num")) ?? 0, title: cleanName(e.str("title")) ?? "Episode",
                                                   plot: info.str("plot"), image: info.str("movie_image").flatMap { $0.hasPrefix("http") ? $0 : nil },
                                                   durationSecs: wholeNumber(info.str("duration_secs")) ?? 0, ext: ext))
        }
        switch o["episodes"] {
        case let eps as JSONObj:
            for (k, v) in eps {
                let key = Int(k) ?? 1
                if let list = v as? [Any] { list.compactMap { $0 as? JSONObj }.forEach { add($0, key) } }
                else if let m = v as? JSONObj { m.values.compactMap { $0 as? JSONObj }.forEach { add($0, key) } }
            }
        case let eps as [Any]:
            for (n, item) in eps.enumerated() {
                if let list = item as? [Any] { list.compactMap { $0 as? JSONObj }.forEach { add($0, n + 1) } }
                else if let e = item as? JSONObj { add(e, 1) }
            }
        default: break
        }
        var clean: [Int: [Episode]] = [:]
        for (s, list) in seasons where !list.isEmpty {
            var seen = Set<String>()
            clean[s] = list.filter { seen.insert($0.id).inserted }.sorted { $0.number < $1.number }
        }
        return SeriesDetail(plot: i.str("plot"), cast: i.str("cast"), genre: i.str("genre"),
                            year: (i.str("releaseDate") ?? i.str("release_date")).map { String($0.prefix(4)) },
                            backdrop: i.firstImage("backdrop_path") ?? i.str("cover"), seasons: clean,
                            tmdb: tmdbId(i.str("tmdb") ?? i.str("tmdb_id")), trailer: youtubeId(i.str("youtube_trailer") ?? i.str("trailer")))
    }
}
