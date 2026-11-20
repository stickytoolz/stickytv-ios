import SwiftUI
import StickyKit

private let favCat = "__fav", recentCat = "__recent", allCat = "__all"

/// Live TV, laid out as on the Fire TV: categories on the left, the channels (with what's on) in the middle, and the
/// preview window with the programme details on the right. Tap a channel to watch it in the preview; tap it again (or the
/// preview) for full screen. Press and hold a channel for Favourites.
struct LiveView: View {
    @EnvironmentObject var library: Library
    @ObservedObject private var live = LivePlayer.shared
    @AppStorage("liveCat") private var cat = allCat
    /// Guide (the grid, as the Fire TV opens with) or List (categories, channels, preview).
    @AppStorage("liveGuide") private var guideMode = true

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
        if guideMode { GuideView(guideMode: $guideMode) } else { listMode }
    }

    private var listMode: some View {
        HStack(spacing: 0) {
            categories.frame(width: 148)
            Divider().overlay(Nova.line)
            channelList.frame(maxWidth: .infinity)
            Divider().overlay(Nova.line)
            preview.frame(width: 268)
        }
        .padding(.top, 24)
        .background(Nova.bg.ignoresSafeArea())
    }

    // MARK: categories

    private var categories: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    Text("LIVE TV").font(.system(size: 18, weight: .black)).foregroundStyle(Nova.text).padding(.horizontal, 12)
                    ModeSwitch(guideMode: $guideMode).padding(.horizontal, 8).padding(.bottom, 6)
                    ForEach(cats, id: \.0) { id, name in
                        Button { cat = id } label: {
                            Text(name).font(.system(size: 13, weight: id == cat ? .bold : .medium)).lineLimit(2).multilineTextAlignment(.leading)
                                .foregroundStyle(id == cat ? Nova.accent : Nova.text)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).padding(.vertical, 9)
                                .background(id == cat ? Nova.accent.opacity(0.13) : .clear, in: RoundedRectangle(cornerRadius: 10))
                        }.buttonStyle(.plain).id(id)
                    }
                }.padding(.horizontal, 6).padding(.bottom, 16)
            }
            .onAppear { proxy.scrollTo(cat, anchor: .center) }
        }
    }

    // MARK: channels

    @ViewBuilder private var channelList: some View {
        if case .loading(let msg) = library.state, library.channels.isEmpty {
            VStack { Spacer(); ProgressView(msg).tint(Nova.accent); Spacer() }
        } else if case .failed(let msg) = library.state, library.channels.isEmpty {
            EmptyState(title: "Couldn't load your channels", body_: msg)
        } else if channels.isEmpty {
            EmptyState(title: "Nothing here", body_: cat == favCat ? "Press and hold a channel to add it to Favourites." : "This category is empty.")
        } else {
            let list = channels
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(list) { c in
                            ChannelRow(channel: c, playing: live.channel?.id == c.id, favorite: library.prefs.isFavorite(Prefs.liveKey(c)))
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    if live.channel?.id == c.id { live.fullScreen = true } else { live.play(c, in: list) }
                                }
                                .contextMenu {
                                    Button { library.toggleFavorite(Prefs.liveKey(c)) } label: {
                                        library.prefs.isFavorite(Prefs.liveKey(c)) ? Label("Remove from Favourites", systemImage: "star.slash") : Label("Add to Favourites", systemImage: "star")
                                    }
                                    Button { live.play(c, in: list); live.fullScreen = true } label: { Label("Watch full screen", systemImage: "arrow.up.left.and.arrow.down.right") }
                                }
                                .id(c.id)
                        }
                    }.padding(.horizontal, 8).padding(.bottom, 16)
                }
                .onAppear { if let id = live.channel?.id { proxy.scrollTo(id, anchor: .center) } }
            }
        }
    }

    // MARK: preview

    private var preview: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                if live.channel != nil {
                    LiveVideo().contentShape(Rectangle()).onTapGesture { live.fullScreen = true }
                        .overlay(alignment: .topTrailing) {
                            Image(systemName: "arrow.up.left.and.arrow.down.right").font(.caption.bold()).padding(7)
                                .background(.black.opacity(0.5), in: Circle()).padding(6)
                        }
                } else {
                    Nova.panel
                    Text("Tap a channel to watch it here").font(.caption).foregroundStyle(Nova.muted)
                }
            }
            .aspectRatio(16 / 9, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Nova.line))
            if let c = live.channel {
                ProgrammeInfo(channel: c)
            }
            Spacer(minLength: 0)
        }.padding(.horizontal, 12).padding(.top, 8)
    }
}

/// What's on now and next on a channel (from the TV guide).
struct ProgrammeInfo: View {
    let channel: Channel
    @EnvironmentObject var library: Library
    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { ctx in
            let _ = library.guideVersion
            let nn = library.nowNext(channel, at: ctx.date)
            VStack(alignment: .leading, spacing: 6) {
                Text(channel.name).font(.headline).foregroundStyle(Nova.text).lineLimit(1)
                if let now = nn.now {
                    HStack(spacing: 6) {
                        Tag(text: "Now", color: Nova.live)
                        Text("\(timeText(now.start)) – \(timeText(now.end))").font(.caption).foregroundStyle(Nova.muted)
                    }
                    Text(now.title).font(.subheadline.bold()).foregroundStyle(Nova.text).lineLimit(2)
                    ProgressBar(value: now.progress(ctx.date))
                    if let d = now.desc { Text(d).font(.caption).foregroundStyle(Nova.muted).lineLimit(4) }
                } else if let s = library.guideStatus {
                    Text(s).font(.caption).foregroundStyle(Nova.muted)
                } else {
                    Text("No guide for this channel").font(.caption).foregroundStyle(Nova.faint)
                }
                if let next = nn.next {
                    Text("Next  \(timeText(next.start))  \(next.title)").font(.caption).foregroundStyle(Nova.muted).lineLimit(1)
                }
            }
        }
    }
}

