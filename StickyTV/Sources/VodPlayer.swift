import SwiftUI
import AVFoundation
import AVKit
import StickyKit
#if canImport(MobileVLCKit)
import MobileVLCKit
#elseif canImport(VLCKit)
import VLCKit
#endif
import VLCKitSPM

/// Movies and episodes: MP4 in the iPhone's own player (scrubbing, AirPlay, picture-in-picture); anything else
/// (MKV, AVI, TS…) in VLC, which plays them like the Fire TV does.
struct VodPlayer: View {
    let url: URL
    let key: String
    let title: String
    let prefs: Prefs
    var fromStart = false
    var body: some View {
        if ["mp4", "m4v", "mov"].contains(url.pathExtension.lowercased()) {
            AVVodPlayer(url: url, key: key, title: title, prefs: prefs, fromStart: fromStart)
        } else {
            VLCVodPlayer(url: url, key: key, title: title, prefs: prefs, fromStart: fromStart)
        }
    }
}

/// VLC for movies: tap for the controls (close, play/pause, 10 seconds back/forward, the bar to jump anywhere).
struct VLCVodPlayer: View {
    let url: URL
    let key: String
    let title: String
    let prefs: Prefs
    var fromStart = false
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = VLCVodModel()
    @State private var controls = true
    @State private var scrubbing: Double?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VLCCanvasView(canvas: model.canvas).ignoresSafeArea()
            if model.loading { ProgressView().tint(Nova.accent) }
            if controls {
                VStack {
                    HStack(spacing: 14) {
                        Button { model.save(prefs, key); model.stop(); dismiss() } label: {
                            Image(systemName: "xmark").font(.headline).padding(12).background(.black.opacity(0.5), in: Circle())
                        }
                        Text(title).font(.headline).lineLimit(1)
                        Spacer()
                    }.padding(.horizontal, 24).padding(.top, 12)
                    Spacer()
                    HStack(spacing: 40) {
                        Button { model.jump(-10) } label: { Image(systemName: "gobackward.10").font(.system(size: 30)) }
                        Button { model.togglePause() } label: { Image(systemName: model.playing ? "pause.fill" : "play.fill").font(.system(size: 40)) }
                        Button { model.jump(10) } label: { Image(systemName: "goforward.10").font(.system(size: 30)) }
                    }
                    Spacer()
                    HStack(spacing: 12) {
                        Text(clock(scrubbing ?? model.position)).font(.caption.monospacedDigit())
                        Slider(value: Binding(get: { scrubbing ?? model.position }, set: { scrubbing = $0 }), in: 0...max(model.length, 1)) { editing in
                            if !editing, let s = scrubbing { model.seek(to: s); scrubbing = nil }
                        }.tint(Nova.accent)
                        Text(clock(model.length)).font(.caption.monospacedDigit())
                    }.padding(.horizontal, 24).padding(.bottom, 16)
                }
                .foregroundStyle(.white)
                .background(LinearGradient(colors: [.black.opacity(0.6), .clear, .black.opacity(0.6)], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
            }
        }
        .statusBarHidden()
        .contentShape(Rectangle())
        .onTapGesture { withAnimation { controls.toggle() } }
        .onAppear {
            LivePlayer.shared.player.pause()
            model.open(url, from: fromStart ? 0 : prefs.position(key))
        }
        .onDisappear { model.save(prefs, key); model.stop() }
    }

    private func clock(_ s: Double) -> String {
        let t = Int(s); return t >= 3600 ? String(format: "%d:%02d:%02d", t / 3600, t / 60 % 60, t % 60) : String(format: "%d:%02d", t / 60, t % 60)
    }
}

@MainActor
final class VLCVodModel: ObservableObject {
    let player = VLCMediaPlayer()
    let canvas = VideoCanvas()
    @Published var position: Double = 0          // seconds
    @Published var length: Double = 0
    @Published var playing = false
    @Published var loading = true
    private var timer: Timer?
    private var startAt: Double = 0
    private var started = false

    func open(_ url: URL, from: Double) {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
        startAt = from
        let m = VLCMedia(url: url)
        m.addOptions(["network-caching": 3000, "http-user-agent": XtreamAPI.defaultAgent])
        player.drawable = canvas
        player.media = m
        player.play()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in Task { @MainActor in self?.tick() } }
    }

    private func tick() {
        playing = player.isPlaying
        let len = Double(player.media?.length.intValue ?? 0) / 1000
        if len > 0 { length = len }
        position = Double(player.time.intValue) / 1000
        loading = !player.isPlaying && player.state != .paused
        // resume where you left off, once it has started
        if !started && player.isPlaying {
            started = true
            if startAt > 5 { player.time = VLCTime(int: Int32(startAt * 1000)) }
        }
    }

    func togglePause() { if player.isPlaying { player.pause() } else { player.play() } }
    func jump(_ s: Int32) { if s > 0 { player.jumpForward(s) } else { player.jumpBackward(-s) } }
    func seek(to s: Double) { player.time = VLCTime(int: Int32(s * 1000)) }
    func save(_ prefs: Prefs, _ key: String) { if position > 5 { prefs.savePosition(key, position, length) } }
    func stop() { timer?.invalidate(); player.stop() }
}

/// Shows a VLC canvas in SwiftUI.
struct VLCCanvasView: UIViewRepresentable {
    let canvas: VideoCanvas
    func makeUIView(context: Context) -> VideoCanvas { canvas }
    func updateUIView(_ v: VideoCanvas, context: Context) {}
}

/// MP4 movies and episodes: the iPhone's own player (scrubbing, AirPlay, picture-in-picture), resuming where you left off.
struct AVVodPlayer: UIViewControllerRepresentable {
    let url: URL
    let key: String
    let title: String
    let prefs: Prefs
    var fromStart = false

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
        LivePlayer.shared.player.pause()
        let item = AVPlayerItem(asset: AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": ["User-Agent": XtreamAPI.defaultAgent]]))
        let meta = AVMutableMetadataItem()
        meta.identifier = .commonIdentifierTitle; meta.value = title as NSString
        item.externalMetadata = [meta]
        let p = AVPlayer(playerItem: item)
        let start = fromStart ? 0 : prefs.position(key)
        if start > 5 { p.seek(to: CMTime(seconds: start, preferredTimescale: 1)) }
        let vc = AVPlayerViewController()
        vc.player = p
        vc.allowsPictureInPicturePlayback = true
        context.coordinator.track(p, key: key, prefs: prefs)
        p.play()
        return vc
    }
    func updateUIViewController(_ vc: AVPlayerViewController, context: Context) {}
    static func dismantleUIViewController(_ vc: AVPlayerViewController, coordinator: Coordinator) {
        coordinator.save(); vc.player?.pause(); vc.player = nil
    }
    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        private var timeObs: Any?
        private weak var player: AVPlayer?
        private var key = ""
        private var prefs: Prefs?
        func track(_ p: AVPlayer, key: String, prefs: Prefs) {
            player = p; self.key = key; self.prefs = prefs
            timeObs = p.addPeriodicTimeObserver(forInterval: CMTime(seconds: 10, preferredTimescale: 1), queue: .main) { [weak self] _ in self?.save() }
        }
        func save() {
            guard let p = player, let item = p.currentItem else { return }
            let pos = p.currentTime().seconds, dur = item.duration.seconds
            if pos.isFinite, pos > 5 { prefs?.savePosition(key, pos, dur.isFinite ? dur : 0) }
        }
        deinit { if let t = timeObs { player?.removeTimeObserver(t) } }
    }
}

