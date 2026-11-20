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

private enum SettingsTab: String, CaseIterable { case look = "Look & feel", guide = "TV guide", account = "Profiles & logins", about = "About" }

/// Settings as on the Fire TV: the sections down the left, the chosen one on the right.
struct SettingsView: View {
    let onSignOut: () -> Void
    @EnvironmentObject var library: Library
    @State private var tab = SettingsTab.look
    @State private var confirm = false
    @AppStorage("appLogo") private var logo = AppLogo.graffiti.rawValue
    @AppStorage("clock24") private var clock24 = false
    @State private var iconError: String?

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("SETTINGS").font(.system(size: 20, weight: .black)).foregroundStyle(Nova.text).padding(.bottom, 8)
                ForEach(SettingsTab.allCases, id: \.self) { t in
                    Button { tab = t } label: {
                        Text(t.rawValue).font(.system(size: 14, weight: tab == t ? .bold : .medium)).foregroundStyle(tab == t ? Nova.accent : Nova.text)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).padding(.vertical, 9)
                            .background(tab == t ? Nova.accent.opacity(0.13) : .clear, in: RoundedRectangle(cornerRadius: 10))
                    }.buttonStyle(.plain)
                }
                Spacer()
            }.frame(width: 180).padding(.leading, 12).padding(.top, 8)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    switch tab {
                    case .look: lookPage
                    case .guide: guidePage
                    case .account: accountPage
                    case .about: aboutPage
                    }
                }.padding(.horizontal, 20).padding(.top, 36).padding(.bottom, 24)
            }
        }
        .background(Nova.bg.ignoresSafeArea())
        .confirmationDialog("Sign out of this provider?", isPresented: $confirm, titleVisibility: .visible) {
            Button("Sign out", role: .destructive) { onSignOut() }
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
        SettingRow(title: "Clock style", value: clock24 ? "24-hour" : "12-hour") { clock24.toggle() }
    }

    @ViewBuilder private var guidePage: some View {
        SectionTitle(text: "TV guide")
        SettingRow(title: "Guide time shift", value: "\(library.prefs.guideOffsetHours > 0 ? "+" : "")\(library.prefs.guideOffsetHours) h",
                   help: "If the guide is an hour or more off, move it here.") {
            var h = library.prefs.guideOffsetHours + 1
            if h > 12 { h = -12 }
            library.prefs.guideOffsetHours = h
            library.loadGuide(force: true)
        }
        SettingRow(title: "Refresh TV guide now", value: library.guideStatus ?? "Ready", help: "Downloads the guide from your provider again.") {
            library.loadGuide(force: true)
        }
    }

    @ViewBuilder private var accountPage: some View {
        SectionTitle(text: "This login")
        if let a = library.prefs.activeAccount {
            InfoRow(k: "Name", v: a.name); InfoRow(k: "Server", v: a.server); InfoRow(k: "Username", v: a.username)
        }
        if let i = library.info {
            InfoRow(k: "Status", v: i.status)
            InfoRow(k: "Expires", v: i.expires?.formatted(date: .abbreviated, time: .omitted) ?? "Never")
            InfoRow(k: "Screens at once", v: "\(i.maxConnections)")
        }
        SettingRow(title: "Reload channels, movies and shows", value: "") { if let a = library.prefs.activeAccount { library.load(a) } }
        SettingRow(title: "Sign out", value: "", danger: true) { confirm = true }
    }

    @ViewBuilder private var aboutPage: some View {
        HStack(spacing: 14) { BrandLogo() }
        InfoRow(k: "Version", v: (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "?")
        InfoRow(k: "Channels", v: "\(library.channels.count)")
        InfoRow(k: "Movies", v: "\(library.movies.count)")
        InfoRow(k: "Shows", v: "\(library.series.count)")
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
