import SwiftUI
import StickyKit

enum SortOrder: String, CaseIterable { case newest = "Newest", az = "A – Z", top = "Top rated" }
private let allCat = "__all", favCat = "__fav"

/// Movies or TV Shows, as on the Fire TV: the title with the sort beside it, the categories, then the posters.
struct BrowseView: View {
    let kind: Kind
    @EnvironmentObject var library: Library
    @State private var cat = allCat
    @State private var sort = SortOrder.newest
    @State private var items: [AnyHashable] = []

    private var title: String { kind == .movie ? "Movies" : "TV Shows" }
    private var cats: [(String, String)] {
        [(allCat, "All"), (favCat, "★ My list")] + (kind == .movie ? library.movieCategories : library.seriesCategories).map { ($0.id, $0.name) }
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    Text(title.uppercased()).font(.system(size: 20, weight: .black)).foregroundStyle(Nova.text)
                    Text("\(items.count) titles").font(.caption).foregroundStyle(Nova.muted)
                    Spacer().frame(width: 10)
                    Text("Sort").font(.caption).foregroundStyle(Nova.muted)
                    ForEach(SortOrder.allCases, id: \.self) { s in Chip(text: s.rawValue, selected: sort == s) { sort = s } }
                    Spacer()
                }.padding(.horizontal, 16).padding(.top, 6)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) { ForEach(cats, id: \.0) { id, name in Chip(text: name, selected: cat == id) { cat = id } } }
                        .padding(.horizontal, 16).padding(.vertical, 8)
                }
                if items.isEmpty {
                    if library.vodLoading { VStack { Spacer(); ProgressView("Your movies and shows are still arriving…").tint(Nova.accent); Spacer() }.frame(maxWidth: .infinity) }
                    else { EmptyState(title: "Nothing here", body_: cat == favCat ? "Press and hold any title to add it to My list." : "This category is empty."); Spacer() }
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 14)], spacing: 16) {
                            ForEach(items, id: \.self) { item in
                                if let m = item.base as? Movie {
                                    NavigationLink(value: m) { PosterCard(movie: m, progress: progress(Prefs.movieKey(m)), width: 96) }.buttonStyle(.plain)
                                        .contextMenu { favButton(Prefs.movieKey(m)) }
                                } else if let s = item.base as? Series {
                                    NavigationLink(value: s) { PosterCard(series: s, width: 96) }.buttonStyle(.plain)
                                        .contextMenu { favButton(Prefs.seriesKey(s)) }
                                }
                            }
                        }.padding(.horizontal, 16).padding(.bottom, 24)
                    }
                }
            }
            .background(Nova.bg.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Movie.self) { MovieInfoView(movie: $0) }
            .navigationDestination(for: Series.self) { ShowInfoView(series: $0) }
            .task(id: "\(cat)|\(sort.rawValue)|\(library.movies.count)|\(library.series.count)|\(library.favoritesVersion)") { await refresh() }
        }
    }

    @ViewBuilder private func favButton(_ key: String) -> some View {
        Button { library.toggleFavorite(key) } label: {
            library.prefs.isFavorite(key) ? Label("Remove from My list", systemImage: "star.slash") : Label("Add to My list", systemImage: "star")
        }
    }

    private func progress(_ key: String) -> Double {
        let d = library.prefs.duration(key)
        return d > 0 ? library.prefs.position(key) / d : 0
    }

    /// Sorting 50,000 titles happens off the main thread; the previous list stays meanwhile.
    private func refresh() async {
        let favs = Set(library.prefs.favorites)
        let s = sort
        if kind == .movie {
            let base: [Movie] = cat == allCat ? library.movies : cat == favCat ? library.movies.filter { favs.contains(Prefs.movieKey($0)) } : (library.moviesByCat[cat] ?? [])
            let sorted = await Task.detached(priority: .userInitiated) { () -> [Movie] in
                switch s {
                case .newest: return base.sorted { $0.added > $1.added }
                case .az: return base.sorted { cleanTitle($0.name).title.localizedCaseInsensitiveCompare(cleanTitle($1.name).title) == .orderedAscending }
                case .top: return base.sorted { $0.rating > $1.rating }
                }
            }.value
            items = sorted.map { AnyHashable($0) }
        } else {
            let base: [Series] = cat == allCat ? library.series : cat == favCat ? library.series.filter { favs.contains(Prefs.seriesKey($0)) } : (library.seriesByCat[cat] ?? [])
            let sorted = await Task.detached(priority: .userInitiated) { () -> [Series] in
                switch s {
                case .newest: return base.sorted { $0.updated > $1.updated }
                case .az: return base.sorted { cleanTitle($0.name).title.localizedCaseInsensitiveCompare(cleanTitle($1.name).title) == .orderedAscending }
                case .top: return base.sorted { $0.rating > $1.rating }
                }
            }.value
            items = sorted.map { AnyHashable($0) }
        }
    }
}

