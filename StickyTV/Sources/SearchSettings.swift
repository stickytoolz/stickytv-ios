import SwiftUI
import StickyKit

/// One search for channels, movies and shows (as on the Fire TV).
struct SearchView: View {
    @EnvironmentObject var library: Library
    @ObservedObject private var live = LivePlayer.shared
    @State private var query = ""
    @State private var results: (channels: [Channel], movies: [Movie], series: [Series]) = ([], [], [])

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if query.trimmingCharacters(in: .whitespaces).count < 2 {
                        EmptyState(title: "Search", body_: "Channels, movies and shows: type at least two letters.")
                    } else if results.channels.isEmpty && results.movies.isEmpty && results.series.isEmpty {
                        EmptyState(title: "Nothing found", body_: "Try fewer or different words.")
                    }
                    if !results.channels.isEmpty {
                        SectionTitle(text: "Channels", trailing: "\(results.channels.count)").padding(.horizontal, 16)
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(spacing: 12) {
                                ForEach(results.channels) { c in Button { live.play(c, in: results.channels); live.fullScreen = true } label: { ChannelCard(channel: c) }.buttonStyle(.plain) }
                            }.padding(.horizontal, 16)
                        }
                    }
                    if !results.movies.isEmpty {
                        SectionTitle(text: "Movies", trailing: "\(results.movies.count)").padding(.horizontal, 16)
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(alignment: .top, spacing: 12) { ForEach(results.movies) { m in NavigationLink(value: m) { PosterCard(movie: m) }.buttonStyle(.plain) } }.padding(.horizontal, 16)
                        }
                    }
                    if !results.series.isEmpty {
                        SectionTitle(text: "TV Shows", trailing: "\(results.series.count)").padding(.horizontal, 16)
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(alignment: .top, spacing: 12) { ForEach(results.series) { s in NavigationLink(value: s) { PosterCard(series: s) }.buttonStyle(.plain) } }.padding(.horizontal, 16)
                        }
                    }
                }.padding(.vertical, 12)
            }
            .background(Nova.bg.ignoresSafeArea())
            .navigationTitle("Search")
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Channels, movies, shows")
            .navigationDestination(for: Movie.self) { MovieInfoView(movie: $0) }
            .navigationDestination(for: Series.self) { ShowInfoView(series: $0) }
            .task(id: query) { await search() }
        }
    }

    private func search() async {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else { results = ([], [], []); return }
        try? await Task.sleep(nanoseconds: 250_000_000)            // wait for typing to pause
        if Task.isCancelled { return }
        let chs = library.channels, mv = library.movies, se = library.series
        results = await Task.detached(priority: .userInitiated) {
            let words = q.lowercased().split(separator: " ").map(String.init)
            func hit(_ s: String) -> Bool { let l = s.lowercased(); return words.allSatisfy { l.contains($0) } }
            return (Array(chs.filter { hit($0.name) }.prefix(60)), Array(mv.filter { hit($0.name) }.prefix(60)), Array(se.filter { hit($0.name) }.prefix(60)))
        }.value
    }
}

struct SettingsView: View {
    let onSignOut: () -> Void
    @EnvironmentObject var library: Library
    @State private var confirm = false
    @AppStorage("appLogo") private var logo = AppLogo.graffiti.rawValue
    @State private var iconError: String?

    var body: some View {
        NavigationStack {
            List {
                Section("Account") {
                    if let a = library.prefs.activeAccount {
                        row("Name", a.name); row("Server", a.server); row("Username", a.username)
                    }
                    if let i = library.info {
                        row("Status", i.status)
                        row("Expires", i.expires?.formatted(date: .abbreviated, time: .omitted) ?? "Never")
                        row("Screens at once", "\(i.maxConnections)")
                    }
                    Button("Reload channels, movies and shows") { if let a = library.prefs.activeAccount { library.load(a, force: false) } }
                    Button("Sign out", role: .destructive) { confirm = true }
                }
                Section {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 14)], spacing: 14) {
                        ForEach(AppLogo.allCases) { l in
                            Button { pick(l) } label: {
                                VStack(spacing: 6) {
                                    Image(l.image).resizable().scaledToFit().padding(8).frame(width: 72, height: 72)
                                        .background(Nova.bg2, in: RoundedRectangle(cornerRadius: 16))
                                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(logo == l.rawValue ? Nova.accent : Nova.line, lineWidth: logo == l.rawValue ? 3 : 1))
                                    Text(l.rawValue).font(.caption2).foregroundStyle(logo == l.rawValue ? Nova.accent : Nova.muted).lineLimit(1)
                                }
                            }.buttonStyle(.plain)
                        }
                    }.padding(.vertical, 6)
                    if let iconError { Text(iconError).font(.caption).foregroundStyle(Nova.live) }
                } header: { Text("App icon") } footer: { Text("Changes the icon on your Home Screen and the logo inside the app.") }
                Section("About") {
                    row("Version", (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "?")
                    row("Channels", "\(library.channels.count)")
                    row("Movies", "\(library.movies.count)")
                    row("Shows", "\(library.series.count)")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Nova.bg.ignoresSafeArea())
            .navigationTitle("Settings")
            .confirmationDialog("Sign out of this provider?", isPresented: $confirm, titleVisibility: .visible) {
                Button("Sign out", role: .destructive) { onSignOut() }
            }
        }
    }

    private func pick(_ l: AppLogo) {
        iconError = nil
        logo = l.rawValue
        guard UIApplication.shared.supportsAlternateIcons else { return }
        UIApplication.shared.setAlternateIconName(l.iconName) { err in
            if let err { DispatchQueue.main.async { iconError = "Couldn't change the icon: \(err.localizedDescription)" } }
        }
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack { Text(k).foregroundStyle(Nova.muted); Spacer(); Text(v).multilineTextAlignment(.trailing).lineLimit(2) }
    }
}
