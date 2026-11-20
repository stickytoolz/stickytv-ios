import Foundation

/// A channel's signal strength, worked out from what the player measures every second (as the Fire TV app's dots and
/// Channel signal window): the speed the stream arrives at against the speed it needs, and whether it dropped out.
public struct SignalSample: Codable, Hashable {
    public var at: Date
    public var observedBps: Double      // how fast it's arriving
    public var indicatedBps: Double     // how fast it needs to arrive (0 = unknown)
    public var droppedFrames: Int
    public var stalls: Int              // times it stopped to wait, so far on this channel
    public init(at: Date, observedBps: Double, indicatedBps: Double, droppedFrames: Int, stalls: Int) {
        self.at = at; self.observedBps = observedBps; self.indicatedBps = indicatedBps; self.droppedFrames = droppedFrames; self.stalls = stalls
    }
}

public enum SignalLevel: Int, Codable, Comparable {
    case none = 0, weak = 1, ok = 2, strong = 3
    public static func < (a: SignalLevel, b: SignalLevel) -> Bool { a.rawValue < b.rawValue }
    public var label: String { switch self { case .none: "No signal"; case .weak: "Weak"; case .ok: "Good"; case .strong: "Strong" } }
}

public enum SignalMeter {
    /// Strength from the last minute of samples: a dropout in the last two minutes makes it weak; otherwise how far the
    /// arriving speed is above what the picture needs.
    public static func level(_ samples: [SignalSample], lastStall: Date?, now: Date = Date()) -> SignalLevel {
        let recent = samples.filter { now.timeIntervalSince($0.at) <= 60 }
        guard let last = recent.last, last.observedBps > 0 else { return recent.isEmpty ? .none : .weak }
        if let s = lastStall, now.timeIntervalSince(s) < 120 { return .weak }
        let observed = recent.map(\.observedBps).reduce(0, +) / Double(recent.count)
        let needed = last.indicatedBps
        if needed <= 0 { return observed > 6_000_000 ? .strong : observed > 2_500_000 ? .ok : .weak }
        let ratio = observed / needed
        return ratio >= 1.6 ? .strong : ratio >= 1.05 ? .ok : .weak
    }

    /// Frames shown smoothly, in percent, between two samples (dropped frames lower it).
    public static func smoothness(_ samples: [SignalSample], fps: Double = 30) -> Int {
        guard let first = samples.first, let last = samples.last, last.at > first.at else { return 100 }
        let expected = last.at.timeIntervalSince(first.at) * fps
        let dropped = Double(max(last.droppedFrames - first.droppedFrames, 0))
        return max(0, min(100, Int(((expected - dropped) / max(expected, 1) * 100).rounded())))
    }
}

/// Every channel's last strength (for the dots), and a log of stream problems (Settings › Stream health).
public final class SignalStore {
    let d: UserDefaults
    public init(defaults: UserDefaults = .standard) { d = defaults }

    public func level(_ channelId: Int) -> SignalLevel? { (d.object(forKey: "signal.\(channelId)") as? Int).flatMap(SignalLevel.init(rawValue:)) }
    public func remember(_ channelId: Int, _ l: SignalLevel) { d.set(l.rawValue, forKey: "signal.\(channelId)") }

    public struct Problem: Codable, Hashable, Identifiable {
        public var at: Date
        public var channel: String
        public var what: String          // "Dropped out", "Reconnected", "Refused (403)"…
        public var id: String { "\(at.timeIntervalSince1970)|\(channel)|\(what)" }
    }
    /// The last 30 problems, newest first.
    public var problems: [Problem] { (d.data(forKey: "streamProblems").flatMap { try? JSONDecoder().decode([Problem].self, from: $0) }) ?? [] }
    public func note(_ channel: String, _ what: String, at: Date = Date()) {
        let list = [Problem(at: at, channel: channel, what: what)] + problems
        if let data = try? JSONEncoder().encode(Array(list.prefix(30))) { d.set(data, forKey: "streamProblems") }
    }
    public func clearProblems() { d.removeObject(forKey: "streamProblems") }
}

/// The weak-signal cushion (Settings › Player): after each dropout it saves more ahead before carrying on —
/// 8, then 15, then 25 seconds (kept while the app is open).
public enum Cushion {
    public static let steps: [Double] = [8, 15, 25]
    public static func seconds(afterStalls n: Int) -> Double { n <= 0 ? 0 : steps[min(n, steps.count) - 1] }
}
