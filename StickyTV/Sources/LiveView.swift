import SwiftUI
import StickyKit

private let favCat = "__fav", recentCat = "__recent", allCat = "__all"

/// Live TV, as on the Fire TV: the picture in a preview at the top, the categories, then the channels. Tap a channel to
/// watch it in the preview; tap it again (or the preview) for full screen.
struct LiveView: View {
    @EnvironmentObject var library: Library
    @ObservedObject private var live = LivePlayer.shared
    @AppStorage("liveCat") private var cat = allCat

    private var cats: [(String, String)] {
        [(favCat, "★ Favourites"), (recentCat, "Recently watched"), (allCat, "All channels")] + library.liveCategories.map { ($0.id, $0.name) }
    }
    private var channels: [Channel] {
        _ = library.favoritesVersion
        switch cat {
        case favCat: return library.favoriteChannels()
        case recentCat: return library.recentChannels()
        case allCat: return library.channels
        default: return library.channelsByCat[cat] ?? []
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if let c = live.channel {
                LiveVideo().aspectRatio(16 / 9, contentMode: .fit).contentShape(Rectangle())
                    .onTapGesture { live.fullScreen = true }
                    .overlay(alignment: .bottomLeading) {
                        Text(c.name).font(.caption.bold()).padding(.horizontal, 8).padding(.vertical, 4)
                            .background(.black.opacity(0.6), in: Capsule()).padding(8)
                    }
                    .overlay(alignment: .topTrailing) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right").font(.caption.bold()).padding(8)
                            .background(.black.opacity(0.5), in: Circle()).padding(8)
                    }
            }
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(cats, id: \.0) { id, name in Chip(text: name, selected: id == cat) { cat = id }.id(id) }
                    }.padding(.horizontal, 16).padding(.vertical, 10)
                }
                .onAppear { proxy.scrollTo(cat, anchor: .center) }
            }
            if case .loading(let msg) = library.state, library.channels.isEmpty {
                Spacer(); ProgressView(msg).tint(Nova.accent); Spacer()
            } else if case .failed(let msg) = library.state, library.channels.isEmpty {
                EmptyState(title: "Couldn't load your channels", body_: msg); Spacer()
            } else if channels.isEmpty {
                EmptyState(title: "Nothing here", body_: cat == favCat ? "Press and hold a channel to add it to Favourites." : "This category is empty."); Spacer()
            } else {
                ScrollViewReader { proxy in
                    List(channels) { c in
                        ChannelRow(channel: c, playing: live.channel?.id == c.id, favorite: library.prefs.isFavorite(Prefs.liveKey(c)))
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if live.channel?.id == c.id { live.fullScreen = true } else { live.play(c, in: channels) }
                            }
                            .contextMenu {
                                Button { library.toggleFavorite(Prefs.liveKey(c)) } label: {
                                    library.prefs.isFavorite(Prefs.liveKey(c)) ? Label("Remove from Favourites", systemImage: "star.slash") : Label("Add to Favourites", systemImage: "star")
                                }
                                Button { live.play(c, in: channels); live.fullScreen = true } label: { Label("Watch full screen", systemImage: "arrow.up.left.and.arrow.down.right") }
                            }
                            .listRowBackground(live.channel?.id == c.id ? Nova.panelHi : Nova.bg)
                            .listRowSeparatorTint(Nova.line)
                            .id(c.id)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .onAppear { if let id = live.channel?.id { proxy.scrollTo(id, anchor: .center) } }
                }
            }
        }
        .background(Nova.bg.ignoresSafeArea())
    }
}

