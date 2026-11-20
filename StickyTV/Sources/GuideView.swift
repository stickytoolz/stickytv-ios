import SwiftUI
import StickyKit

private let favCat = "__fav", recentCat = "__recent", allCat = "__all"
private let slot: TimeInterval = 30 * 60

/// Live TV in guide mode, as on the Fire TV (the default): the highlighted programme's details and the preview window at
/// the top, the categories, then the guide grid (channels down the left, programmes across two hours, the time along the
/// top). ◀ ▶ (or a swipe across the grid) moves through time. Tap a programme to see it; tap one that's on now to watch
/// it in the preview, and again for full screen.
struct GuideView: View {
    @EnvironmentObject var library: Library
    @ObservedObject private var live = LivePlayer.shared
    @AppStorage("liveCat") private var cat = allCat
    @Binding var guideMode: Bool
    @State private var windowStart = GuideView.roundedNow()
    @State private var picked: (channel: Channel, program: Program?)?
    @State private var swipe: CGFloat = 0

    static func roundedNow() -> Date { Date(timeIntervalSince1970: (Date().timeIntervalSince1970 / slot).rounded(.down) * slot) }

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
        GeometryReader { geo in
            let windowLen: TimeInterval = geo.size.width > 640 ? 2 * 3600 : 1.5 * 3600
            VStack(spacing: 0) {
                top.frame(height: max(geo.size.height * 0.40, 130))
                categoryBar
                grid(windowLen: windowLen)
            }
        }
        .background(Nova.bg.ignoresSafeArea())
        .onAppear { if picked == nil, let c = live.channel { picked = (c, library.nowNext(c).now) } }
    }

    // MARK: the top: details and preview

    private var top: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text("LIVE TV").font(.system(size: 18, weight: .black)).foregroundStyle(Nova.text)
                    ModeSwitch(guideMode: $guideMode)
                }
                if let p = picked {
                    Text(p.channel.name).font(.caption.bold()).foregroundStyle(Nova.accent).lineLimit(1)
                    if let pr = p.program {
                        Text(pr.title).font(.system(size: 18, weight: .heavy)).foregroundStyle(Nova.text).lineLimit(2)
                        HStack(spacing: 6) {
                            if pr.isLive(Date()) { Tag(text: "Now", color: Nova.live) }
                            Text("\(whenText(pr.start)) – \(timeText(pr.end))").font(.caption).foregroundStyle(Nova.muted)
                        }
                        if let d = pr.desc { Text(d).font(.caption).foregroundStyle(Nova.muted).lineLimit(3) }
                    } else {
                        Text(library.guideStatus ?? "No guide for this channel").font(.caption).foregroundStyle(Nova.muted)
                    }
                } else {
                    Text("Tap a channel or a show.").font(.caption).foregroundStyle(Nova.muted)
                    if let s = library.guideStatus { Text(s).font(.caption).foregroundStyle(Nova.muted) }
                }
                Spacer(minLength: 0)
            }.frame(maxWidth: .infinity, alignment: .leading)
            ZStack {
                if live.channel != nil {
                    LiveVideo().contentShape(Rectangle()).onTapGesture { live.fullScreen = true }
                        .overlay(alignment: .topTrailing) {
                            Image(systemName: "arrow.up.left.and.arrow.down.right").font(.caption.bold()).padding(6)
                                .background(.black.opacity(0.5), in: Circle()).padding(5)
                        }
                } else {
                    Nova.panel
                    Text("Tap a channel to watch it here").font(.caption).foregroundStyle(Nova.muted)
                }
            }
            .aspectRatio(16 / 9, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Nova.line))
        }
        .padding(.leading, 14).padding(.trailing, 14).padding(.top, 24).padding(.bottom, 6)
    }

    private var categoryBar: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(cats, id: \.0) { id, name in Chip(text: name, selected: id == cat) { cat = id }.id(id) }
                }.padding(.horizontal, 14).padding(.vertical, 5)
            }
            .onAppear { proxy.scrollTo(cat, anchor: .center) }
        }
    }

    // MARK: the grid

    private let channelW: CGFloat = 150
    private let rowH: CGFloat = 44

    private func grid(windowLen: TimeInterval) -> some View {
        GeometryReader { g in
            let w = g.size.width - channelW
            let end = windowStart.addingTimeInterval(windowLen)
            VStack(spacing: 0) {
                // the times along the top, with ◀ ▶
                HStack(spacing: 0) {
                    HStack(spacing: 6) {
                        Button { move(-1) } label: { Image(systemName: "chevron.left").font(.caption.bold()).frame(width: 30, height: 24).background(Nova.panel, in: Capsule()) }
                        Button { windowStart = GuideView.roundedNow() } label: { Text("Now").font(.caption2.bold()).frame(width: 40, height: 24).background(Nova.panel, in: Capsule()) }
                        Button { move(1) } label: { Image(systemName: "chevron.right").font(.caption.bold()).frame(width: 30, height: 24).background(Nova.panel, in: Capsule()) }
                    }.buttonStyle(.plain).foregroundStyle(Nova.text).frame(width: channelW)
                    ZStack(alignment: .topLeading) {
                        ForEach(0..<Int(windowLen / slot), id: \.self) { i in
                            let t = windowStart.addingTimeInterval(Double(i) * slot)
                            Text(i == 0 && !Calendar.current.isDateInToday(t) ? whenText(t) : timeText(t))
                                .font(.caption2.bold()).foregroundStyle(Nova.muted)
                                .offset(x: CGFloat(Double(i) * slot / windowLen) * w + 4)
                        }
                    }.frame(width: w, height: 24, alignment: .leading).clipped()
                }.padding(.vertical, 3)
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 3) {
                            let list = channels
                            ForEach(list) { c in
                                row(c, list: list, w: w, end: end, windowLen: windowLen).id(c.id)
                            }
                        }.padding(.bottom, 16)
                    }
                    .overlay(alignment: .topLeading) {
                        // the red "now" line
                        let now = Date()
                        if now > windowStart && now < end {
                            Rectangle().fill(Nova.live).frame(width: 2).offset(x: channelW + CGFloat(now.timeIntervalSince(windowStart) / windowLen) * w)
                                .allowsHitTesting(false)
                        }
                    }
                    .onAppear { if let id = live.channel?.id { proxy.scrollTo(id, anchor: .center) } }
                }
            }
            .offset(x: swipe)
            .simultaneousGesture(DragGesture(minimumDistance: 24)
                .onChanged { v in if abs(v.translation.width) > abs(v.translation.height) * 1.5 { swipe = v.translation.width / 6 } }
                .onEnded { v in
                    withAnimation(.easeOut(duration: 0.15)) { swipe = 0 }
                    guard abs(v.translation.width) > 60, abs(v.translation.width) > abs(v.translation.height) * 1.5 else { return }
                    move(v.translation.width < 0 ? 1 : -1)      // swipe left: later, swipe right: earlier
                })
        }
    }

    /// ◀ ▶: half an hour earlier or later (from an hour back up to a day ahead).
    private func move(_ by: Int) {
        let next = windowStart.addingTimeInterval(Double(by) * slot)
        let earliest = GuideView.roundedNow().addingTimeInterval(-2 * slot)
        let latest = GuideView.roundedNow().addingTimeInterval(22 * 3600)
        withAnimation(.easeOut(duration: 0.15)) { windowStart = min(max(next, earliest), latest) }
    }

    private func row(_ c: Channel, list: [Channel], w: CGFloat, end: Date, windowLen: TimeInterval) -> some View {
        let _ = library.guideVersion
        let progs = library.programs(for: c).filter { $0.end > windowStart && $0.start < end }
        let playing = live.channel?.id == c.id
        return HStack(spacing: 0) {
            // the channel: logo, number, name, star
            HStack(spacing: 6) {
                NetImage(url: c.logo, fallback: c.name, fit: true).frame(width: 34, height: 24).padding(2)
                    .background(Color(red: 0.04, green: 0.06, blue: 0.11), in: RoundedRectangle(cornerRadius: 6))
                VStack(alignment: .leading, spacing: 0) {
                    if c.num > 0 { Text("\(c.num)").font(.system(size: 9).monospacedDigit()).foregroundStyle(Nova.faint) }
                    MarqueeText(text: c.name, font: .system(size: 11, weight: .semibold), active: playing)
                }
                if library.prefs.isFavorite(Prefs.liveKey(c)) { Image(systemName: "star.fill").font(.system(size: 8)).foregroundStyle(Nova.gold) }
            }
            .padding(.horizontal, 6).frame(width: channelW, height: rowH, alignment: .leading)
            .background(playing ? Nova.accent.opacity(0.16) : Nova.panel, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
            .onTapGesture { tapped(c, list: list, program: library.nowNext(c).now) }
            .contextMenu {
                Button { library.toggleFavorite(Prefs.liveKey(c)) } label: {
                    library.prefs.isFavorite(Prefs.liveKey(c)) ? Label("Remove from Favourites", systemImage: "star.slash") : Label("Add to Favourites", systemImage: "star")
                }
            }
            // the programmes across the window
            ZStack(alignment: .leading) {
                if progs.isEmpty {
                    Text(library.guideStatus != nil ? "Loading guide…" : "No listings").font(.caption2).foregroundStyle(Nova.faint)
                        .padding(.horizontal, 8).frame(width: w - 4, height: rowH, alignment: .leading)
                        .background(Nova.panel.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
                        .onTapGesture { tapped(c, list: list, program: nil) }
                }
                ForEach(progs, id: \.start) { pr in
                    let x0 = CGFloat(max(pr.start.timeIntervalSince(windowStart), 0) / windowLen) * w
                    let x1 = CGFloat(min(pr.end.timeIntervalSince(windowStart), windowLen) / windowLen) * w
                    let isPicked = picked?.channel.id == c.id && picked?.program?.start == pr.start
                    let onNow = pr.isLive(Date())
                    Text(pr.title).font(.system(size: 11, weight: onNow ? .bold : .medium)).lineLimit(2)
                        .foregroundStyle(onNow ? Nova.text : Nova.text.opacity(0.75))
                        .padding(.horizontal, 6)
                        .frame(width: max(x1 - x0 - 3, 2), height: rowH, alignment: .leading)
                        .background(isPicked ? Nova.accent.opacity(0.3) : (onNow ? Nova.panelHi : Nova.panel.opacity(0.7)), in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(isPicked ? Nova.accent : .clear, lineWidth: 1.5))
                        .clipped()
                        .offset(x: x0)
                        .onTapGesture { tapped(c, list: list, program: pr) }
                }
            }
            .frame(width: w, height: rowH, alignment: .leading).padding(.leading, 3)
        }
        .padding(.horizontal, 4)
    }

    /// Tap: show its details; a show on now plays in the preview; again (the same one): full screen.
    private func tapped(_ c: Channel, list: [Channel], program: Program?) {
        let samePick = picked?.channel.id == c.id && picked?.program?.start == program?.start
        picked = (c, program)
        let isNow = program.map { $0.isLive(Date()) } ?? true
        guard isNow else { return }                               // a later show: just its details
        if live.channel?.id == c.id { if samePick || program == nil { live.fullScreen = true } }
        else { live.play(c, in: list) }
    }
}

/// "Guide | List" (Live TV's two layouts, as in the Fire TV's settings).
struct ModeSwitch: View {
    @Binding var guideMode: Bool
    var body: some View {
        HStack(spacing: 0) {
            ForEach([true, false], id: \.self) { g in
                Button { guideMode = g } label: {
                    Text(g ? "Guide" : "List").font(.caption2.bold()).padding(.horizontal, 10).padding(.vertical, 5)
                        .foregroundStyle(guideMode == g ? Color.black : Nova.muted)
                        .background(guideMode == g ? Nova.accent : .clear, in: Capsule())
                }.buttonStyle(.plain)
            }
        }.padding(2).background(Nova.panel, in: Capsule())
    }
}
