import SwiftUI
import StickyKit

@main
struct StickyTVApp: App {
    @StateObject private var library = Library()
    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(library)
                .preferredColorScheme(.dark)
                .tint(Nova.accent)
                .persistentSystemOverlays(.hidden)
        }
    }
}

/// The sections of the left menu, in the Fire TV app's order.
enum AppSection: String, CaseIterable, Hashable {
    case search, home, live, multiview, sports, movies, shows, recordings, settings
    var label: String {
        switch self {
        case .search: "Search"; case .home: "Home"; case .live: "Live TV"; case .multiview: "Multiview"; case .sports: "Sports"
        case .movies: "Movies"; case .shows: "TV Shows"; case .recordings: "Recordings"; case .settings: "Settings"
        }
    }
    var icon: String {
        switch self {
        case .search: "magnifyingglass"; case .home: "house.fill"; case .live: "play.tv.fill"; case .multiview: "square.grid.2x2.fill"
        case .sports: "sportscourt.fill"; case .movies: "film.fill"; case .shows: "tv.fill"; case .recordings: "record.circle"; case .settings: "gearshape.fill"
        }
    }
}

final class Nav: ObservableObject {
    @Published var section: AppSection = .home
}

/// The Fire TV app's frame, on its side: the menu down the left, the page on the right, the clock at the top.
struct RootView: View {
    @EnvironmentObject var library: Library
    @ObservedObject private var live = LivePlayer.shared
    @StateObject private var nav = Nav()
    @State private var account: Account?
    @State private var started = false
    @State private var autoplayed = false
    @AppStorage("showClock") private var showClock = true

    var body: some View {
        Group {
            if account == nil {
                LoginView { a in
                    library.prefs.saveAccount(a)
                    library.load(a, force: true)
                    account = a
                }
            } else {
                HStack(spacing: 0) {
                    Rail(nav: nav)
                    ZStack(alignment: .topTrailing) {
                        page.frame(maxWidth: .infinity, maxHeight: .infinity)
                        if showClock { ClockView().padding(.top, 6).padding(.trailing, 14).allowsHitTesting(false) }
                    }
                }
                .environmentObject(nav)
            }
        }
        .background(Nova.bg.ignoresSafeArea())
        .fullScreenCover(isPresented: $live.fullScreen) { LiveFullScreen().environmentObject(library).environmentObject(nav) }
        .onChange(of: library.channels.count) { n in
            // Settings › Player › Play last channel at start
            guard n > 0, !autoplayed else { return }
            autoplayed = true
            if library.prefs.autoplayLast, live.channel == nil, let c = library.channels.first(where: { $0.id == library.prefs.lastChannel }) {
                nav.section = .live
                live.play(c, in: library.channelsByCat[c.categoryId] ?? library.channels)
                live.fullScreen = true
            }
        }
        .onAppear {
            guard !started else { return }
            started = true
            live.attach(library)
            account = library.prefs.activeAccount
            if let a = account { library.load(a) }
        }
    }

    @ViewBuilder private var page: some View {
        switch nav.section {
        case .search: SearchView()
        case .home: HomeView()
        case .live: LiveView()
        case .multiview: ComingSoon(title: "Multiview", text: "Up to four channels at once is coming in a later update.")
        case .sports: SportsView()
        case .movies: BrowseView(kind: .movie).id("movies")
        case .shows: BrowseView(kind: .series).id("shows")
        case .recordings: ComingSoon(title: "Recordings", text: "Recording is coming in a later update.")
        case .settings:
            SettingsView(onSignOut: {
                live.stop()
                if let a = account { library.prefs.removeAccount(a) }
                library.signOut()
                account = library.prefs.activeAccount
                if let next = account { library.load(next) }
            })
        }
    }
}

