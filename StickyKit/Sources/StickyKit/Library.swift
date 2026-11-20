import Foundation
import Combine

public enum LoadState: Equatable {
    case idle, loading(String), ready, failed(String)
}

/// Everything the screens show: the account, categories, channels, movies and shows. Opens from the saved copy
/// straight away, then refreshes from the provider in the background (like the Fire TV app).
@MainActor
public final class Library: ObservableObject {
    public let prefs: Prefs
    @Published public private(set) var state: LoadState = .idle
    @Published public private(set) var info: AccountInfo?
    @Published public private(set) var liveCategories: [Category] = []
    @Published public private(set) var movieCategories: [Category] = []
    @Published public private(set) var seriesCategories: [Category] = []
    @Published public private(set) var channels: [Channel] = []
    @Published public private(set) var movies: [Movie] = []
    @Published public private(set) var series: [Series] = []
    @Published public private(set) var channelsByCat: [String: [Channel]] = [:]
    @Published public private(set) var moviesByCat: [String: [Movie]] = [:]
    @Published public private(set) var seriesByCat: [String: [Series]] = [:]
    @Published public private(set) var vodLoading = false
    @Published public var favoritesVersion = 0           // bumps when favourites change, so lists redraw
    /// The TV guide: what's on each channel. guideVersion bumps when it changes; guideStatus says what it's doing.
    @Published public private(set) var guideVersion = 0
    @Published public private(set) var guideStatus: String?
    private var programs: [String: [Program]] = [:]
    private var nameLinks: [String: String] = [:]
    private var guideTask: Task<Void, Never>?

    public private(set) var api: XtreamAPI?
    private var loadTask: Task<Void, Never>?

    public init(prefs: Prefs = Prefs()) { self.prefs = prefs }

