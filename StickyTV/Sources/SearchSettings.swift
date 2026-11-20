import SwiftUI
import StickyKit

/// One search for channels, movies and shows (as on the Fire TV).
struct SearchView: View {
    @EnvironmentObject var library: Library
    @ObservedObject private var live = LivePlayer.shared
    @State private var query = ""
    @State private var results: (channels: [Channel], movies: [Movie], series: [Series]) = ([], [], [])
    @FocusState private var typing: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Nova.muted)
                    TextField("Search channels, movies, shows", text: $query).focused($typing).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .submitLabel(.search)
                    if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Nova.muted) } }
                }
                .padding(12).background(Nova.panel, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(typing ? Nova.accent : Nova.line))
                .padding(.horizontal, 16).padding(.top, 8).padding(.trailing, 70)
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
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
                                LazyHStack(alignment: .top, spacing: 12) { ForEach(results.movies) { m in NavigationLink(value: m) { PosterCard(movie: m, width: 96) }.buttonStyle(.plain) } }.padding(.horizontal, 16)
                            }
                        }
                        if !results.series.isEmpty {
                            SectionTitle(text: "TV Shows", trailing: "\(results.series.count)").padding(.horizontal, 16)
                            ScrollView(.horizontal, showsIndicators: false) {
                                LazyHStack(alignment: .top, spacing: 12) { ForEach(results.series) { s in NavigationLink(value: s) { PosterCard(series: s, width: 96) }.buttonStyle(.plain) } }.padding(.horizontal, 16)
                            }
                        }
                    }.padding(.vertical, 12)
                }.scrollDismissesKeyboard(.immediately)
            }
            .background(Nova.bg.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
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

private enum SettingsTab: String, CaseIterable {
    case look = "Look & feel", home = "Home screen", player = "Player", guide = "TV guide", sports = "Sports",
         hide = "Hide & unhide", account = "Profiles & logins", about = "About"
}

/// Settings as on the Fire TV: the sections down the left, the chosen one on the right.
struct SettingsView: View {
    let onSignOut: () -> Void
    @EnvironmentObject var library: Library
    @State private var tab = SettingsTab.look
    @State private var confirm = false
    @State private var adding = false
    @State private var hideKind = Kind.live
    @State private var tick = 0                 // redraws after a setting kept in Prefs changes
    @AppStorage("appLogo") private var logo = AppLogo.graffiti.rawValue
    @AppStorage("clock24") private var clock24 = false
    @AppStorage("showClock") private var showClock = true
    @AppStorage("homeRowsVersion") private var rowsVersion = 0
    @State private var iconError: String?

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("SETTINGS").font(.system(size: 20, weight: .black)).foregroundStyle(Nova.text).padding(.bottom, 6)
                    ForEach(SettingsTab.allCases, id: \.self) { t in
                        Button { tab = t } label: {
                            Text(t.rawValue).font(.system(size: 14, weight: tab == t ? .bold : .medium)).foregroundStyle(tab == t ? Nova.accent : Nova.text)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).padding(.vertical, 8)
                                .background(tab == t ? Nova.accent.opacity(0.13) : .clear, in: RoundedRectangle(cornerRadius: 10))
                        }.buttonStyle(.plain)
                    }
                }.padding(.top, 8)
            }.frame(width: 180).padding(.leading, 12)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    let _ = tick
                    switch tab {
                    case .look: lookPage
                    case .home: homePage
                    case .player: playerPage
                    case .guide: guidePage
                    case .sports: sportsPage
                    case .hide: hidePage
                    case .account: accountPage
                    case .about: aboutPage
                    }
                }.padding(.horizontal, 20).padding(.top, 36).padding(.bottom, 24)
            }
        }
        .background(Nova.bg.ignoresSafeArea())
        .confirmationDialog("Sign out of this login?", isPresented: $confirm, titleVisibility: .visible) {
            Button("Sign out", role: .destructive) { onSignOut() }
        }
        .sheet(isPresented: $adding) {
            LoginView { a in
                adding = false
                library.prefs.saveAccount(a)
                LivePlayer.shared.stop()
                library.load(a, force: true)
                tick += 1
            }
        }
    }

    @ViewBuilder private var lookPage: some View {
        SectionTitle(text: "App icon")
        Text("Changes the icon on your Home Screen and the logo inside the app.").font(.caption).foregroundStyle(Nova.muted)
        HStack(spacing: 14) {
            ForEach(AppLogo.allCases) { l in
                Button { pick(l) } label: {
                    VStack(spacing: 6) {
                        Image(l.image).resizable().scaledToFit().padding(8).frame(width: 78, height: 78)
                            .background(Nova.bg2, in: RoundedRectangle(cornerRadius: 18))
                            .overlay(RoundedRectangle(cornerRadius: 18).stroke(logo == l.rawValue ? Nova.accent : Nova.line, lineWidth: logo == l.rawValue ? 3 : 1))
                        Text(l.rawValue).font(.caption2).foregroundStyle(logo == l.rawValue ? Nova.accent : Nova.muted).lineLimit(1)
                    }
                }.buttonStyle(.plain)
            }
        }
        if let iconError { Text(iconError).font(.caption).foregroundStyle(Nova.live) }
        SectionTitle(text: "Screen").padding(.top, 12)
        SettingRow(title: "Show clock", value: showClock ? "On" : "Off") { showClock.toggle() }
        SettingRow(title: "Clock style", value: clock24 ? "24-hour" : "12-hour") { clock24.toggle() }
    }

    @ViewBuilder private var homePage: some View {
        SectionTitle(text: "Home screen rows")
        Text("Turn rows on or off. They appear in this order.").font(.caption).foregroundStyle(Nova.muted)
        ForEach(HomeRow.allCases, id: \.self) { r in
            let hidden = library.prefs.hiddenHomeRows.contains(r.rawValue)
            SettingRow(title: r.rawValue, value: hidden ? "Off" : "On") {
                var h = library.prefs.hiddenHomeRows
                if hidden { h.remove(r.rawValue) } else { h.insert(r.rawValue) }
                library.prefs.hiddenHomeRows = h
                rowsVersion += 1; tick += 1
            }
        }
    }

    @ViewBuilder private var playerPage: some View {
        SectionTitle(text: "Live TV")
        SettingRow(title: "Play last channel at start", value: library.prefs.autoplayLast ? "On" : "Off", help: "Jump straight into live TV when the app opens.") {
            library.prefs.autoplayLast.toggle(); tick += 1
        }
        SettingRow(title: "Channel info shows for", value: "\(library.prefs.overlaySecs) seconds", help: "In full screen, after changing channel or tapping the picture.") {
            let opts = [3, 5, 8, 12]
            library.prefs.overlaySecs = opts[((opts.firstIndex(of: library.prefs.overlaySecs) ?? 1) + 1) % opts.count]; tick += 1
        }
        SettingRow(title: "Player engine", value: Prefs.playerEngines.first { $0.id == library.prefs.playerEngine }?.name ?? "VLC · MPEG-TS",
                   help: "VLC · MPEG-TS is what works on the Fire TV. Try the others if channels freeze or won't start (VLC switches a channel that won't open to the other format by itself). Changes on the next channel.") {
            let e = Prefs.playerEngines.map(\.id)
            library.prefs.playerEngine = e[((e.firstIndex(of: library.prefs.playerEngine) ?? 0) + 1) % e.count]; tick += 1
        }
        SectionTitle(text: "Buffering").padding(.top, 12)
        SettingRow(title: "Buffer", value: ["Low (fast channel changes)", "Normal", "High (slow internet)"][min(max(library.prefs.bufferMode, 0), 2)],
                   help: "A bigger buffer means fewer freezes on slow internet, and slower channel changes. Changes on the next channel.") {
            library.prefs.bufferMode = (library.prefs.bufferMode + 1) % 3; tick += 1
        }
        SettingRow(title: "Weak-signal cushion", value: library.prefs.cushion ? "On" : "Off",
                   help: "On: after a channel stops for a weak signal, it saves 8, 15 then 25 seconds ahead before carrying on (plays a little behind live, fewer stops). Off: the plain player.") {
            library.prefs.cushion.toggle(); tick += 1
        }
        SectionTitle(text: "Stream health").padding(.top, 12)
        Text("Each channel's signal shows as a dot in the guide (green strong, yellow good, red weak). In full screen, the bars button opens the Channel signal window.")
            .font(.caption).foregroundStyle(Nova.muted)
        let problems = LivePlayer.shared.signals.problems
        if problems.isEmpty {
            InfoRow(k: "Recent stream problems", v: "None")
        } else {
            ForEach(problems.prefix(15)) { p in
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(whenText(p.at)) · \(p.channel)").font(.caption.bold()).foregroundStyle(Nova.text)
                    Text(p.what).font(.caption).foregroundStyle(Nova.muted).fixedSize(horizontal: false, vertical: true)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(10).background(Nova.panel.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
            }
            SettingRow(title: "Clear the list", value: "") { LivePlayer.shared.signals.clearProblems(); tick += 1 }
        }
        Text("Movies and shows: MP4 plays in the iPhone's own player, everything else (MKV, AVI…) in VLC.").font(.caption).foregroundStyle(Nova.muted).padding(.top, 4)
    }

    @ViewBuilder private var guidePage: some View {
        SectionTitle(text: "TV guide")
        SettingRow(title: "Guide time shift", value: "\(library.prefs.guideOffsetHours > 0 ? "+" : "")\(library.prefs.guideOffsetHours) h",
                   help: "If the guide is an hour or more off, move it here.") {
            var h = library.prefs.guideOffsetHours + 1
            if h > 12 { h = -12 }
            library.prefs.guideOffsetHours = h
            library.loadGuide(force: true); tick += 1
        }
        SettingRow(title: "Refresh TV guide now", value: library.guideStatus ?? "Ready", help: "Downloads the guide from your provider again.") {
            library.loadGuide(force: true)
        }
    }

    @ViewBuilder private var sportsPage: some View {
        SectionTitle(text: "Sports")
        SettingRow(title: "Live scores", value: library.prefs.liveScores ? "On" : "Off", help: "Scores and game clocks on the game cards, from ESPN. Checked once a minute.") {
            library.prefs.liveScores.toggle(); tick += 1
        }
        SectionTitle(text: "My Teams", trailing: "\(library.prefs.myTeams.count) picked").padding(.top, 12)
        TeamPicker(showsTitle: false)
    }

    @ViewBuilder private var hidePage: some View {
        SectionTitle(text: "Hide & unhide categories")
        Text("Hidden categories disappear from Live TV, Movies and TV Shows (and their channels and titles from everywhere else).").font(.caption).foregroundStyle(Nova.muted)
        HStack(spacing: 8) {
            Chip(text: "Live TV", selected: hideKind == .live) { hideKind = .live }
            Chip(text: "Movies", selected: hideKind == .movie) { hideKind = .movie }
            Chip(text: "TV Shows", selected: hideKind == .series) { hideKind = .series }
        }
        let cats = hideKind == .live ? library.allLiveCategories : hideKind == .movie ? library.allMovieCategories : library.allSeriesCategories
        let prefix = hideKind == .live ? "live" : hideKind == .movie ? "movie" : "series"
        let hidden = library.prefs.hiddenCategories
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 8)], spacing: 8) {
            ForEach(cats) { c in
                let key = "\(prefix):\(c.id)"
                Button { library.toggleHidden(key); tick += 1 } label: {
                    HStack {
                        Image(systemName: hidden.contains(key) ? "eye.slash" : "eye").foregroundStyle(hidden.contains(key) ? Nova.faint : Nova.accent)
                        Text(c.name).font(.caption.bold()).foregroundStyle(hidden.contains(key) ? Nova.faint : Nova.text).lineLimit(1)
                        Spacer(minLength: 0)
                    }.padding(10).background(Nova.panel, in: RoundedRectangle(cornerRadius: 10))
                }.buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder private var accountPage: some View {
        SectionTitle(text: "Logins")
        let active = library.prefs.activeAccount?.id
        ForEach(library.prefs.accounts) { a in
            HStack(spacing: 10) {
                Image(systemName: a.id == active ? "checkmark.circle.fill" : "circle").foregroundStyle(a.id == active ? Nova.accent : Nova.faint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(a.name).font(.subheadline.bold()).foregroundStyle(Nova.text)
                    Text("\(a.username) · \(a.server)").font(.caption).foregroundStyle(Nova.muted).lineLimit(1)
                }
                Spacer()
                if a.id != active {
                    Button("Switch") {
                        LivePlayer.shared.stop()
                        library.prefs.activeAccountId = a.id
                        library.load(a); tick += 1
                    }.font(.caption.bold()).buttonStyle(.bordered)
                }
            }.padding(12).background(Nova.panel, in: RoundedRectangle(cornerRadius: 14))
        }
        SettingRow(title: "Add a login", value: "") { adding = true }
        if let i = library.info {
            SectionTitle(text: "This login").padding(.top, 12)
            InfoRow(k: "Status", v: i.status)
            InfoRow(k: "Expires", v: i.expires?.formatted(date: .abbreviated, time: .omitted) ?? "Never")
            InfoRow(k: "Screens at once", v: "\(i.maxConnections)")
        }
        SettingRow(title: "Reload channels, movies and shows", value: "") { if let a = library.prefs.activeAccount { library.load(a) } }
        SettingRow(title: "Sign out of this login", value: "", danger: true) { confirm = true }
    }

    @ViewBuilder private var aboutPage: some View {
        HStack(spacing: 14) { BrandLogo() }
        InfoRow(k: "Version", v: (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "?")
        InfoRow(k: "Channels", v: "\(library.channels.count)")
        InfoRow(k: "Movies", v: "\(library.movies.count)")
        InfoRow(k: "Shows", v: "\(library.series.count)")
        InfoRow(k: "Coming next", v: "Cast & actors, recordings, Multiview, backup")
    }

    private func pick(_ l: AppLogo) {
        iconError = nil
        logo = l.rawValue
        guard UIApplication.shared.supportsAlternateIcons else { return }
        UIApplication.shared.setAlternateIconName(l.iconName) { err in
            if let err { DispatchQueue.main.async { iconError = "Couldn't change the icon: \(err.localizedDescription)" } }
        }
    }
}

/// A row you tap to change a setting (the Fire TV's SettingRow).
struct SettingRow: View {
    let title: String
    let value: String
    var help: String? = nil
    var danger = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline.bold()).foregroundStyle(danger ? Nova.live : Nova.text)
                    if let help { Text(help).font(.caption).foregroundStyle(Nova.muted) }
                }
                Spacer()
                Text(value).font(.subheadline).foregroundStyle(Nova.accent).lineLimit(1)
            }.padding(.horizontal, 16).padding(.vertical, 12).background(Nova.panel, in: RoundedRectangle(cornerRadius: 14))
        }.buttonStyle(.plain)
    }
}

struct InfoRow: View {
    let k: String
    let v: String
    var body: some View {
        HStack { Text(k).foregroundStyle(Nova.muted); Spacer(); Text(v).foregroundStyle(Nova.text).lineLimit(1) }
            .font(.subheadline).padding(.horizontal, 16).padding(.vertical, 10).background(Nova.panel.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
    }
}
