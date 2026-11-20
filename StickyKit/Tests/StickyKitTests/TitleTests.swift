import XCTest
@testable import StickyKit

final class TitleTests: XCTestCase {
    func testTidy() {
        let a = cleanTitle("EN - The Matrix (1999) [4K]")
        XCTAssertEqual(a.title, "The Matrix"); XCTAssertEqual(a.year, "1999"); XCTAssertEqual(a.quality, "4K")
        let b = cleanTitle("|EN| Spider-Man: No Way Home (2021) (HD)")
        XCTAssertEqual(b.title, "Spider-Man: No Way Home"); XCTAssertEqual(b.year, "2021"); XCTAssertEqual(b.quality, "HD")
        XCTAssertEqual(cleanTitle("1917").title, "1917")
        XCTAssertNil(cleanTitle("1917").year)
        XCTAssertEqual(cleanTitle("Up").title, "Up")
        XCTAssertEqual(cleanTitle("FR: Amélie 2001").title, "Amélie")
        XCTAssertEqual(cleanTitle("FR: Amélie 2001").year, "2001")
        XCTAssertEqual(cleanTitle("Sub Zero").title, "Zero", "quality words go, as on the Fire TV")
        XCTAssertEqual(cleanTitle("Oasis: Don't Look Back in Anger").title, "Oasis: Don't Look Back in Anger")
        XCTAssertEqual(cleanTitle("  ").title, "  ", "nothing left: the original")
        XCTAssertEqual(cleanTitle("Dune Part Two - ").title, "Dune Part Two")
    }
}
