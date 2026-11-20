import SwiftUI
import StickyKit

enum SortOrder: String, CaseIterable { case newest = "Newest", az = "A – Z", top = "Top rated" }
private let allCat = "__all", favCat = "__fav"

/// Movies or TV Shows: the categories, the sort (it sorts the category you're in), and the posters.
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
            VStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) { ForEach(cats, id: \.0) { id, name in Chip(text: name, selected: cat == id) { cat = id } } }
                        .padding(.horizontal, 16).padding(.top, 6)
                }
                HStack(spacing: 8) {
                    Text("\(items.count) titles").font(.caption).foregroundStyle(Nova.muted)
                    Spacer()
                    Menu {
                        ForEach(SortOrder.allCases, id: \.self) { s in Button { sort = s } label: { if s == sort { Label(s.rawValue, systemImage: "checkmark") } else { Text(s.rawValue) } } }
                    } label: {
                        Label(sort.rawValue, systemImage: "arrow.up.arrow.down").font(.caption.bold())
                    }
                }.padding(.horizontal, 16).padding(.vertical, 8)
                if items.isEmpty {
                    if library.vodLoading { Spacer(); ProgressView("Your movies and shows are still arriving…").tint(Nova.accent); Spacer() }
                    else { EmptyState(title: "Nothing here", body_: cat == favCat ? "Press and hold any title to add it to My list." : "This category is empty."); Spacer() }
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 12)], spacing: 16) {
                            ForEach(items, id: \.self) { item in
                                if let m = item.base as? Movie {
                                    NavigationLink(value: m) { PosterCard(movie: m, progress: progress(Prefs.movieKey(m)), width: 104) }.buttonStyle(.plain)
                                        .contextMenu { favButton(Prefs.movieKey(m)) }
                                } else if let s = item.base as? Series {
                                    NavigationLink(value: s) { PosterCard(series: s, width: 104) }.buttonStyle(.plain)
                                        .contextMenu { favButton(Prefs.seriesKey(s)) }
                                }
                            }
                        }.padding(.horizontal, 16).padding(.bottom, 24)
                    }
                }
            }
            .background(Nova.bg.ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
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
        if kind == .movie {
            let base: [Movie] = cat == allCat ? library.movies : cat == favCat ? library.movies.filter { favs.contains(Prefs.movieKey($0)) } : (library.moviesByCat[cat] ?? [])
            let s = sort
            let sorted = await Task.detached(priority: .userInitiated) { () -> [Movie] in
                switch s {
                case .newest: return base.sorted { $0.added > $1.added }
                case .az: return base.sorted { cleanTitle($0.name).title.localizedCaseInsensitiveCompare(cleanTitle($1.name).title) == .orderedAscending }
                case .top: return base.sorted { $0.rating > $1.rating }
                }
            }.value
            items = sorted.map(AnyHashable.init)
        } else {
            let base: [Series] = cat == allCat ? library.series : cat == favCat ? library.series.filter { favs.contains(Prefs.seriesKey($0)) } : (library.seriesByCat[cat] ?? [])
            let s = sort
            let sorted = await Task.detached(priority: .userInitiated) { () -> [Series] in
                switch s {
                case .newest: return base.sorted { $0.updated > $1.updated }
                case .az: return base.sorted { cleanTitle($0.name).title.localizedCaseInsensitiveCompare(cleanTitle($1.name).title) == .orderedAscending }
                case .top: return base.sorted { $0.rating > $1.rating }
                }
            }.value
            items = sorted.map(AnyHashable.init)
        }
    }
}

/// The big picture behind an info page, fading into the background.
struct InfoBackdrop: View {
    let image: String?
    var body: some View {
        GeometryReader { g in
            NetImage(url: image, fallback: "").frame(width: g.size.width, height: 300).clipped()
                .overlay(LinearGradient(colors: [Nova.bg.opacity(0.1), Nova.bg], startPoint: .top, endPoint: .bottom))
        }.frame(height: 300)
    }
}

struct MovieInfoView: View {
    let movie: Movie
    @EnvironmentObject var library: Library
    @State private var detail: MovieDetail?
    @State private var playing: Bool = false
    @State private var fromStart = false