/// The info pages' background: the picture filling the page, fading to the left and bottom (as on the Fire TV).
struct InfoBackdrop: View {
    let image: String?
    var body: some View {
        ZStack {
            NetImage(url: image, fallback: "")
            LinearGradient(stops: [.init(color: Nova.bg, location: 0.25), .init(color: Nova.bg.opacity(0.6), location: 0.7), .init(color: Nova.bg.opacity(0.2), location: 1)],
                           startPoint: .leading, endPoint: .trailing)
            LinearGradient(stops: [.init(color: .clear, location: 0.5), .init(color: Nova.bg, location: 1)], startPoint: .top, endPoint: .bottom)
        }.ignoresSafeArea()
    }
}

struct MovieInfoView: View {
    let movie: Movie
    @EnvironmentObject var library: Library
    @State private var detail: MovieDetail?
    @State private var playing = false
    @State private var fromStart = false

    var body: some View {
        let k = Prefs.movieKey(movie)
        let pos = library.prefs.position(k)
        let ct = cleanTitle(movie.name)
        ZStack(alignment: .topLeading) {
            InfoBackdrop(image: detail?.backdrop ?? movie.poster)
            ScrollView {
                HStack(alignment: .top, spacing: 24) {
                    NetImage(url: movie.poster, fallback: ct.title).frame(width: 150, height: 225).clipShape(RoundedRectangle(cornerRadius: 14))
                    VStack(alignment: .leading, spacing: 10) {
                        Text(ct.title).font(.system(size: 28, weight: .heavy)).foregroundStyle(Nova.text).lineLimit(2)
                        FlowTags(tags: [detail?.year ?? ct.year, detail?.duration, movie.rating > 0 ? "★ \(String(format: "%.1f", movie.rating))" : nil,
                                        detail?.genre?.split(separator: ",").first.map { $0.trimmingCharacters(in: .whitespaces) }])
                        if let p = detail?.plot { Text(p).font(.subheadline).foregroundStyle(Nova.text.opacity(0.85)).lineLimit(5) }
                        if let c = detail?.cast { Text("Starring  \(c)").font(.caption).foregroundStyle(Nova.muted).lineLimit(2) }
                        if let d = detail?.director { Text("Director  \(d)").font(.caption).foregroundStyle(Nova.muted).lineLimit(1) }
                        HStack(spacing: 12) {
                            NeonButton(title: pos > 0 ? "Resume \(minutesText(pos))" : "Play", icon: "play.fill") { fromStart = false; playing = true }
                            if pos > 0 { NeonButton(title: "Start over", icon: "gobackward", primary: false) { fromStart = true; playing = true } }
                            let fav = library.prefs.isFavorite(k)
                            NeonButton(title: fav ? "In My list" : "My list", icon: fav ? "star.fill" : "star", primary: false) { library.toggleFavorite(k) }
                        }.padding(.top, 6)
                    }.frame(maxWidth: 480, alignment: .leading)
                    Spacer(minLength: 0)
                }.padding(.horizontal, 24).padding(.top, 44).padding(.bottom, 24)
            }
            BackButton().padding(.leading, 20).padding(.top, 8)
        }
        .toolbar(.hidden, for: .navigationBar)
        .task(id: movie.id) { detail = try? await library.movieDetail(movie) }
        .fullScreenCover(isPresented: $playing) {
            if let url = library.movieURL(movie) {
                VodPlayer(url: url, key: k, title: ct.title, prefs: library.prefs, fromStart: fromStart).ignoresSafeArea()
            }
        }
    }
}

struct ShowInfoView: View {
    let series: Series
    @EnvironmentObject var library: Library
    @State private var detail: SeriesDetail?
    @State private var failed = false
    @State private var season: Int?
    @State private var playingEp: Episode?