    public func load(_ account: Account, force: Bool = false) {
        loadTask?.cancel()
        let api = XtreamAPI(account: account)
        self.api = api
        let cache = PlaylistCache(account: account)
        if !force, let saved = cache.read() { apply(saved); state = .ready; openSavedGuide(account) }
        else { state = .loading("Signing in…") }
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                // a fresh copy (under 6 hours old) is good enough to open with; refresh quietly anyway
                let info = try await api.login()
                var p = PlaylistData()
                p.info = info
                if self.channels.isEmpty { self.state = .loading("Loading channels…") }
                async let lc = api.categories(.live)
                async let ch = api.channels()
                p.liveCats = try await lc
                p.channels = try await ch
                self.info = info
                self.applyLive(p.liveCats, p.channels)
                self.state = .ready
                self.loadGuide(account: account)
                // movies and shows after: live TV is ready to watch meanwhile
                self.vodLoading = true
                async let mc = api.categories(.movie)
                async let sc = api.categories(.series)
                async let mv = api.movies()
                async let se = api.series()
                p.movieCats = (try? await mc) ?? self.movieCategories
                p.seriesCats = (try? await sc) ?? self.seriesCategories
                p.movies = (try? await mv) ?? self.movies
                p.series = (try? await se) ?? self.series
                if Task.isCancelled { return }
                self.applyVod(p.movieCats, p.seriesCats, p.movies, p.series)
                self.vodLoading = false
                p.savedAt = Date()
                let toSave = p
                Task.detached(priority: .utility) { cache.write(toSave) }
            } catch is CancellationError {
            } catch {
                self.vodLoading = false
                // with a saved copy on screen, a failed refresh is quiet; with nothing, say what went wrong
                if self.channels.isEmpty { self.state = .failed(error.localizedDescription) }
            }
        }
    }

    public func signOut() {
        loadTask?.cancel(); guideTask?.cancel()
        programs = [:]; nameLinks = [:]; guideStatus = nil
        api = nil; info = nil
        liveCategories = []; movieCategories = []; seriesCategories = []
        channels = []; movies = []; series = []
        channelsByCat = [:]; moviesByCat = [:]; seriesByCat = [:]
        state = .idle
    }

    private func apply(_ p: PlaylistData) {
        info = p.info
        applyLive(p.liveCats, p.channels)
        applyVod(p.movieCats, p.seriesCats, p.movies, p.series)
    }

    /// Every category the provider has (hidden ones too), for Settings › Hide & unhide.
    @Published public private(set) var allLiveCategories: [Category] = []
    @Published public private(set) var allMovieCategories: [Category] = []
    @Published public private(set) var allSeriesCategories: [Category] = []
    private var rawChannels: [Channel] = [], rawMovies: [Movie] = [], rawSeries: [Series] = []

    private func applyLive(_ cats: [Category], _ chs: [Channel]) {
        let hidden = prefs.hiddenCategories
        let byCatAll = Dictionary(grouping: chs, by: \.categoryId)
        allLiveCategories = cats.filter { !(byCatAll[$0.id]?.isEmpty ?? true) }
        rawChannels = chs
        liveCategories = allLiveCategories.filter { !hidden.contains("live:\($0.id)") }
        channels = chs.filter { !hidden.contains("live:\($0.categoryId)") }
        channelsByCat = Dictionary(grouping: channels, by: \.categoryId)
    }

    private func applyVod(_ mc: [Category], _ sc: [Category], _ mv: [Movie], _ se: [Series]) {
        let hidden = prefs.hiddenCategories
        let mAll = Dictionary(grouping: mv, by: \.categoryId)
        let sAll = Dictionary(grouping: se, by: \.categoryId)
        allMovieCategories = mc.filter { !(mAll[$0.id]?.isEmpty ?? true) }
        allSeriesCategories = sc.filter { !(sAll[$0.id]?.isEmpty ?? true) }
        rawMovies = mv; rawSeries = se
        movieCategories = allMovieCategories.filter { !hidden.contains("movie:\($0.id)") }
        seriesCategories = allSeriesCategories.filter { !hidden.contains("series:\($0.id)") }
        movies = mv.filter { !hidden.contains("movie:\($0.categoryId)") }
        series = se.filter { !hidden.contains("series:\($0.categoryId)") }
        moviesByCat = Dictionary(grouping: movies, by: \.categoryId)
        seriesByCat = Dictionary(grouping: series, by: \.categoryId)
    }

    /// Hide or show a category ("live:12", "movie:3", "series:4") everywhere.
    public func toggleHidden(_ key: String) {
        var h = prefs.hiddenCategories
        if h.contains(key) { h.remove(key) } else { h.insert(key) }
        prefs.hiddenCategories = h
        applyLive(allLiveCategories, rawChannels)
        applyVod(allMovieCategories, allSeriesCategories, rawMovies, rawSeries)
    }

    // MARK: lists

    public func favoriteChannels() -> [Channel] {
        let favs = prefs.favorites
        let byId = Dictionary(channels.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return favs.compactMap { k in k.hasPrefix("live:") ? Int(k.dropFirst(5)).flatMap { byId[$0] } : nil }
    }
    public func recentChannels() -> [Channel] {
        let byId = Dictionary(channels.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return prefs.recentChannels.compactMap { byId[$0] }
    }
    public func toggleFavorite(_ key: String) { prefs.toggleFavorite(key); favoritesVersion += 1 }

    public func liveURL(_ c: Channel, format: String = "ts") -> URL? { api?.liveURL(c.id, format: format) }
    public func movieURL(_ m: Movie) -> URL? { api?.movieURL(m) }
    public func episodeURL(_ e: Episode) -> URL? { api?.episodeURL(e) }
    public func movieDetail(_ m: Movie) async throws -> MovieDetail {
        guard let api else { throw StickyError("Not signed in") }
        return try await api.movieDetail(m.id)
    }
    public func seriesDetail(_ s: Series) async throws -> SeriesDetail {
        guard let api else { throw StickyError("Not signed in") }
        return try await api.seriesDetail(s.id)
    }

    // MARK: TV guide

    private struct SavedGuide: Codable { var programs: [String: [Program]]; var nameLinks: [String: String]; var savedAt: Date }
    private func guideFile(_ a: Account) -> URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("guide")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let name = a.id.unicodeScalars.reduce(UInt32(5381)) { ($0 &* 33) &+ $1.value }
        return dir.appendingPathComponent("g\(name).json")
    }

    /// The guide saved last time, straight away (refreshed in the background after the channels load).
    private func openSavedGuide(_ a: Account) {
        let file = guideFile(a)
        Task.detached(priority: .userInitiated) {
            guard let data = try? Data(contentsOf: file), let g = try? JSONDecoder().decode(SavedGuide.self, from: data) else { return }
            await MainActor.run { [weak self] in
                guard let self, self.programs.isEmpty else { return }
                self.programs = g.programs; self.nameLinks = g.nameLinks; self.guideVersion += 1
            }
        }
    }

    /// Downloads the provider's guide (xmltv.php) and reads it in the background: 2 hours back to 24 hours ahead,
    /// only the channels in the playlist (by guide id, or by name for channels with none).
    public func loadGuide(account: Account? = nil, force: Bool = false) {
        guard let api, let a = account ?? prefs.activeAccount else { return }
        let file = guideFile(a)
        let age = ((try? FileManager.default.attributesOfItem(atPath: file.path))?[.modificationDate] as? Date).map { Date().timeIntervalSince($0) } ?? .infinity
        if !force && age < 6 * 3600 && !programs.isEmpty { return }
        guideTask?.cancel()
        let chs = channels
        let wanted = Set(chs.compactMap { $0.epgId?.lowercased() })
        let names = Set(chs.filter { $0.epgId == nil }.flatMap { GuideMatch.keysFor($0.name) })
        let offset = prefs.guideOffsetHours
        guideStatus = programs.isEmpty ? "Loading the TV guide…" : "Updating the TV guide…"
        guideTask = Task { [weak self] in
            do {
                var req = URLRequest(url: api.xmltvURL(), timeoutInterval: 300)
                req.setValue(XtreamAPI.defaultAgent, forHTTPHeaderField: "User-Agent")
                let (tmp, resp) = try await URLSession.shared.download(for: req)
                if let h = resp as? HTTPURLResponse, !(200..<300).contains(h.statusCode) { throw StickyError("The guide server answered \(h.statusCode)") }
                let now = Date()
                let result: GuideResult = try await Task.detached(priority: .utility) {
                    let parser = GuideParser(wanted: wanted, from: now.addingTimeInterval(-2 * 3600), to: now.addingTimeInterval(24 * 3600), offsetHours: offset, names: names)
                    if let gz = try? Data(contentsOf: tmp, options: .mappedIfSafe), gz.count > 2, gz[gz.startIndex] == 0x1f, gz[gz.startIndex + 1] == 0x8b {
                        guard let plain = gunzip(gz) else { throw StickyError("The guide couldn't be unpacked") }
                        return parser.parse(plain)
                    }
                    guard let stream = InputStream(url: tmp) else { throw StickyError("The guide couldn't be read") }
                    return parser.parse(stream: stream)
                }.value
                try? FileManager.default.removeItem(at: tmp)
                guard let self, !Task.isCancelled else { return }
                if result.programs.isEmpty && !self.programs.isEmpty { self.guideStatus = nil; return }    // keep the old one
                self.programs = result.programs; self.nameLinks = result.nameLinks; self.guideVersion += 1
                self.guideStatus = result.programs.isEmpty ? "Your provider's TV guide is empty" : nil
                let saved = SavedGuide(programs: result.programs, nameLinks: result.nameLinks, savedAt: Date())
                Task.detached(priority: .utility) { if let d = try? JSONEncoder().encode(saved) { try? d.write(to: file, options: .atomic) } }
            } catch is CancellationError {
            } catch {
                self?.guideStatus = self?.programs.isEmpty == true ? "Couldn't load the TV guide (\(error.localizedDescription))" : nil
            }
        }
    }

    /// A channel's programmes: by its guide id, or the guide channel its name was matched to.
    public func programs(for c: Channel) -> [Program] {
        if let id = c.epgId?.lowercased(), let p = programs[id] { return p }
        for k in GuideMatch.keysFor(c.name) { if let id = nameLinks[k], let p = programs[id] { return p } }
        return []
    }

    /// What's on now, and next.
    public func nowNext(_ c: Channel, at now: Date = Date()) -> (now: Program?, next: Program?) {
        let list = programs(for: c)
        guard let i = list.firstIndex(where: { $0.end > now }) else { return (nil, nil) }
        let cur = list[i].start <= now ? list[i] : nil
        let next = cur == nil ? list[i] : (i + 1 < list.count ? list[i + 1] : nil)
        return (cur, next)
    }

    // MARK: sports

    @Published public private(set) var games: [Game] = []
    @Published public private(set) var scoresUpdated: Date?
    @Published public private(set) var scoresLoading = false
    @Published public var teamsVersion = 0

    /// Today's games in every league, from ESPN (all at once; a league that fails is just left out).
    public func refreshScores() async {
        if scoresLoading { return }
        scoresLoading = true
        defer { scoresLoading = false }
        let found: [Game] = await withTaskGroup(of: [Game].self) { group in
            for l in League.all {
                group.addTask {
                    guard let r = try? await URLSession.shared.data(from: Sports.scoreboardURL(l)),
                          (r.1 as? HTTPURLResponse)?.statusCode == 200 else { return [] }
                    return Sports.parseScoreboard(r.0, league: l)
                }
            }
            var all: [Game] = []
            for await g in group { all += g }
            return all
        }
        if !found.isEmpty || games.isEmpty { games = found }
        scoresUpdated = Date()
    }

    /// What's on now on every channel that has a guide (worked out once, for matching games to channels).
    public func nowTitles(at now: Date = Date()) -> [Int: String] {
        var out: [Int: String] = [:]
        for c in channels { if let t = nowNext(c, at: now).now?.title { out[c.id] = t } }
        return out
    }

    /// The channels showing a game, best first.
    public func channels(for g: Game, nowTitles: [Int: String]) -> [Channel] {
        Sports.channels(for: g, in: channels) { nowTitles[$0.id] }
    }

    /// Every team of every league, for the My Teams picker (fetched once, when the picker opens).
    @Published public private(set) var allTeams: [Team] = []
    @Published public private(set) var teamsLoading = false
    public func loadTeams() async {
        if !allTeams.isEmpty || teamsLoading { return }
        teamsLoading = true
        defer { teamsLoading = false }
        let found: [Team] = await withTaskGroup(of: [Team].self) { group in
            for l in League.all where l.sport != "mma" {
                group.addTask {
                    guard let r = try? await URLSession.shared.data(from: Sports.teamsURL(l)), (r.1 as? HTTPURLResponse)?.statusCode == 200 else { return [] }
                    return Sports.parseTeams(r.0, league: l)
                }
            }
            var all: [Team] = []
            for await t in group { all += t }
            return all
        }
        allTeams = found
    }

    /// Your teams' coming games (from their season schedules; refreshed every few hours or when the teams change).
    @Published public private(set) var teamSchedule: [Game] = []
    private var scheduleFor: Set<String> = []
    private var scheduleAt = Date.distantPast

    public func refreshSchedules(force: Bool = false) async {
        let teams = prefs.myTeams
        let ids = Set(teams.map(\.key))
        if ids.isEmpty { teamSchedule = []; scheduleFor = []; return }
        if !force && ids == scheduleFor && Date().timeIntervalSince(scheduleAt) < 3 * 3600 { return }
        let found: [Game] = await withTaskGroup(of: [Game].self) { group in
            for t in teams {
                guard let url = Sports.scheduleURL(t), let l = League.all.first(where: { $0.id == t.league }) else { continue }
                group.addTask {
                    guard let r = try? await URLSession.shared.data(from: url), (r.1 as? HTTPURLResponse)?.statusCode == 200 else { return [] }
                    return Sports.parseScoreboard(r.0, league: l)
                }
            }
            var all: [Game] = []
            for await g in group { all += g }
            return all
        }
        var seen = Set<String>()
        teamSchedule = found.filter { seen.insert($0.id).inserted }
        scheduleFor = ids; scheduleAt = Date()
    }

    /// My Teams games to show: on now and coming up (today's live scores where ESPN has them), soonest first.
    public func myTeamGames() -> [Game] {
        let mine = myTeamIds
        let today = games.filter { mine.contains($0.home.key) || mine.contains($0.away.key) }
        let todayIds = Set(today.map(\.id))
        let merged = today.filter { $0.state != .post } + teamSchedule.filter { !todayIds.contains($0.id) }
        let up = Sports.upcoming(merged, teams: mine)
        return up.sorted { ($0.state == .live ? 0 : 1, $0.start) < ($1.state == .live ? 0 : 1, $1.start) }
    }

    public func toggleTeam(_ t: Team) {
        prefs.toggleTeam(t); teamsVersion += 1
        Task { await refreshSchedules(force: true) }
    }
    /// Your teams, by Team.key (the same club in every competition).
    public var myTeamIds: Set<String> { Set(prefs.myTeams.map(\.key)) }
}

/// Unpacks a .gz file (guides are often sent gzipped).
func gunzip(_ data: Data) -> Data? {
    let b = [UInt8](data)
    guard b.count > 18, b[0] == 0x1f, b[1] == 0x8b, b[2] == 8 else { return nil }
    let flags = b[3]
    var i = 10
    if flags & 4 != 0 { guard i + 2 <= b.count else { return nil }; i += 2 + Int(b[i]) + Int(b[i + 1]) << 8 }   // extra field
    if flags & 8 != 0 { while i < b.count && b[i] != 0 { i += 1 }; i += 1 }                                     // file name
    if flags & 16 != 0 { while i < b.count && b[i] != 0 { i += 1 }; i += 1 }                                    // comment
    if flags & 2 != 0 { i += 2 }                                                                                // header check
    guard i < b.count - 8 else { return nil }
    let deflated = Data(b[i..<(b.count - 8)])
    return try? (deflated as NSData).decompressed(using: .zlib) as Data
}