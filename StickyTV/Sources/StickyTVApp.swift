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
        }
    }
}

/// The sections, in the Fire TV app's order. Five fit along the bottom; the rest are under "More".
enum AppSection: Hashable { case home, live, movies, shows, search, settings }

final class Nav: ObservableObject {
    @Published var tab: AppSection = .home
}

struct RootView: View {
    @EnvironmentObject var library: Library
    @ObservedObject private var live = LivePlayer.shared
    @StateObject private var nav = Nav()
    @State private var account: Account?
    @State private var started = false

    var body: some View {
        Group {
            if account == nil {
                LoginView { a in
                    library.prefs.saveAccount(a)
                    library.load(a, force: true)
                    account = a
                }
            } else {
                TabView(selection: $nav.tab) {
                    HomeView().tabItem { Label("Home", systemImage: "house.fill") }.tag(AppSection.home)
                    LiveView().tabItem { Label("Live TV", systemImage: "play.tv.fill") }.tag(AppSection.live)
                    BrowseView(kind: .movie).tabItem { Label("Movies", systemImage: "film.fill") }.tag(AppSection.movies)
                    BrowseView(kind: .series).tabItem { Label("TV Shows", systemImage: "tv.fill") }.tag(AppSection.shows)
                    SearchView().tabItem { Label("Search", systemImage: "magnifyingglass") }.tag(AppSection.search)
                    SettingsView(onSignOut: {
                        live.stop()
                        if let a = account { library.prefs.removeAccount(a) }
                        library.signOut()
                        account = library.prefs.activeAccount
                        if let next = account { library.load(next) }
                    }).tabItem { Label("Settings", systemImage: "gearshape.fill") }.tag(AppSection.settings)
                }
                .environmentObject(nav)
            }
        }
        .background(Nova.bg.ignoresSafeArea())
        .fullScreenCover(isPresented: $live.fullScreen) { LiveFullScreen().environmentObject(library).environmentObject(nav) }
        .onAppear {
            guard !started else { return }
            started = true
            live.attach(library)
            account = library.prefs.activeAccount
            if let a = account { library.load(a) }
            let tab = UITabBarAppearance(); tab.configureWithOpaqueBackground(); tab.backgroundColor = UIColor(Nova.bg2)
            UITabBar.appearance().standardAppearance = tab; UITabBar.appearance().scrollEdgeAppearance = tab
            let bar = UINavigationBarAppearance(); bar.configureWithOpaqueBackground(); bar.backgroundColor = UIColor(Nova.bg)
            bar.titleTextAttributes = [.foregroundColor: UIColor.white]; bar.largeTitleTextAttributes = [.foregroundColor: UIColor.white]
            UINavigationBar.appearance().standardAppearance = bar; UINavigationBar.appearance().scrollEdgeAppearance = bar
        }
    }
}

/// Sign in to an Xtream provider (or paste an M3U link).
struct LoginView: View {
    let onDone: (Account) -> Void
    @State private var server = ""
    @State private var user = ""
    @State private var pass = ""
    @State private var name = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                BrandLogo().padding(.top, 40)
                Text("Sign in with the details from your provider.").foregroundStyle(Nova.muted)
                field("SERVER URL", $server, hint: "http://example.com:8080  (or paste an M3U link)", keyboard: .URL)
                field("USERNAME", $user, hint: "")
                VStack(alignment: .leading, spacing: 6) {
                    Text("PASSWORD").font(.caption.bold()).foregroundStyle(Nova.muted)
                    SecureField("", text: $pass).textContentType(.password).padding(14).background(Nova.panel, in: RoundedRectangle(cornerRadius: 12))
                }
                field("NAME (OPTIONAL)", $name, hint: "e.g. Home TV")
                if let error { Text(error).foregroundStyle(Nova.live).font(.footnote.bold()) }
                Button {
                    Task { await signIn() }
                } label: {
                    HStack { if busy { ProgressView().tint(.black) }; Text(busy ? "Signing in…" : "Sign in").bold() }
                        .frame(maxWidth: .infinity).padding(14).background(Nova.accent, in: RoundedRectangle(cornerRadius: 14)).foregroundStyle(.black)
                }.disabled(busy)
            }.padding(24)
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
                .padding(14).background(Nova.panel, in: RoundedRectangle(cornerRadius: 12))
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