    var body: some View {
        let k = Prefs.seriesKey(series)
        let seasons = (detail?.seasons.keys.sorted()) ?? []
        let sel = season ?? seasons.first
        let eps = sel.flatMap { detail?.seasons[$0] } ?? []
        let all = seasons.flatMap { detail?.seasons[$0] ?? [] }
        let resume = all.last { library.prefs.position(Prefs.episodeKey($0)) > 0 }
        ZStack(alignment: .topLeading) {
            InfoBackdrop(image: detail?.backdrop ?? series.backdrop ?? series.cover)
            HStack(alignment: .top, spacing: 20) {
                // left: the show
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(cleanTitle(series.name).title).font(.system(size: 26, weight: .heavy)).foregroundStyle(Nova.text).lineLimit(2)
                        FlowTags(tags: [detail?.year ?? series.year, seasons.isEmpty ? nil : "\(seasons.count) season\(seasons.count > 1 ? "s" : "")",
                                        series.rating > 0 ? "★ \(String(format: "%.1f", series.rating))" : nil])
                        if let p = detail?.plot ?? series.plot { Text(p).font(.subheadline).foregroundStyle(Nova.text.opacity(0.85)).lineLimit(6) }
                        if let target = resume ?? all.first {
                            NeonButton(title: resume != nil ? "Resume S\(target.season) E\(target.number)" : "Play S\(target.season) E\(target.number)", icon: "play.fill") { playingEp = target }
                        }
                        let fav = library.prefs.isFavorite(k)
                        NeonButton(title: fav ? "In My list" : "My list", icon: fav ? "star.fill" : "star", primary: false) { library.toggleFavorite(k) }
                        if failed { Text("Couldn't load episodes. Try again later.").font(.footnote).foregroundStyle(Nova.live) }
                        if detail == nil && !failed { ProgressView("Loading episodes…").tint(Nova.accent) }
                    }.padding(.top, 44)
                }.frame(width: 300)
                // right: seasons and episodes
                VStack(alignment: .leading, spacing: 8) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) { ForEach(seasons, id: \.self) { n in Chip(text: "Season \(n)", selected: n == sel) { season = n } } }
                    }
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(eps) { e in
                                Button { playingEp = e } label: { EpisodeRow(episode: e, cover: series.cover, prefs: library.prefs) }.buttonStyle(.plain)
                            }
                        }.padding(.bottom, 16)
                    }
                }.padding(.top, 30)
            }.padding(.horizontal, 24)
            BackButton().padding(.leading, 20).padding(.top, 8)
        }
        .toolbar(.hidden, for: .navigationBar)
        .task(id: series.id) {
            do { detail = try await library.seriesDetail(series) } catch { failed = true }
        }
        .fullScreenCover(item: $playingEp) { e in
            if let url = library.episodeURL(e) {
                VodPlayer(url: url, key: Prefs.episodeKey(e), title: "\(cleanTitle(series.name).title) S\(e.season) E\(e.number)", prefs: library.prefs).ignoresSafeArea()
            }
        }
    }
}

struct EpisodeRow: View {
    let episode: Episode
    let cover: String?
    let prefs: Prefs
    var body: some View {
        let k = Prefs.episodeKey(episode)
        let pos = prefs.position(k), dur = prefs.duration(k)
        HStack(spacing: 12) {
            NetImage(url: episode.image ?? cover, fallback: episode.title).frame(width: 112, height: 63).clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(alignment: .bottom) { if pos > 0, dur > 0 { ProgressBar(value: pos / dur).padding(4) } }
            VStack(alignment: .leading, spacing: 3) {
                Text("\(episode.number). \(episode.title)").font(.subheadline.bold()).foregroundStyle(Nova.text).lineLimit(1)
                if let p = episode.plot { Text(p).font(.caption).foregroundStyle(Nova.muted).lineLimit(2) }
                if episode.durationSecs > 0 { Text(minutesText(Double(episode.durationSecs))).font(.caption2).foregroundStyle(Nova.faint) }
            }
            Spacer(minLength: 0)
        }.padding(8).background(Nova.panel.opacity(0.9), in: RoundedRectangle(cornerRadius: 12))
    }
}

/// The big rounded buttons of the Fire TV app (cyan for the main one).
struct NeonButton: View {
    let title: String
    let icon: String
    var primary = true
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon).font(.subheadline.bold()).lineLimit(1)
                .padding(.horizontal, 18).padding(.vertical, 11)
                .foregroundStyle(primary ? Color.black : Nova.text)
                .background(primary ? Nova.accent : Nova.panel, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(primary ? .clear : Nova.line))
        }.buttonStyle(.plain)
    }
}

struct FlowTags: View {
    let tags: [String?]
    var body: some View {
        HStack(spacing: 6) { ForEach(tags.compactMap { $0 }, id: \.self) { t in Tag(text: t, color: t.hasPrefix("★") ? Nova.gold : Nova.text) } }
    }
}
