import XCTest
@testable import StickyKit

final class SignalTests: XCTestCase {
    func samples(_ observed: Double, needed: Double, now: Date, dropped: [Int] = []) -> [SignalSample] {
        (0..<10).map { i in SignalSample(at: now.addingTimeInterval(Double(i - 9)), observedBps: observed, indicatedBps: needed,
                                          droppedFrames: dropped.isEmpty ? 0 : dropped[min(i, dropped.count - 1)], stalls: 0) }
    }

    func testLevels() {
        let now = Date()
        XCTAssertEqual(SignalMeter.level(samples(12e6, needed: 6e6, now: now), lastStall: nil, now: now), .strong)
        XCTAssertEqual(SignalMeter.level(samples(7e6, needed: 6e6, now: now), lastStall: nil, now: now), .ok)
        XCTAssertEqual(SignalMeter.level(samples(4e6, needed: 6e6, now: now), lastStall: nil, now: now), .weak)
        XCTAssertEqual(SignalMeter.level(samples(12e6, needed: 6e6, now: now), lastStall: now.addingTimeInterval(-30), now: now), .weak, "dropped out just now")
        XCTAssertEqual(SignalMeter.level(samples(12e6, needed: 6e6, now: now), lastStall: now.addingTimeInterval(-600), now: now), .strong, "long ago")
        XCTAssertEqual(SignalMeter.level([], lastStall: nil, now: now), .none)
        XCTAssertEqual(SignalMeter.level(samples(8e6, needed: 0, now: now), lastStall: nil, now: now), .strong, "speed needed unknown")
    }

    func testSmoothness() {
        let now = Date()
        XCTAssertEqual(SignalMeter.smoothness(samples(1, needed: 1, now: now)), 100)
        XCTAssertEqual(SignalMeter.smoothness(samples(1, needed: 1, now: now, dropped: [0, 27])), 90, "27 of 270 frames dropped")
    }

    func testStoreAndCushion() {
        let s = SignalStore(defaults: UserDefaults(suiteName: "s-\(UUID())")!)
        XCTAssertNil(s.level(5)); s.remember(5, .ok); XCTAssertEqual(s.level(5), .ok)
        for i in 0..<35 { s.note("ESPN", "Dropped out \(i)") }
        XCTAssertEqual(s.problems.count, 30); XCTAssertEqual(s.problems.first?.what, "Dropped out 34", "newest first")
        XCTAssertEqual([0, 1, 2, 3, 9].map(Cushion.seconds(afterStalls:)), [0, 8, 15, 25, 25])
    }
}
