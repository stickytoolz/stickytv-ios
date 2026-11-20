import XCTest
@testable import StickyKit

final class GuideTests: XCTestCase {
    func testTimes() {
        let a = parseXmltvTime("20261102183000 +0000")!
        XCTAssertEqual(a.timeIntervalSince1970, 1793644200)
        XCTAssertEqual(parseXmltvTime("20261102133000 -0500"), a, "same moment in New York")
        XCTAssertEqual(parseXmltvTime("20261102183000"), a, "no zone: UTC")
        XCTAssertEqual(parseXmltvTime("202611021830 +0000"), a, "no seconds")
        XCTAssertNil(parseXmltvTime("soon")); XCTAssertNil(parseXmltvTime(nil))
    }

    func testNames() {
        XCTAssertEqual(GuideMatch.normalizeName("US| ESPN HD"), "espn")
        XCTAssertEqual(GuideMatch.normalizeName("[UK] - Sky Sports News"), "skysportsnews")
        XCTAssertEqual(GuideMatch.idToName("ESPN.HD.us2"), "ESPN HD")
        XCTAssertEqual(GuideMatch.idToName("Sky.Sports.Main.Event.uk"), "Sky Sports Main Event")
        XCTAssertTrue(GuideMatch.keysFor("US: Fox News Channel HD").contains("foxnews"))
    }

    let xml = """
    <?xml version="1.0" encoding="UTF-8"?>
    <tv>
      <channel id="ESPN.us"><display-name>ESPN</display-name></channel>
      <channel id="foxnews.us"><display-name>Fox News Channel</display-name></channel>
      <programme start="20261102180000 +0000" stop="20261102190000 +0000" channel="ESPN.us"><title>SportsCenter</title><desc>Highlights &amp; news</desc></programme>
      <programme start="20261102190000 +0000" stop="20261102210000 +0000" channel="ESPN.us"><title><![CDATA[Monday Night Football]]></title></programme>
      <programme start="20261102185000 +0000" stop="20261102193000 +0000" channel="ESPN.us"><title>Overlap</title></programme>
      <programme start="20261102180000 +0000" stop="20261102190000 +0000" channel="foxnews.us"><title>The Five</title></programme>
      <programme start="20261102180000 +0000" stop="20261102190000 +0000" channel="other"><title>Not wanted</title></programme>
    </tv>
    """

    func testParseAndMatchByIdAndName() {
        let from = parseXmltvTime("20261102000000")!, to = parseXmltvTime("20261103000000")!
        // ESPN by its guide id; Fox News has no guide id in the playlist: matched by name
        let p = GuideParser(wanted: ["espn.us"], from: from, to: to, names: GuideMatch.keysFor("US| Fox News HD"))
        let r = p.parse(Data(xml.utf8))
        let espn = r.programs["espn.us"]!
        XCTAssertEqual(espn.map(\.title), ["SportsCenter", "Overlap", "Monday Night Football"])
        XCTAssertEqual(espn[0].desc, "Highlights & news")
        XCTAssertEqual(espn[1].end, espn[2].start, "an overlap ends when the next show starts")
        XCTAssertNotNil(r.nameLinks["foxnews"]); XCTAssertEqual(r.programs["foxnews.us"]?.first?.title, "The Five")
        XCTAssertNil(r.programs["other"])
    }

    func testDamagedGuideKeepsWhatWasRead() {
        let broken = xml.replacingOccurrences(of: "</tv>", with: "<programme start=")
        let r = GuideParser(wanted: ["espn.us"], from: .distantPast, to: .distantFuture).parse(Data(broken.utf8))
        XCTAssertEqual(r.programs["espn.us"]?.count, 3)
    }

    func testGzippedGuide() {
        // a real .gz file (with a file name in its header, as guide sites send)
        let gz = Data(base64Encoded: "H4sICAAAAAAC/2d1aWRlLnhtbACzKSmzs0nOSMzLS81RyEyxVUpU0rez0QeKAgBkqo25GgAAAA==")!
        XCTAssertEqual(gunzip(gz).flatMap { String(data: $0, encoding: .utf8) }, "<tv><channel id=\"a\"/></tv>")
        XCTAssertNil(gunzip(Data("not gzip".utf8)))
    }
}
