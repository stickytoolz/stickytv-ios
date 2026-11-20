import XCTest
@testable import StickyKit

/// The same awkward provider answers the Fire TV app is tested with.
final class ProviderTests: XCTestCase {
    func testServerAddresses() {
        XCTAssertEqual(XtreamAPI.normalizeServer("example.com:8080"), "http://example.com:8080")
        XCTAssertEqual(XtreamAPI.normalizeServer("http://example.com:8080/"), "http://example.com:8080")
        XCTAssertEqual(XtreamAPI.normalizeServer("http://example.com:8080/get.php?username=a&password=b"), "http://example.com:8080")
        XCTAssertEqual(XtreamAPI.normalizeServer("https://example.com/panel/player_api.php"), "https://example.com/panel")
        XCTAssertEqual(XtreamAPI.normalizeServer("  HTTP://Example.com  "), "http://Example.com")
    }

    func testM3uLink() {
        let a = XtreamAPI.parseM3uLink("http://tv.example.com:80/get.php?username=joe&password=pw&type=m3u_plus")
        XCTAssertEqual(a?.username, "joe"); XCTAssertEqual(a?.password, "pw"); XCTAssertEqual(a?.server, "http://tv.example.com:80")
        XCTAssertNil(XtreamAPI.parseM3uLink("http://tv.example.com/"))
    }

    func testNames() {
        XCTAssertEqual(cleanName("  ESPN\n HD  "), "ESPN HD")
        XCTAssertNil(cleanName("null")); XCTAssertNil(cleanName("   ")); XCTAssertNil(cleanName(nil))
        XCTAssertEqual(cleanName(String(repeating: "a", count: 200))?.count, 118)
        XCTAssertEqual(cleanName("Already fine"), "Already fine")
    }

    func testChannelsArrayOrObjectAndSloppyTypes() {
        let arr = #"[{"num":1,"name":"ESPN","stream_id":"101","stream_icon":"http://x/l.png","epg_channel_id":"espn.us","category_id":"1.0","tv_archive":1},"#
            + #" {"name":"No id"}, {"stream_id":101,"name":"dup"}, {"stream_id":"102.0","name":null,"category_id":2,"stream_icon":"logo.png"}]"#
        let ch = XtreamAPI.parseChannels(Data(arr.utf8))
        XCTAssertEqual(ch.map(\.id), [101, 102])
        XCTAssertEqual(ch[0].categoryId, "1"); XCTAssertTrue(ch[0].hasArchive); XCTAssertEqual(ch[0].epgId, "espn.us")
        XCTAssertEqual(ch[1].name, "Channel 102"); XCTAssertNil(ch[1].logo, "not an http picture"); XCTAssertEqual(ch[1].categoryId, "2")
        let obj = #"{"a":{"stream_id":5,"name":"A"},"b":{"stream_id":6,"name":"B"}}"#
        XCTAssertEqual(Set(XtreamAPI.parseChannels(Data(obj.utf8)).map(\.id)), [5, 6])
        XCTAssertTrue(XtreamAPI.parseChannels(Data("<html>bad gateway</html>".utf8)).isEmpty)
    }

    func testMoviesAndShows() {
        let mv = #"[{"stream_id":1000,"name":"Neon Horizon","rating":"8.1","added":"1700000000","category_id":"13","container_extension":"mkv","tmdb":"5001"},"#
            + #"{"stream_id":1001,"name":"Bad","rating":"77","container_extension":"m p 4!"}]"#
        let m = XtreamAPI.parseMovies(Data(mv.utf8))
        XCTAssertEqual(m[0].tmdb, 5001); XCTAssertEqual(m[0].ext, "mkv"); XCTAssertEqual(m[0].rating, 8.1)
        XCTAssertEqual(m[1].rating, 0, "out of range"); XCTAssertEqual(m[1].ext, "mp4")
        let se = #"[{"series_id":2000,"name":"Harbor Lights","releaseDate":"2024-03-01","backdrop_path":["","http://x/b.jpg"],"rating":"7.7"}]"#
        let s = XtreamAPI.parseSeries(Data(se.utf8))
        XCTAssertEqual(s[0].year, "2024"); XCTAssertEqual(s[0].backdrop, "http://x/b.jpg")
    }

    func testEpisodesInEveryShape() {
        func eps(_ json: String) -> [Int: [Episode]] {
            XtreamAPI.parseSeriesDetail(XtreamAPI.object(Data(json.utf8))).seasons
        }
        let a = eps(#"{"episodes":{"1":[{"id":"11","episode_num":2,"title":"B"},{"id":"10","episode_num":1,"title":"A"}],"2":[{"id":"21","episode_num":1}]}}"#)
        XCTAssertEqual(a[1]?.map(\.title), ["A", "B"]); XCTAssertEqual(a[2]?.count, 1)
        let b = eps(#"{"episodes":{"1":{"0":{"id":"5","episode_num":1}}}}"#)
        XCTAssertEqual(b[1]?.first?.id, "5")
        let c = eps(#"{"episodes":[[{"id":7.0,"episode_num":1}],[{"id":8,"episode_num":1}]]}"#)
        XCTAssertEqual(c[1]?.first?.id, "7"); XCTAssertEqual(c[2]?.first?.id, "8")
        XCTAssertTrue(eps(#"{"episodes":[]}"#).isEmpty)
    }

    func testTrailerAndTmdb() {
        XCTAssertEqual(youtubeId("https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=3"), "dQw4w9WgXcQ")
        XCTAssertEqual(youtubeId("https://youtu.be/dQw4w9WgXcQ"), "dQw4w9WgXcQ")
        XCTAssertEqual(youtubeId("dQw4w9WgXcQ"), "dQw4w9WgXcQ")
        XCTAssertNil(youtubeId("")); XCTAssertNil(youtubeId("null"))
        XCTAssertEqual(tmdbId("550"), 550); XCTAssertEqual(tmdbId("550.0"), 550); XCTAssertEqual(tmdbId("abc"), 0)
    }

    func testStreamAddresses() {
        let api = XtreamAPI(account: Account(name: "x", server: "http://h:8080", username: "u s", password: "p/w"))
        XCTAssertEqual(api.liveURL(5).absoluteString, "http://h:8080/live/u%20s/p%2Fw/5.m3u8")
    }

    func testFavoritesAndAccounts() {
        let d = UserDefaults(suiteName: "test-\(UUID())")!
        let p = Prefs(defaults: d)
        XCTAssertTrue(p.toggleFavorite("live:1")); XCTAssertTrue(p.isFavorite("live:1"))
        XCTAssertFalse(p.toggleFavorite("live:1")); XCTAssertFalse(p.isFavorite("live:1"))
        let a = Account(name: "A", server: "http://a", username: "u", password: "p")
        p.saveAccount(a); XCTAssertEqual(p.activeAccount, a)
        p.watched(3); p.watched(4); p.watched(3)
        XCTAssertEqual(p.recentChannels, [3, 4])
        p.savePosition("m", 100, 7200); XCTAssertEqual(p.position("m"), 100)
        p.savePosition("m", 7180, 7200); XCTAssertEqual(p.position("m"), 0, "finished: starts over")
    }

    func testPlaylistCacheRoundTrip() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let c = PlaylistCache(account: Account(name: "A", server: "http://a", username: "u", password: "p"), folder: dir)
        var p = PlaylistData()
        p.channels = [Channel(id: 1, num: 1, name: "One", logo: nil, epgId: nil, categoryId: "1", hasArchive: false)]
        c.write(p)
        XCTAssertEqual(c.read()?.channels.first?.name, "One")
    }
}