struct ChannelRow: View {
    let channel: Channel
    let playing: Bool
    let favorite: Bool
    var body: some View {
        HStack(spacing: 12) {
            NetImage(url: channel.logo, fallback: channel.name, fit: true)
                .frame(width: 56, height: 40).padding(4).background(Color(red: 0.04, green: 0.06, blue: 0.11), in: RoundedRectangle(cornerRadius: 8))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if channel.num > 0 { Text("\(channel.num)").font(.caption.monospacedDigit()).foregroundStyle(Nova.faint) }
                    Text(channel.name).font(.body.weight(.semibold)).foregroundStyle(Nova.text).lineLimit(1)
                }
            }
            Spacer()
            if favorite { Image(systemName: "star.fill").foregroundStyle(Nova.gold).font(.caption) }
            if playing { Image(systemName: "speaker.wave.2.fill").foregroundStyle(Nova.accent).font(.caption) }
        }.padding(.vertical, 4)
    }
}

/// Full-screen live TV. Swipe up / down: next / previous channel (▲▼ on the remote). Tap: the channel info and buttons.
struct LiveFullScreen: View {
    @EnvironmentObject var library: Library
    @ObservedObject private var live = LivePlayer.shared
    @State private var showInfo = true
    @State private var hideTask: Task<Void, Never>?
    @State private var drag: CGFloat = 0
    @State private var fill = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            LiveVideo(fill: fill).ignoresSafeArea().offset(y: drag / 4)
            if showInfo, let c = live.channel {
                VStack {
                    HStack(spacing: 12) {
                        Button { live.fullScreen = false } label: { Image(systemName: "xmark").font(.headline).padding(12).background(.black.opacity(0.5), in: Circle()) }
                        NetImage(url: c.logo, fallback: c.name, fit: true).frame(width: 52, height: 36)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(c.name).font(.headline).lineLimit(1)
                            if c.num > 0 { Text("Channel \(c.num)").font(.caption).foregroundStyle(Nova.muted) }
                        }
                        Spacer()
                        Button { library.toggleFavorite(Prefs.liveKey(c)) } label: {
                            Image(systemName: library.prefs.isFavorite(Prefs.liveKey(c)) ? "star.fill" : "star").font(.headline)
                                .foregroundStyle(library.prefs.isFavorite(Prefs.liveKey(c)) ? Nova.gold : .white).padding(12).background(.black.opacity(0.5), in: Circle())
                        }
                        Button { fill.toggle() } label: {
                            Image(systemName: fill ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right").font(.headline).padding(12).background(.black.opacity(0.5), in: Circle())
                        }
                        if live.previous != nil {
                            Button { live.flipBack(); poke() } label: { Image(systemName: "arrow.uturn.backward").font(.headline).padding(12).background(.black.opacity(0.5), in: Circle()) }
                        }
                    }
                    .padding(.horizontal, 20).padding(.top, 12)
                    .background(LinearGradient(colors: [.black.opacity(0.75), .clear], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
                    Spacer()
                    Text("Swipe up or down to change channel").font(.caption).foregroundStyle(Nova.muted).padding(.bottom, 16)
                }.foregroundStyle(.white).transition(.opacity)
            }
        }
        .statusBarHidden()
        .contentShape(Rectangle())
        .onTapGesture { withAnimation { showInfo.toggle() }; if showInfo { poke() } }
        .gesture(DragGesture(minimumDistance: 30)
            .onChanged { v in if abs(v.translation.height) > abs(v.translation.width) { drag = v.translation.height } }
            .onEnded { v in
                let h = v.translation.height
                withAnimation(.easeOut(duration: 0.2)) { drag = 0 }
                guard abs(h) > 60, abs(h) > abs(v.translation.width) else { return }
                live.step(h < 0 ? 1 : -1)            // up: next channel, down: previous (like ▲▼)
                withAnimation { showInfo = true }; poke()
            })
        .onAppear { poke(); rotate(landscape: true) }
        .onDisappear { rotate(landscape: false) }
    }

    /// The info hides by itself after a few seconds.
    private func poke() {
        hideTask?.cancel()
        hideTask = Task { try? await Task.sleep(nanoseconds: 4_000_000_000); if !Task.isCancelled { withAnimation { showInfo = false } } }
    }

    private func rotate(landscape: Bool) {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
        if #available(iOS 16.0, *) {
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: landscape ? .landscapeRight : .portrait)) { _ in }
        }
    }
}