/// The menu down the left (icons, like the Fire TV's): tap one to go there.
struct Rail: View {
    @ObservedObject var nav: Nav
    @AppStorage("appLogo") private var logo = AppLogo.graffiti.rawValue
    var body: some View {
        VStack(spacing: 0) {
            Image((AppLogo(rawValue: logo) ?? .graffiti).image).resizable().scaledToFit().frame(width: 34, height: 28).padding(.vertical, 3)
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 3) {
                    ForEach(AppSection.allCases, id: \.self) { s in
                        Button { nav.section = s } label: {
                            Image(systemName: s.icon).font(.system(size: 15, weight: .semibold))
                                .frame(width: 42, height: 31)
                                .foregroundStyle(nav.section == s ? Nova.accent : Nova.muted)
                                .background(nav.section == s ? Nova.accent.opacity(0.16) : Nova.panel, in: RoundedRectangle(cornerRadius: 11))
                                .overlay(RoundedRectangle(cornerRadius: 11).stroke(nav.section == s ? Nova.accent.opacity(0.6) : Nova.line))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(s.label)
                        if s == .search { Spacer().frame(height: 2) }
                    }
                }.padding(.vertical, 2)
            }
            // which version this is (handy when sideloading a new one)
            Text("v" + ((Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "?"))
                .font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundStyle(Nova.faint).padding(.bottom, 4)
        }
        .frame(width: 62)
        .background(LinearGradient(colors: [Nova.bg2, Nova.bg], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
    }
}

struct ClockView: View {
    @AppStorage("clock24") private var clock24 = false
    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { ctx in
            Text(timeText(ctx.date, clock24: clock24)).font(.system(size: 15, weight: .bold, design: .monospaced)).foregroundStyle(Nova.text)
        }
    }
}

struct ComingSoon: View {
    let title: String
    let text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased()).font(.system(size: 24, weight: .black)).foregroundStyle(Nova.text)
            Text(text).foregroundStyle(Nova.muted)
            Spacer()
        }.padding(.horizontal, 28).padding(.top, 16).frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A "‹ Back" button for pages opened from another (the menu stays on the left).
struct BackButton: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        Button { dismiss() } label: {
            Label("Back", systemImage: "chevron.left").font(.subheadline.bold()).padding(.horizontal, 12).padding(.vertical, 7)
                .background(.black.opacity(0.45), in: Capsule())
        }.buttonStyle(.plain).foregroundStyle(.white)
    }
}

/// Sign in to an Xtream provider (or paste an M3U link). Logo on the left, the boxes on the right.
struct LoginView: View {
    let onDone: (Account) -> Void
    @State private var server = ""
    @State private var user = ""
    @State private var pass = ""
    @State private var name = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 14) {
                Image(AppLogo.graffiti.image).resizable().scaledToFit().frame(maxWidth: 220)
                Text("Sign in with the details from your provider.").font(.subheadline).foregroundStyle(Nova.muted).multilineTextAlignment(.center)
            }.frame(maxWidth: .infinity).padding(24)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    field("SERVER URL", $server, hint: "http://example.com:8080  (or paste an M3U link)", keyboard: .URL)
                    HStack(spacing: 12) {
                        field("USERNAME", $user, hint: "")
                        VStack(alignment: .leading, spacing: 6) {
                            Text("PASSWORD").font(.caption.bold()).foregroundStyle(Nova.muted)
                            SecureField("", text: $pass).textContentType(.password).padding(12).background(Nova.panel, in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    field("NAME (OPTIONAL)", $name, hint: "e.g. Home TV")
                    if let error { Text(error).foregroundStyle(Nova.live).font(.footnote.bold()) }
                    Button { Task { await signIn() } } label: {
                        HStack { if busy { ProgressView().tint(.black) }; Text(busy ? "Signing in…" : "Sign in").bold() }
                            .frame(maxWidth: .infinity).padding(13).background(Nova.accent, in: RoundedRectangle(cornerRadius: 14)).foregroundStyle(.black)
                    }.disabled(busy)
                }.padding(24)
            }.frame(maxWidth: .infinity)
        }
        .background(Nova.bg.ignoresSafeArea())
        .onChange(of: server) { v in
            // a pasted M3U link fills in everything
            if let a = XtreamAPI.parseM3uLink(v), user.isEmpty || pass.isEmpty { server = a.server; user = a.username; pass = a.password }
        }
    }

    private func field(_ label: String, _ text: Binding<String>, hint: String, keyboard: UIKeyboardType = .default) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.caption.bold()).foregroundStyle(Nova.muted)
            TextField(hint, text: text).keyboardType(keyboard).textInputAutocapitalization(.never).autocorrectionDisabled()
                .padding(12).background(Nova.panel, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func signIn() async {
        error = nil
        guard !server.trimmingCharacters(in: .whitespaces).isEmpty, !user.isEmpty, !pass.isEmpty else { error = "Fill in the server, username and password."; return }
        busy = true
        defer { busy = false }
        let a = Account(name: name.isEmpty ? (URLComponents(string: XtreamAPI.normalizeServer(server))?.host ?? "My TV") : name,
                        server: XtreamAPI.normalizeServer(server), username: user.trimmingCharacters(in: .whitespaces), password: pass)
        do { _ = try await XtreamAPI(account: a).login(); onDone(a) } catch { self.error = error.localizedDescription }
    }
}
