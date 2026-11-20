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
    @State private var picking = false

    private var games: [Game] {
        _ = library.teamsVersion
        let mine = library.myTeamIds
        let base: [Game]
        switch league {
        case allLeagues: base = library.games
        case myTeams: return library.myTeamGames()          // on now and coming up, soonest first
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
                Button { picking = true } label: {
                    Label("My Teams", systemImage: "star.fill").font(.caption.bold()).padding(.horizontal, 12).padding(.vertical, 7)
                        .foregroundStyle(Nova.gold).background(Nova.gold.opacity(0.14), in: Capsule())
                }.buttonStyle(.plain)
            }.padding(.horizontal, 16).padding(.top, 6).padding(.trailing, 70)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) { ForEach(leagues, id: \.0) { id, name in Chip(text: name, selected: league == id) { league = id } } }
                    .padding(.horizontal, 16).padding(.vertical, 8)
            }
            let list = games
            if list.isEmpty {
                if library.scoresLoading && library.games.isEmpty { VStack { Spacer(); ProgressView("Getting today's games…").tint(Nova.accent); Spacer() }.frame(maxWidth: .infinity) }
                else if league == myTeams {
                    VStack(spacing: 12) {
                        EmptyState(title: library.prefs.myTeams.isEmpty ? "No teams picked yet" : "No games for your teams today",
                                   body_: "Pick your teams, or press and hold any game to add its teams.")
                        NeonButton(title: "Pick My Teams", icon: "star.fill") { picking = true }
                    }.frame(maxWidth: .infinity)
                    Spacer()
                }
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
                await library.refreshSchedules()
                nowTitles = library.nowTitles()
                try? await Task.sleep(nanoseconds: 60_000_000_000)
            }
        }
        .onChange(of: library.guideVersion) { _ in nowTitles = library.nowTitles() }
        .sheet(isPresented: $picking) { TeamPickerSheet().environmentObject(library) }
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
                    Text(whenText(game.start)).font(.caption.bold()).foregroundStyle(Nova.text)
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

/// Pick My Teams: search every league (NFL, NBA, NHL, MLB, college, soccer…), tap a team to add or remove it.
struct TeamPicker: View {
    @EnvironmentObject var library: Library
    @State private var query = ""
    @State private var league = "__all"
    var showsTitle = true

    private var mine: [Team] { _ = library.teamsVersion; return library.prefs.myTeams }
    private var results: [Team] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return library.allTeams.filter { t in
            (league == "__all" || t.league == league) &&
            (q.isEmpty || t.name.lowercased().contains(q) || t.abbr.lowercased() == q || t.short.lowercased().contains(q))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if showsTitle { Text("MY TEAMS").font(.system(size: 20, weight: .black)).foregroundStyle(Nova.text) }
            if !mine.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(mine) { t in
                            Button { library.toggleTeam(t) } label: {
                                HStack(spacing: 6) {
                                    NetImage(url: t.logo, fallback: t.abbr, fit: true).frame(width: 20, height: 20)
                                    Text(t.short).font(.caption.bold())
                                    Image(systemName: "xmark.circle.fill").font(.caption).foregroundStyle(Nova.muted)
                                }.padding(.horizontal, 10).padding(.vertical, 6).background(Nova.gold.opacity(0.15), in: Capsule())
                                    .overlay(Capsule().stroke(Nova.gold.opacity(0.5)))
                            }.buttonStyle(.plain).foregroundStyle(Nova.text)
                        }
                    }
                }
            }
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(Nova.muted)
                TextField("Search teams (e.g. Knicks, Arsenal, Italy)", text: $query).textInputAutocapitalization(.never).autocorrectionDisabled()
                if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Nova.muted) } }
            }.padding(10).background(Nova.panel, in: RoundedRectangle(cornerRadius: 12))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    Chip(text: "All leagues", selected: league == "__all") { league = "__all" }
                    ForEach(League.all.filter { $0.sport != "mma" }) { l in Chip(text: l.name, selected: league == l.id) { league = l.id } }
                }
            }
            if library.teamsLoading && library.allTeams.isEmpty {
                ProgressView("Getting the teams…").tint(Nova.accent).frame(maxWidth: .infinity).padding(20)
            } else if library.allTeams.isEmpty {
                Text("Couldn't get the team list. Check the internet connection.").font(.caption).foregroundStyle(Nova.live)
            } else {
                let picked = Set(mine.map(\.id))
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 8)], spacing: 8) {
                    ForEach(results.prefix(300)) { t in
                        Button { library.toggleTeam(t) } label: {
                            HStack(spacing: 8) {
                                NetImage(url: t.logo, fallback: t.abbr, fit: true).frame(width: 26, height: 26)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(t.name).font(.caption.bold()).foregroundStyle(Nova.text).lineLimit(1)
                                    Text(League.all.first { $0.id == t.league }?.name ?? "").font(.system(size: 10)).foregroundStyle(Nova.muted)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: picked.contains(t.id) ? "star.fill" : "star").foregroundStyle(picked.contains(t.id) ? Nova.gold : Nova.faint)
                            }.padding(8).background(Nova.panel, in: RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(picked.contains(t.id) ? Nova.gold.opacity(0.5) : Nova.line))
                        }.buttonStyle(.plain)
                    }
                }
            }
        }
        .task { await library.loadTeams() }
    }
}

/// The picker on its own page (from Sports).
struct TeamPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        ZStack(alignment: .topTrailing) {
            ScrollView { TeamPicker().padding(20) }
            Button { dismiss() } label: { Text("Done").bold().padding(.horizontal, 16).padding(.vertical, 8).background(Nova.accent, in: Capsule()).foregroundStyle(.black) }
                .padding(16)
        }.background(Nova.bg.ignoresSafeArea())
    }
}

/// "7:30 PM" today, "Tomorrow 7:30 PM", "Sat Nov 29 1:00 PM" later.
func whenText(_ d: Date) -> String {
    let cal = Calendar.current
    if cal.isDateInToday(d) { return timeText(d) }
    if cal.isDateInTomorrow(d) { return "Tomorrow \(timeText(d))" }
    let f = DateFormatter(); f.dateFormat = "EEE MMM d"
    return "\(f.string(from: d)) \(timeText(d))"
}
