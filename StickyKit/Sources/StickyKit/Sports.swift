import Foundation

/// Games and live scores from ESPN's public scoreboards, matched to the channels that show them (as on the Fire TV):
/// the provider's event channels ("NFL 01: Chiefs @ Bills"), a guide programme naming both teams, or the TV network
/// ESPN lists (ESPN, FOX, TNT…) found among the channels.
public struct League: Hashable, Identifiable {
    public let id: String          // "nfl"
    public let name: String        // "NFL"
    public let sport: String       // "football"
    public init(_ id: String, _ name: String, _ sport: String) { self.id = id; self.name = name; self.sport = sport }

    public static let all: [League] = [
        League("nfl", "NFL", "football"), League("college-football", "College Football", "football"),
        League("nba", "NBA", "basketball"), League("wnba", "WNBA", "basketball"), League("mens-college-basketball", "College Basketball", "basketball"),
        League("nhl", "NHL", "hockey"), League("mlb", "MLB", "baseball"),
        League("eng.1", "Premier League", "soccer"), League("usa.1", "MLS", "soccer"), League("uefa.champions", "Champions League", "soccer"),
        League("esp.1", "La Liga", "soccer"), League("ita.1", "Serie A", "soccer"), League("ger.1", "Bundesliga", "soccer"), League("fra.1", "Ligue 1", "soccer"),
        League("fifa.world", "World Cup", "soccer"), League("ufc", "UFC", "mma"),
    ]
}

public struct Team: Codable, Hashable, Identifiable {
    public var id: String           // ESPN id, with the league: "nfl:12"
    public var name: String         // "Kansas City Chiefs"
    public var short: String        // "Chiefs"
    public var abbr: String         // "KC"
    public var logo: String?
    public var league: String
}

public struct Game: Hashable, Identifiable {
    public enum State: String { case pre, live = "in", post }
    public var id: String
    public var league: League
    public var start: Date
    public var state: State
    public var detail: String        // "Q3 4:12", "Final", "8:20 PM"
    public var home: Team
    public var away: Team
    public var homeScore: String?
    public var awayScore: String?
    public var networks: [String]    // "ESPN", "ABC"
    public var title: String { "\(away.short) @ \(home.short)" }
}

public enum Sports {
    public static var base = "https://site.api.espn.com"

    public static func scoreboardURL(_ l: League, day: Date = Date()) -> URL {
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd"; f.timeZone = .current
        let sportPath = l.sport == "mma" ? "mma" : l.sport
        return URL(string: "\(base)/apis/site/v2/sports/\(sportPath)/\(l.id)/scoreboard?dates=\(f.string(from: day))")!
    }

    public static func teamsURL(_ l: League) -> URL {
        URL(string: "\(base)/apis/site/v2/sports/\(l.sport)/\(l.id)/teams?limit=1000")!
    }

    /// Every team in a league (for picking My Teams).
    public static func parseTeams(_ data: Data, league: League) -> [Team] {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? JSONObj,
              let sport = (root["sports"] as? [Any])?.first as? JSONObj,
              let lg = (sport["leagues"] as? [Any])?.first as? JSONObj,
              let teams = lg["teams"] as? [Any] else { return [] }
        return teams.compactMap { ($0 as? JSONObj)?.obj("team") }.compactMap { t in
            guard let id = t.str("id") else { return nil }
            let name = t.str("displayName") ?? t.str("name") ?? "?"
            return Team(id: "\(league.id):\(id)", name: name, short: t.str("shortDisplayName") ?? name,
                        abbr: t.str("abbreviation") ?? "", logo: (t["logos"] as? [Any])?.compactMap { ($0 as? JSONObj)?.str("href") }.first, league: league.id)
        }.sorted { $0.name < $1.name }
    }

