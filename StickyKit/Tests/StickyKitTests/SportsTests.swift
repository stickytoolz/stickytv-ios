import XCTest
@testable import StickyKit

final class SportsTests: XCTestCase {
    let nfl = League("nfl", "NFL", "football")

    let board = """
    {"events":[
     {"id":"401","date":"2026-11-22T21:25Z","competitions":[{"competitors":[
        {"homeAway":"home","score":"17","team":{"id":"2","displayName":"Buffalo Bills","shortDisplayName":"Bills","abbreviation":"BUF","logo":"https://x/buf.png"}},
        {"homeAway":"away","score":"21","team":{"id":"12","displayName":"Kansas City Chiefs","shortDisplayName":"Chiefs","abbreviation":"KC"}}],
       "status":{"type":{"state":"in","shortDetail":"Q3 4:12"}},
       "broadcasts":[{"names":["CBS"]}]}]},
     {"id":"402","date":"2026-11-23T01:20Z","competitions":[{"competitors":[
        {"homeAway":"home","score":"0","team":{"id":"21","displayName":"Philadelphia Eagles","shortDisplayName":"Eagles","abbreviation":"PHI"}},
        {"homeAway":"away","score":"0","team":{"id":"6","displayName":"Dallas Cowboys","shortDisplayName":"Cowboys","abbreviation":"DAL"}}],
       "status":{"type":{"state":"pre","shortDetail":"8:20 PM"}},
       "geoBroadcasts":[{"media":{"shortName":"NBC"}}]}]},
     {"id":"bad","competitions":[]}
    ]}
    """

    func testScoreboard() {
        let g = Sports.parseScoreboard(Data(board.utf8), league: nfl)
        XCTAssertEqual(g.count, 2)
        XCTAssertEqual(g[0].title, "Chiefs @ Bills")
        XCTAssertEqual(g[0].state, .live); XCTAssertEqual(g[0].detail, "Q3 4:12")
        XCTAssertEqual(g[0].homeScore, "17"); XCTAssertEqual(g[0].awayScore, "21")
        XCTAssertEqual(g[0].home.logo, "https://x/buf.png"); XCTAssertEqual(g[0].away.id, "nfl:12")
        XCTAssertEqual(g[0].networks, ["CBS"])
        XCTAssertNil(g[1].homeScore, "no score before the game")
        XCTAssertEqual(g[1].networks, ["NBC"])
        XCTAssertTrue(Sports.parseScoreboard(Data("<html>".utf8), league: nfl).isEmpty)
    }

    func testChannelsForAGame() {
        let g = Sports.parseScoreboard(Data(board.utf8), league: nfl)[0]
        func ch(_ id: Int, _ name: String) -> Channel { Channel(id: id, num: id, name: name, logo: nil, epgId: nil, categoryId: "1", hasArchive: false) }
        let list = [ch(1, "US| CBS HD"), ch(2, "NFL 01: Chiefs @ Bills 4:25PM"), ch(3, "US| ESPN"), ch(4, "Local Sports"), ch(5, "NFL 02: Cowboys @ Eagles")]
        let found = Sports.channels(for: g, in: list) { $0.id == 4 ? "NFL Football: Kansas City Chiefs at Buffalo Bills" : nil }
        XCTAssertEqual(found.map(\.id), [2, 4, 1], "event channel, then the guide, then the network")
    }

    func testMyTeamsFirst() {
        let g = Sports.parseScoreboard(Data(board.utf8), league: nfl)
        XCTAssertEqual(Sports.sorted(g, myTeams: []).first?.id, "nfl:401", "live first")
        XCTAssertEqual(Sports.sorted(g, myTeams: ["nfl:21"]).first?.id, "nfl:402", "your team's game first")
    }

    func testTeamList() {
        let json = #"{"sports":[{"leagues":[{"teams":[{"team":{"id":"18","displayName":"New York Knicks","shortDisplayName":"Knicks","abbreviation":"NY","logos":[{"href":"https://x/ny.png"}]}},{"team":{"id":"2","displayName":"Boston Celtics","shortDisplayName":"Celtics","abbreviation":"BOS"}}]}]}]}"#
        let t = Sports.parseTeams(Data(json.utf8), league: League("nba", "NBA", "basketball"))
        XCTAssertEqual(t.map(\.short), ["Celtics", "Knicks"], "sorted by name")
        XCTAssertEqual(t[1].id, "nba:18"); XCTAssertEqual(t[1].logo, "https://x/ny.png")
    }

    func testHiddenCategoriesAndTeamsAreKept() {
        let p = Prefs(defaults: UserDefaults(suiteName: "t-\(UUID())")!)
        p.hiddenCategories = ["live:7"]; XCTAssertEqual(p.hiddenCategories, ["live:7"])
        let knicks = Team(id: "nba:18", name: "New York Knicks", short: "Knicks", abbr: "NY", logo: nil, league: "nba")
        p.toggleTeam(knicks); XCTAssertEqual(p.myTeams.map(\.id), ["nba:18"])
        p.toggleTeam(knicks); XCTAssertTrue(p.myTeams.isEmpty)
        XCTAssertTrue(p.liveScores, "on unless turned off")
    }
}
