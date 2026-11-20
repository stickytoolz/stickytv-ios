import SwiftUI
import StickyKit

/// Home, with the Fire TV app's rows: favourite channels, recently watched, continue watching, new movies, latest shows.
struct HomeView: View {
    @EnvironmentObject var library: Library
    @EnvironmentObject var nav: Nav
    @ObservedObject private var live = LivePlayer.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack {
                        BrandLogo()
                        Spacer()
                        if let e = library.info?.expires {
                            VStack(alignment: .trailing, spacing: 1) {
                                Text("EXPIRES").font(.system(size: 9, weight: .heavy)).tracking(1).foregroundStyle(Nova.faint)
                                Text(e.formatted(date: .abbreviated, time: .omitted)).font(.caption.bold())
                                    .foregroundStyle(e.timeIntervalSinceNow < 7 * 86400 ? Nova.live : Nova.muted)
                            }
                        }
                    }.padding(.leading, 16).padding(.trailing, 86).padding(.top, 6)     // (the clock is at the top right)

                    if library.vodLoading && library.movies.isEmpty {
                        HStack(spacing: 8) { ProgressView().tint(Nova.accent); Text("Movies and shows are still arriving…").font(.caption).foregroundStyle(Nova.muted) }
                            .padding(.horizontal, 16)
                    }

                    let favs = library.favoriteChannels()
                    if !favs.isEmpty { channelRow("Favourite channels", favs) }
                    let recent = library.recentChannels()
                    if !recent.isEmpty { channelRow("Recently watched channels", recent) }

                    let cont = continueWatching()
                    if !cont.isEmpty {
                        row("Continue watching") {
                            ForEach(cont) { m in NavigationLink(value: m) { PosterCard(movie: m, progress: progress(m)) }.buttonStyle(.plain) }
                        }
                    }
                    let newMovies = Array(library.movies.sorted { $0.added > $1.added }.prefix(20))
                    if !newMovies.isEmpty {
                        row("New movies") { ForEach(newMovies) { m in NavigationLink(value: m) { PosterCard(movie: m) }.buttonStyle(.plain) } }
                    }
                    let shows = Array(library.series.sorted { $0.updated > $1.updated }.prefix(20))
                    if !shows.isEmpty {
                        row("Latest shows") { ForEach(shows) { s in NavigationLink(value: s) { PosterCard(series: s) }.buttonStyle(.plain) } }
                    }
                    if favs.isEmpty && recent.isEmpty && library.channels.isEmpty, case .failed(let msg) = library.state {
                        EmptyState(title: "Couldn't load your account", body_: msg)
                    }
                }.padding(.bottom, 24)
            }
            .background(Nova.bg.ignoresSafeArea())
            .navigationDestination(for: Movie.self) { MovieInfoView(movie: $0) }
            .navigationDestination(for: Series.self) { ShowInfoView(series: $0) }
            .toolbar(.hidden, for: .navigationBar)
            .refreshable { if let a = library.prefs.activeAccount { library.load(a) } }
        }
    }

    private func continueWatching() -> [Movie] {
        library.movies.filter { library.prefs.position(Prefs.movieKey($0)) > 0 }.prefix(20).map { $0 }
    }
    private func progress(_ m: Movie) -> Double {
        let k = Prefs.movieKey(m)
        let d = library.prefs.duration(k)
        return d > 0 ? library.prefs.position(k) / d : 0
    }

    private func channelRow(_ title: String, _ list: [Channel]) -> some View {
        row(title) {
            ForEach(list) { c in
                Button { live.play(c, in: list); live.fullScreen = true } label: { ChannelCard(channel: c) }.buttonStyle(.plain)
            }
        }
    }

    private func row<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(text: title).padding(.horizontal, 16)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 12) { content() }.padding(.horizontal, 16)
            }
        }
    }
}

struct ChannelCard: View {
    let channel: Channel
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            NetImage(url: channel.logo, fallback: channel.name, fit: true)
                .padding(14).frame(width: 140, height: 84)
                .background(Color(red: 0.04, green: 0.06, blue: 0.11), in: RoundedRectangle(cornerRadius: 12))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Nova.line))
            Text(channel.name).font(.caption.weight(.semibold)).foregroundStyle(Nova.text).lineLimit(1).frame(width: 140, alignment: .leading)
        }
    }
}

/// A poster with its title and year under it; a star rating and 4K / HD in the corners, like the Fire TV.
struct PosterCard: View {
    let title: String
    let image: String?
    let subtitle: String?
    let rating: Double
    let quality: String?
    var progress: Double = 0
    var width: CGFloat = 110

    init(movie m: Movie, progress: Double = 0, width: CGFloat = 110) {
        let ct = cleanTitle(m.name)
        title = ct.title; image = m.poster; subtitle = ct.year; rating = m.rating; quality = ct.quality; self.progress = progress; self.width = width
    }
    init(series s: Series, width: CGFloat = 110) {
        let ct = cleanTitle(s.name)
        title = ct.title; image = s.cover; subtitle = s.year ?? ct.year; rating = s.rating; quality = nil; self.width = width
    }
    init(title: String, image: String?, subtitle: String?, badge: String? = nil, width: CGFloat = 110) {
        self.title = title; self.image = image; self.subtitle = subtitle; rating = 0; quality = badge; self.width = width
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ZStack {
                NetImage(url: image, fallback: title)
            }
            .frame(width: width, height: width * 1.5)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Nova.line))
            .overlay(alignment: .topLeading) {
                if rating > 0 {
                    Text("★ \(String(format: "%.1f", rating))").font(.system(size: 10, weight: .bold)).foregroundStyle(Nova.gold)
                        .padding(.horizontal, 5).padding(.vertical, 3).background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 5)).padding(5)
                }
            }
            .overlay(alignment: .topTrailing) {
                if let q = quality {
                    Text(q).font(.system(size: 10, weight: .bold)).foregroundStyle(q == "4K" ? Nova.gold : .white)
                        .padding(.horizontal, 5).padding(.vertical, 3).background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 5)).padding(5)
                }
            }
            .overlay(alignment: .bottom) {
                if progress > 0 {
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.25))
                            Capsule().fill(Nova.accent).frame(width: g.size.width * min(progress, 1))
                        }
                    }.frame(height: 4).padding(6)
                }
            }
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(Nova.text).lineLimit(1)
            if let s = subtitle { Text(s).font(.system(size: 11)).foregroundStyle(Nova.muted).lineLimit(1) }
        }.frame(width: width)
    }
}
