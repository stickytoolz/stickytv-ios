import SwiftUI

/// The Fire TV app's look: deep navy, neon cyan, a red for live.
enum Nova {
    static let bg = Color(red: 0.035, green: 0.047, blue: 0.094)
    static let bg2 = Color(red: 0.055, green: 0.071, blue: 0.137)
    static let panel = Color(red: 0.075, green: 0.094, blue: 0.176)
    static let panelHi = Color(red: 0.11, green: 0.14, blue: 0.25)
    static let line = Color.white.opacity(0.08)
    static let text = Color.white
    static let muted = Color.white.opacity(0.62)
    static let faint = Color.white.opacity(0.35)
    static let accent = Color(red: 0.0, green: 0.898, blue: 1.0)
    static let live = Color(red: 1.0, green: 0.27, blue: 0.36)
    static let gold = Color(red: 1.0, green: 0.78, blue: 0.25)
}

/// A picture from the internet, with initials while it loads or when there is none.
struct NetImage: View {
    let url: String?
    var fallback: String = ""
    var fit = false
    var body: some View {
        if let s = url, let u = URL(string: s) {
            AsyncImage(url: u, transaction: Transaction(animation: .easeOut(duration: 0.15))) { phase in
                switch phase {
                case .success(let img): if fit { img.resizable().scaledToFit() } else { img.resizable().scaledToFill() }
                default: Monogram(name: fallback)
                }
            }
        } else {
            Monogram(name: fallback)
        }
    }
}

/// Initials on a colour made from the name (channels and people with no picture).
struct Monogram: View {
    let name: String
    var body: some View {
        ZStack {
            LinearGradient(colors: [hashColor(name).opacity(0.85), hashColor(name).opacity(0.35)], startPoint: .topLeading, endPoint: .bottomTrailing)
            if !name.isEmpty {
                Text(initials(name)).font(.system(size: 15, weight: .heavy, design: .rounded)).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.5).padding(4)
            }
        }
    }
}

func initials(_ s: String) -> String {
    let words = s.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).filter { !$0.isEmpty }
    if words.count >= 2 { return String(words[0].prefix(1) + words[1].prefix(1)).uppercased() }
    return String(words.first?.prefix(3) ?? "?").uppercased()
}

func hashColor(_ s: String) -> Color {
    var h: UInt32 = 5381
    for u in s.unicodeScalars { h = (h &* 33) &+ u.value }
    return Color(hue: Double(h % 360) / 360, saturation: 0.55, brightness: 0.62)
}

/// A small coloured label ("2025", "★ 8.1", "LIVE").
struct Tag: View {
    let text: String
    var color: Color = Nova.accent
    var body: some View {
        Text(text.uppercased()).font(.system(size: 11, weight: .bold)).tracking(0.6)
            .foregroundStyle(color).padding(.horizontal, 8).padding(.vertical, 4)
            .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 6))
    }
}

/// A rounded chip for categories and sort choices.
struct Chip: View {
    let text: String
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(text).font(.system(size: 14, weight: selected ? .bold : .medium)).lineLimit(1)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .foregroundStyle(selected ? Color.black : Nova.text)
                .background(selected ? Nova.accent : Nova.panel, in: Capsule())
                .overlay(Capsule().stroke(selected ? Color.clear : Nova.line))
        }.buttonStyle(.plain)
    }
}

struct SectionTitle: View {
    let text: String
    var trailing: String? = nil
    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2).fill(Nova.accent).frame(width: 4, height: 14)
            Text(text.uppercased()).font(.system(size: 13, weight: .heavy)).tracking(1).foregroundStyle(Nova.text)
            if let trailing { Text(trailing).font(.system(size: 12)).foregroundStyle(Nova.muted) }
            Spacer()
        }
    }
}

struct EmptyState: View {
    let title: String
    let body_: String
    var body: some View {
        VStack(spacing: 8) {
            Text(title).font(.title3.bold()).foregroundStyle(Nova.text)
            Text(body_).font(.subheadline).foregroundStyle(Nova.muted).multilineTextAlignment(.center)
        }.padding(32).frame(maxWidth: .infinity)
    }
}

/// The four logos made for the Fire TV app. The iPhone icon and the logo inside the app are the same one, chosen in
/// Settings › App icon. (Graffiti is the iPhone app's main icon; the others are Apple "alternate icons".)
enum AppLogo: String, CaseIterable, Identifiable {
    case graffiti = "Graffiti", sticky = "Sticky TV", drip = "Drip Screen", retro = "Retro Set"
    var id: String { rawValue }
    var image: String { switch self { case .graffiti: "LogoGraffiti"; case .sticky: "LogoSticky"; case .drip: "LogoDrip"; case .retro: "LogoRetro" } }
    /// The name of its icon set (nil = the main icon).
    var iconName: String? { switch self { case .graffiti: nil; case .sticky: "AppIcon-Sticky"; case .drip: "AppIcon-Drip"; case .retro: "AppIcon-Retro" } }
    /// The graffiti logo has the name in it; the others get "STICKY TV" written next to them.
    var hasWordmark: Bool { self == .graffiti }
}

struct BrandLogo: View {
    @AppStorage("appLogo") private var logo = AppLogo.graffiti.rawValue
    var body: some View {
        let l = AppLogo(rawValue: logo) ?? .graffiti
        HStack(spacing: 8) {
            Image(l.image).resizable().scaledToFit().frame(height: l.hasWordmark ? 52 : 30)
            if !l.hasWordmark {
                Text("STICKY TV").font(.system(size: 18, weight: .black, design: .rounded)).tracking(1.5).foregroundStyle(Nova.text)
            }
        }
    }
}

func timeText(_ d: Date, clock24: Bool = false) -> String {
    let f = DateFormatter()
    f.dateFormat = clock24 ? "HH:mm" : "h:mm a"
    return f.string(from: d)
}

func minutesText(_ seconds: Double) -> String {
    let m = Int(seconds / 60)
    return m >= 60 ? "\(m / 60)h \(m % 60)m" : "\(m)m"
}
