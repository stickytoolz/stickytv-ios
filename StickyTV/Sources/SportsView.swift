import SwiftUI
import StickyKit

private let allLeagues = "__all", myTeams = "__mine"

/// Sports, as on the Fire TV: today's games with live scores (from ESPN), the channels showing each one, and My Teams first.
struct SportsView: View {
    @EnvironmentObject var library: Library
    @ObservedObject private var live = LivePlayer.shared
    @State private var league = allLeagues
    @State private var nowTitles: [Int: String] = [:]
    @State private var notFound: Game?

    private var games: [Game] {
        _ = library.teamsVersion
        let mine = library.myTeamIds
        let base: [Game]
        switch league {
        case allLeagues: base = library.games
        case myTeams: base = library.games.filter { mine.contains($0.home.id) || mine.contains($0.away.id) }
        default: base = library.games.filter { $0.league.id == league }
        }
        return Sports.sorted(base, myTeams: mine)
    }
    private var leagues: [(String, String)] {
        let have = Set(library.games.map(\.league.id))
        return [(allLeagues, "All"), (myTeams, "★ My Teams")] + League.all.filter { have.contains($0.id) }.map { ($0.id, $0.name) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Text("SPORTS").font(.system(size: 20, weight: .black)).foregroundStyle(Nova.text)
                if let t = library.scoresUpdated { Text("Scores \(timeText(t))").font(.caption).foregroundStyle(Nova.muted) }
                if library.scoresLoading { ProgressView().scaleEffect(0.7).tint(Nova.accent) }
                Spacer()
            }.padding(.horizontal, 16).padding(.top, 6).padding(.trailing, 70)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) { ForEach(leagues, id: \.0) { id, name in Chip(text: name, selected: league == id) { league = id } } }
                    .padding(.horizontal, 16).padding(.vertical, 8)
            }
            let list = games
            if list.isEmpty {
                if library.scoresLoading && library.games.isEmpty { VStack { Spacer(); ProgressView("Getting today's games…").tint(Nova.accent); Spacer() }.frame(maxWidth: .infinity) }
                else if league == myTeams { EmptyState(title: "No games for your teams today", body_: "Press and hold any game to add its teams to My Teams."); Spacer() }
                else { EmptyState(title: "No games right now", body_: "Today's games appear here with live scores."); Spacer() }
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 12)], spacing: 12) {
                        ForEach(list) { g in
                            let chs = library.channels(for: g, nowTitles: nowTitles)
                            GameCard(game: g, channels: chs, mine: library.myTeamIds) { c in
                                live.play(c, in: chs); live.fullScreen = true
                            }
                            .onTapGesture {
                                if let c = chs.first { live.play(c, in: chs); live.fullScreen = true } else { notFound = g }
                            }
                            .contextMenu {
                                ForEach([g.away, g.home], id: \.id) { t in
                                    Button { library.toggleTeam(t) } label: {
                                        library.myTeamIds.contains(t.id) ? Label("Remove \(t.short) from My Teams", systemImage: "star.slash") : Label("Add \(t.short) to My Teams", systemImage: "star")
                                    }
                                }
                            }
                        }
                    }.padding(.horizontal, 16).padding(.bottom, 20)
                }
            }
        }
        .background(Nova.bg.ignoresSafeArea())
        .task {
            // scores every minute while Sports is open
            while !Task.isCancelled {
                await library.refreshScores()
                nowTitles = library.nowTitles()
                try? await Task.sleep(nanoseconds: 60_000_000_000)
            }
        }
        .onChange(of: library.guideVersion) { _ in nowTitles = library.nowTitles() }
        .alert("Not on your channels", isPresented: Binding(get: { notFound != nil }, set: { if !$0 { notFound = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            if let g = notFound {
                Text("Couldn't find a channel showing \(g.title)." + (g.networks.isEmpty ? "" : " It's on \(g.networks.joined(separator: ", ")) — try Search."))
            }
        }
    }
}

struct GameCard: View {
    let game: Game
    let channels: [Channel]
    let mine: Set<String>
    let watch: (Channel) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(game.league.name.uppercased()).font(.system(size: 10, weight: .heavy)).tracking(0.8).foregroundStyle(Nova.muted)
                Spacer()
                switch game.state {
                case .live:
                    HStack(spacing: 4) { Circle().fill(Nova.live).frame(width: 7, height: 7); Text(game.detail).font(.caption.bold()).foregroundStyle(Nova.live) }
                case .pre:
                    Text(timeText(game.start)).font(.caption.bold()).foregroundStyle(Nova.text)
                case .post:
                    Text(game.detail.isEmpty ? "Final" : game.detail).font(.caption.bold()).foregroundStyle(Nova.muted)
                }
            }
            teamRow(game.away, game.awayScore, winning: (Int(game.awayScore ?? "") ?? 0) > (Int(game.homeScore ?? "") ?? 0))
            teamRow(game.home, game.homeScore, winning: (Int(game.homeScore ?? "") ?? 0) > (Int(game.awayScore ?? "") ?? 0))
            if channels.isEmpty {
                Text(game.networks.isEmpty ? "No channel found" : "On \(game.networks.prefix(3).joined(separator: ", "))").font(.caption2).foregroundStyle(Nova.faint)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(channels.prefix(4)) { c in
                            Button { watch(c) } label: {
                                Label(c.name, systemImage: "play.fill").font(.system(size: 11, weight: .bold)).lineLimit(1)
                                    .padding(.horizontal, 9).padding(.vertical, 6)
                                    .foregroundStyle(Nova.accent).background(Nova.accent.opacity(0.13), in: Capsule())
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(Nova.panel, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(game.state == .live ? Nova.live.opacity(0.5) : (isMine ? Nova.gold.opacity(0.5) : Nova.line)))
        .contentShape(RoundedRectangle(cornerRadius: 16))
    }

    private var isMine: Bool { mine.contains(game.home.id) || mine.contains(game.away.id) }

    private func teamRow(_ t: Team, _ score: String?, winning: Bool) -> some View {
        HStack(spacing: 10) {
            NetImage(url: t.logo, fallback: t.abbr, fit: true).frame(width: 26, height: 26)
            Text(t.short).font(.subheadline.weight(winning || game.state == .pre ? .bold : .regular)).foregroundStyle(Nova.text).lineLimit(1)
            if mine.contains(t.id) { Image(systemName: "star.fill").font(.system(size: 9)).foregroundStyle(Nova.gold) }
            Spacer()
            if let score { Text(score).font(.system(size: 18, weight: .heavy).monospacedDigit()).foregroundStyle(winning ? Nova.text : Nova.muted) }
        }
    }
}