    var body: some View {
        let k = Prefs.movieKey(movie)
        let pos = library.prefs.position(k)
        let ct = cleanTitle(movie.name)
        ScrollView {
            ZStack(alignment: .top) {
                InfoBackdrop(image: detail?.backdrop ?? movie.poster)
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .bottom, spacing: 16) {
                        NetImage(url: movie.poster, fallback: ct.title).frame(width: 120, height: 180).clipShape(RoundedRectangle(cornerRadius: 12))
                        VStack(alignment: .leading, spacing: 8) {
                            Text(ct.title).font(.title2.bold()).lineLimit(3)
                            FlowTags(tags: [detail?.year ?? ct.year, detail?.duration, movie.rating > 0 ? "★ \(String(format: "%.1f", movie.rating))" : nil,
                                            detail?.genre?.split(separator: ",").first.map { $0.trimmingCharacters(in: .whitespaces) }])
                        }
                    }.padding(.top, 150)
                    HStack(spacing: 10) {
                        Button { fromStart = false; playing = true } label: {
                            Label(pos > 0 ? "Resume \(minutesText(pos))" : "Play", systemImage: "play.fill").bold()
                                .frame(maxWidth: .infinity).padding(12).background(Nova.accent, in: RoundedRectangle(cornerRadius: 12)).foregroundStyle(.black)
                        }
                        if pos > 0 {
                            Button { fromStart = true; playing = true } label: {
                                Image(systemName: "gobackward").font(.headline).padding(12).background(Nova.panel, in: RoundedRectangle(cornerRadius: 12))
                            }
                        }
                        favButton(k)
                    }
                    if let p = detail?.plot { Text(p).font(.subheadline).foregroundStyle(Nova.text.opacity(0.85)) }
                    if let c = detail?.cast { Text("Starring  \(c)").font(.caption).foregroundStyle(Nova.muted) }
                    if let d = detail?.director { Text("Director  \(d)").font(.caption).foregroundStyle(Nova.muted) }
                }.padding(.horizontal, 16)
            }
        }
        .background(Nova.bg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .task(id: movie.id) { detail = try? await library.movieDetail(movie) }
        .fullScreenCover(isPresented: $playing) {
            if let url = library.movieURL(movie) {
                VodPlayer(url: url, key: k, title: ct.title, prefs: library.prefs, fromStart: fromStart).ignoresSafeArea()
            }
        }
    }

    private func favButton(_ k: String) -> some View {
        Button { library.toggleFavorite(k) } label: {
            Image(systemName: library.prefs.isFavorite(k) ? "star.fill" : "star").font(.headline)
                .foregroundStyle(library.prefs.isFavorite(k) ? Nova.gold : Nova.text).padding(12).background(Nova.panel, in: RoundedRectangle(cornerRadius: 12))
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
        ScrollView {
            ZStack(alignment: .top) {
                InfoBackdrop(image: detail?.backdrop ?? series.backdrop ?? series.cover)
                VStack(alignment: .leading, spacing: 14) {
                    Text(cleanTitle(series.name).title).font(.title2.bold()).padding(.top, 170)
                    FlowTags(tags: [detail?.year ?? series.year, seasons.isEmpty ? nil : "\(seasons.count) season\(seasons.count > 1 ? "s" : "")",
                                    series.rating > 0 ? "★ \(String(format: "%.1f", series.rating))" : nil])
                    if let p = detail?.plot ?? series.plot { Text(p).font(.subheadline).foregroundStyle(Nova.text.opacity(0.85)) }
                    HStack(spacing: 10) {
                        if let target = resume ?? all.first {
                            Button { playingEp = target } label: {
                                Label(resume != nil ? "Resume S\(target.season) E\(target.number)" : "Play S\(target.season) E\(target.number)", systemImage: "play.fill").bold()
                                    .frame(maxWidth: .infinity).padding(12).background(Nova.accent, in: RoundedRectangle(cornerRadius: 12)).foregroundStyle(.black)
                            }
                        }
                        Button { library.toggleFavorite(k) } label: {
                            Image(systemName: library.prefs.isFavorite(k) ? "star.fill" : "star").font(.headline)
                                .foregroundStyle(library.prefs.isFavorite(k) ? Nova.gold : Nova.text).padding(12).background(Nova.panel, in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    if failed { Text("Couldn't load episodes. Try again later.").font(.footnote).foregroundStyle(Nova.live) }
                    if detail == nil && !failed { ProgressView("Loading episodes…").tint(Nova.accent) }
                    if !seasons.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) { ForEach(seasons, id: \.self) { n in Chip(text: "Season \(n)", selected: n == sel) { season = n } } }
                        }
                    }
                    LazyVStack(spacing: 10) {
                        ForEach(eps) { e in
                            Button { playingEp = e } label: { EpisodeRow(episode: e, cover: series.cover, prefs: library.prefs) }.buttonStyle(.plain)
                        }
                    }
                }.padding(.horizontal, 16).padding(.bottom, 24)
            }
        }
        .background(Nova.bg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
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
            NetImage(url: episode.image ?? cover, fallback: episode.title).frame(width: 120, height: 68).clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(alignment: .bottom) {
                    if pos > 0, dur > 0 {
                        GeometryReader { g in Capsule().fill(Nova.accent).frame(width: g.size.width * min(pos / dur, 1), height: 3) }.frame(height: 3).padding(4)
                    }
                }
            VStack(alignment: .leading, spacing: 3) {
                Text("\(episode.number). \(episode.title)").font(.subheadline.bold()).foregroundStyle(Nova.text).lineLimit(1)
                if let p = episode.plot { Text(p).font(.caption).foregroundStyle(Nova.muted).lineLimit(2) }
                if episode.durationSecs > 0 { Text(minutesText(Double(episode.durationSecs))).font(.caption2).foregroundStyle(Nova.faint) }
            }
            Spacer(minLength: 0)
        }.padding(8).background(Nova.panel, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct FlowTags: View {
    let tags: [String?]
    var body: some View {
        HStack(spacing: 6) { ForEach(tags.compactMap { $0 }, id: \.self) { t in Tag(text: t, color: t.hasPrefix("★") ? Nova.gold : Nova.text) } }
    }
}