    /// One league's games today (lenient: anything missing is skipped).
    public static func parseScoreboard(_ data: Data, league: League) -> [Game] {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? JSONObj, let events = root["events"] as? [Any] else { return [] }
        let iso = ISO8601DateFormatter()
        let isoNoSec = DateFormatter(); isoNoSec.dateFormat = "yyyy-MM-dd'T'HH:mm'Z'"; isoNoSec.timeZone = TimeZone(identifier: "UTC")
        return events.compactMap { $0 as? JSONObj }.compactMap { e in
            guard let id = e.str("id"), let comp = (e["competitions"] as? [Any])?.first as? JSONObj,
                  let comps = comp["competitors"] as? [Any], comps.count >= 2 else { return nil }
            let ds = e.str("date") ?? comp.str("date") ?? ""
            guard let start = iso.date(from: ds) ?? isoNoSec.date(from: ds) else { return nil }
            func team(_ c: JSONObj) -> (Team, String?, String)? {
                guard let t = c.obj("team") ?? c.obj("athlete"), let tid = t.str("id") else { return nil }
                let name = t.str("displayName") ?? t.str("name") ?? "?"
                let short = t.str("shortDisplayName") ?? t.str("name") ?? name
                let logo = t.str("logo") ?? (t["logos"] as? [Any])?.compactMap { ($0 as? JSONObj)?.str("href") }.first ?? t.obj("flag")?.str("href")
                let score = (c["score"] as? JSONObj)?.str("displayValue") ?? c.str("score")
                return (Team(id: "\(league.id):\(tid)", name: name, short: short, abbr: t.str("abbreviation") ?? String(short.prefix(3)).uppercased(),
                             logo: logo, league: league.id), score, c.str("homeAway") ?? "")
            }
            let parsed = comps.compactMap { $0 as? JSONObj }.compactMap(team)
            guard parsed.count >= 2 else { return nil }
            let home = parsed.first { $0.2 == "home" } ?? parsed[0]
            let away = parsed.first { $0.2 == "away" && $0.0 != home.0 } ?? parsed.first { $0.0 != home.0 } ?? parsed[1]
            let st = (comp.obj("status") ?? e.obj("status"))?.obj("type")
            let state = Game.State(rawValue: st?.str("state") ?? "pre") ?? .pre
            var nets: [String] = []
            for b in (comp["broadcasts"] as? [Any]) ?? [] { nets += ((b as? JSONObj)?["names"] as? [String]) ?? [] }
            for g in (comp["geoBroadcasts"] as? [Any]) ?? [] { if let n = (g as? JSONObj)?.obj("media")?.str("shortName") { nets.append(n) } }
            var seen = Set<String>()
            nets = nets.filter { seen.insert($0.lowercased()).inserted }
            return Game(id: "\(league.id):\(id)", league: league, start: start, state: state,
                        detail: st?.str("shortDetail") ?? st?.str("detail") ?? "", home: home.0, away: away.0,
                        homeScore: state == .pre ? nil : home.1, awayScore: state == .pre ? nil : away.1, networks: nets)
        }
    }

    /// TV networks as ESPN writes them → as channel names are usually written (both normalised).
    static let networkAliases: [String: String] = [
        "nflnet": "nflnetwork", "nflnetwork": "nflnetwork", "fs1": "fs1", "foxsports1": "fs1", "fs2": "fs2", "cbssn": "cbssportsnetwork",
        "usanet": "usanetwork", "usa": "usanetwork", "nbcsn": "nbcsports", "espnu": "espnu", "secn": "secnetwork", "secnetwork": "secnetwork",
        "accn": "accnetwork", "btn": "bignetwork", "bigtennetwork": "bigtennetwork", "mlbn": "mlbnetwork", "mlbnet": "mlbnetwork", "nhlnet": "nhlnetwork",
        "tnt": "tnt", "tbs": "tbs", "trutv": "trutv", "abc": "abc", "cbs": "cbs", "nbc": "nbc", "fox": "fox", "espn": "espn", "espn2": "espn2",
    ]

    /// Words that identify a team in a channel or programme name ("chiefs", "kansas city chiefs").
    static func teamWords(_ t: Team) -> [String] {
        let short = t.short.lowercased(), full = t.name.lowercased()
        var w = [full, short]
        if let last = full.split(separator: " ").last, last.count >= 4 { w.append(String(last)) }     // "Lakers"
        return Array(Set(w.filter { $0.count >= 3 }))
    }

    /// Channels that show [g], best first: an event channel naming both teams, a channel whose programme now names both
    /// teams, then the networks ESPN lists.
    public static func channels(for g: Game, in channels: [Channel], programmeNow: (Channel) -> String?) -> [Channel] {
        let hw = teamWords(g.home), aw = teamWords(g.away)
        func both(_ s: String) -> Bool { let l = s.lowercased(); return hw.contains { l.contains($0) } && aw.contains { l.contains($0) } }
        var out: [Channel] = []
        var seen = Set<Int>()
        func add(_ c: Channel) { if seen.insert(c.id).inserted { out.append(c) } }
        for c in channels where both(c.name) { add(c) }
        if g.state != .post {
            for c in channels { if let t = programmeNow(c), both(t) { add(c) } }
        }
        let wanted = g.networks.map { n -> String in let k = GuideMatch.normalizeName(n); return networkAliases[k] ?? k }
        if !wanted.isEmpty {
            for net in wanted {
                for c in channels where GuideMatch.normalizeName(c.name) == net { add(c) }
            }
        }
        return Array(out.prefix(8))
    }

    /// The order on the Sports page: your teams' games first, then live, then about to start, then finished.
    public static func sorted(_ games: [Game], myTeams: Set<String>) -> [Game] {
        func rank(_ g: Game) -> Int {
            let mine = myTeams.contains(g.home.id) || myTeams.contains(g.away.id)
            let s = g.state == .live ? 0 : g.state == .pre ? 1 : 2
            return (mine ? 0 : 3) + s
        }
        return games.sorted { rank($0) != rank($1) ? rank($0) < rank($1) : $0.start < $1.start }
    }
}
