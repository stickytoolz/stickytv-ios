import SwiftUI
import StickyKit

/// The coloured dot for a channel's signal (green strong, yellow good, red weak), from the last time it played.
struct SignalDot: View {
    let level: SignalLevel?
    var body: some View {
        if let level, level != .none {
            Circle().fill(SignalDot.color(level)).frame(width: 6, height: 6)
        }
    }
    static func color(_ l: SignalLevel) -> Color { switch l { case .strong: Color.green; case .ok: Nova.gold; case .weak: Nova.live; case .none: Nova.faint } }
}

/// The Channel signal window (as on the Fire TV): how strong this channel's signal is, live.
struct SignalWindow: View {
    @ObservedObject var live = LivePlayer.shared
    let onClose: () -> Void
    var body: some View {
        let last = live.samples.last
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("CHANNEL SIGNAL").font(.system(size: 13, weight: .heavy)).tracking(1)
                Spacer()
                Button(action: onClose) { Image(systemName: "xmark").font(.caption.bold()).padding(7).background(.white.opacity(0.12), in: Circle()) }.buttonStyle(.plain)
            }
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(1...3, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 2).fill(live.level.rawValue >= i ? SignalDot.color(live.level) : .white.opacity(0.15))
                        .frame(width: 8, height: CGFloat(6 + i * 6))
                }
                Text(live.level.label).font(.headline).foregroundStyle(SignalDot.color(live.level)).padding(.leading, 6)
            }
            // the last minute: how fast it arrived (line) against what the picture needs (dashes)
            SpeedGraph(samples: live.samples).frame(height: 60)
            Group {
                if let last {
                    Text("Arriving at \(mbps(last.observedBps))" + (last.indicatedBps > 0 ? " · needs \(mbps(last.indicatedBps))" : ""))
                }
                if live.pictureSize.width > 0 { Text("Picture \(Int(live.pictureSize.width))×\(Int(live.pictureSize.height)) · HLS") }
                Text("Smoothness \(SignalMeter.smoothness(live.samples))% of frames shown")
                Text("Dropped out: " + (live.stalls == 0 ? "not once" : live.stalls == 1 ? "once" : "\(live.stalls) times"))
            }.font(.caption).foregroundStyle(Nova.muted)
        }
        .foregroundStyle(.white).padding(14).frame(width: 300)
        .background(.black.opacity(0.82), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Nova.line))
    }
    private func mbps(_ b: Double) -> String { String(format: "%.1f Mbps", b / 1_000_000) }
}

struct SpeedGraph: View {
    let samples: [SignalSample]
    var body: some View {
        GeometryReader { g in
            let top = max(samples.map { max($0.observedBps, $0.indicatedBps) }.max() ?? 1, 1) * 1.15
            let step = g.size.width / 59
            let x0 = g.size.width - CGFloat(max(samples.count - 1, 0)) * step
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.05))
                if let need = samples.last?.indicatedBps, need > 0 {
                    Path { p in let y = g.size.height * (1 - need / top); p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: g.size.width, y: y)) }
                        .stroke(Nova.gold.opacity(0.7), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }
                Path { p in
                    for (i, s) in samples.enumerated() {
                        let pt = CGPoint(x: x0 + CGFloat(i) * step, y: g.size.height * (1 - s.observedBps / top))
                        if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
                    }
                }.stroke(Nova.accent, lineWidth: 2)
            }
        }
    }
}