struct ProgressBar: View {
    let value: Double
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.15))
                Capsule().fill(Nova.accent).frame(width: g.size.width * min(max(value, 0), 1))
            }
        }.frame(height: 3)
    }
}

struct ChannelRow: View {
    let channel: Channel
    let playing: Bool
    let favorite: Bool
    @EnvironmentObject var library: Library
    var body: some View {
        let _ = library.guideVersion
        let now = library.nowNext(channel).now
        HStack(spacing: 10) {
            NetImage(url: channel.logo, fallback: channel.name, fit: true)
                .frame(width: 40, height: 26).padding(3).background(Color(red: 0.04, green: 0.06, blue: 0.11), in: RoundedRectangle(cornerRadius: 7))
                .clipShape(RoundedRectangle(cornerRadius: 7))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    if channel.num > 0 { Text("\(channel.num)").font(.system(size: 11).monospacedDigit()).foregroundStyle(Nova.faint) }
                    // the playing channel's name scrolls when it's too long (like the highlighted row on the Fire TV)
                    MarqueeText(text: channel.name, font: .system(size: 13, weight: .semibold), active: playing)
                    if favorite { Image(systemName: "star.fill").foregroundStyle(Nova.gold).font(.system(size: 9)) }
                    if playing { Image(systemName: "speaker.wave.2.fill").foregroundStyle(Nova.accent).font(.system(size: 10)) }
                }
                if let now {
                    MarqueeText(text: now.title, font: .system(size: 11), color: Nova.muted, active: playing)
                    ProgressBar(value: now.progress(Date())).frame(maxWidth: 160)
                }
            }
        }
        .padding(.horizontal, 7).padding(.vertical, 5)
        .background(playing ? Nova.accent.opacity(0.12) : Nova.panel.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(playing ? Nova.accent.opacity(0.7) : .clear))
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
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        Button { live.fullScreen = false } label: { Image(systemName: "xmark").font(.headline).padding(12).background(.black.opacity(0.5), in: Circle()) }
                        Spacer()
                        Button { library.toggleFavorite(Prefs.liveKey(c)) } label: {
                            Image(systemName: library.prefs.isFavorite(Prefs.liveKey(c)) ? "star.fill" : "star").font(.headline)
                                .foregroundStyle(library.prefs.isFavorite(Prefs.liveKey(c)) ? Nova.gold : .white).padding(12).background(.black.opacity(0.5), in: Circle())
                        }
                        Button { fill.toggle() } label: {
                            Image(systemName: fill ? "rectangle.arrowtriangle.2.inward" : "rectangle.arrowtriangle.2.outward").font(.headline).padding(12).background(.black.opacity(0.5), in: Circle())
                        }
                        if live.previous != nil {
                            Button { live.flipBack(); poke() } label: { Image(systemName: "arrow.uturn.backward").font(.headline).padding(12).background(.black.opacity(0.5), in: Circle()) }
                        }
                    }
                    .padding(.horizontal, 24).padding(.top, 12)
                    Spacer()
                    // the channel info bar along the bottom, as on the Fire TV
                    HStack(alignment: .top, spacing: 14) {
                        NetImage(url: c.logo, fallback: c.name, fit: true).frame(width: 70, height: 48).padding(4)
                            .background(Color(red: 0.04, green: 0.06, blue: 0.11), in: RoundedRectangle(cornerRadius: 10))
                        ProgrammeInfo(channel: c)
                        Spacer(minLength: 0)
                        Text("Swipe up or down\nto change channel").font(.caption2).foregroundStyle(Nova.faint).multilineTextAlignment(.trailing)
                    }
                    .padding(16)
                    .background(LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
                }.foregroundStyle(.white).transition(.opacity)
            }
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .contentShape(Rectangle())
        .onTapGesture { withAnimation { showInfo.toggle() }; if showInfo { poke() } }
        .gesture(DragGesture(minimumDistance: 30)
            .onChanged { v in if abs(v.translation.height) > abs(v.translation.width) { drag = v.translation.height } }
            .onEnded { v in
                let h = v.translation.height
                withAnimation(.easeOut(duration: 0.2)) { drag = 0 }
                guard abs(h) > 50, abs(h) > abs(v.translation.width) else { return }
                live.step(h < 0 ? 1 : -1)            // up: next channel, down: previous (like ▲▼)
                withAnimation { showInfo = true }; poke()
            })
        .onAppear { poke() }
    }

    /// The info hides by itself after a few seconds.
    private func poke() {
        hideTask?.cancel()
        let secs = UInt64(max(library.prefs.overlaySecs, 2))
        hideTask = Task { try? await Task.sleep(nanoseconds: secs * 1_000_000_000); if !Task.isCancelled { withAnimation { showInfo = false } } }
    }
}
