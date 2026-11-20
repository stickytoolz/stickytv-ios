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

    public private(set) var api: XtreamAPI?
    private var loadTask: Task<Void, Never>?

    public init(prefs: Prefs = Prefs()) { self.prefs = prefs }

    public func load(_ account: Account, force: Bool = false) {
        loadTask?.cancel()
        let api = XtreamAPI(account: account)
        self.api = api
        let cache = PlaylistCache(account: account)
        if !force, let saved = cache.read() { apply(saved); state = .ready }
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
        loadTask?.cancel()
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

    private func applyLive(_ cats: [Category], _ chs: [Channel]) {
        let ids = Set(cats.map(\.id))
        let byCat = Dictionary(grouping: chs, by: \.categoryId)
        liveCategories = cats.filter { !(byCat[$0.id]?.isEmpty ?? true) }
        channels = chs.filter { ids.isEmpty || ids.contains($0.categoryId) || cats.isEmpty }
        channelsByCat = byCat
    }

    private func applyVod(_ mc: [Category], _ sc: [Category], _ mv: [Movie], _ se: [Series]) {
        let mBy = Dictionary(grouping: mv, by: \.categoryId)
        let sBy = Dictionary(grouping: se, by: \.categoryId)
        movieCategories = mc.filter { !(mBy[$0.id]?.isEmpty ?? true) }
        seriesCategories = sc.filter { !(sBy[$0.id]?.isEmpty ?? true) }
        movies = mv; series = se; moviesByCat = mBy; seriesByCat = sBy
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

    public func liveURL(_ c: Channel) -> URL? { api?.liveURL(c.id) }
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
}
