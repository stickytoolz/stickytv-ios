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

/// The one live player (preview window and full screen share it), played by VLC with the Fire TV app's rules:
/// MPEG-TS first (one steady connection; HLS if a channel won't open that way); a failed or stuck channel reconnects,
/// waiting longer each time (a 1-screen plan can still be counting the last connection for a few seconds); the picture
/// stays black until the channel's own picture is there; dropouts, speed and lost frames are measured for the signal.
@MainActor
final class LivePlayer: NSObject, ObservableObject, VLCMediaPlayerDelegate, AVPictureInPictureControllerDelegate {
    static let shared = LivePlayer()

    let player = VLCMediaPlayer()
    let av = AVPlayer()                         // the iPhone's own player, when it's the chosen engine
    let canvas = VideoCanvas()
    private var useApple: Bool { forceApple || library?.prefs.playerEngine == "apple-hls" }
    /// Picture-in-picture needs the iPhone's own player: a VLC channel is handed over to it for PiP.
    private var forceApple = false
    private var pip: AVPictureInPictureController?
    @Published private(set) var inPiP = false
    private var pipWanted = false
    private var avLastTime: Double = -1
    @Published private(set) var channel: Channel?
    @Published private(set) var list: [Channel] = []
    @Published private(set) var status: String?
    @Published private(set) var pictureOn = false
    @Published var fullScreen = false
    @Published private(set) var previous: (list: [Channel], channel: Channel)?

    private weak var library: Library?
    private var retries = 0
    private var wasReady = false
    private var useOtherFormat = false          // this channel wouldn't open in the usual format
    private var retryTask: Task<Void, Never>?
    private var ticker: Timer?
    private var lastTime: Int32 = -1
    private var lastShown = -1                  // pictures shown so far (VLC's count): the surest sign it's playing
    private var stuckFor = 0                    // seconds the picture hasn't moved while it should be playing
    private static let waits: [Double] = [2, 3, 5, 8, 10, 12, 15, 15]   // about a minute and a quarter in all

    // stream health (the Channel signal window and the dots)
    let signals = SignalStore()
    @Published private(set) var samples: [SignalSample] = []
    @Published private(set) var level: SignalLevel = .none
    @Published private(set) var stalls = 0                 // dropouts on this channel
    @Published private(set) var lastStall: Date?
    @Published private(set) var pictureSize: CGSize = .zero
    private var cushionStalls = 0                           // dropouts since the app opened (the cushion grows with them)
    private var lastError: String?

    private override init() {
        super.init()
        player.delegate = self
        player.drawable = canvas
        canvas.avLayer.player = av
        if AVPictureInPictureController.isPictureInPictureSupported() {
            pip = AVPictureInPictureController(playerLayer: canvas.avLayer)
            pip?.delegate = self
            // with the Apple engine, leaving the app shrinks the channel into a floating window by itself
            pip?.canStartPictureInPictureAutomaticallyFromInline = true
        }
    }

    func attach(_ library: Library) { self.library = library }

    /// Plays [c] (from [list], for swiping to the next and previous channel).
    func play(_ c: Channel, in list: [Channel]) {
        if let cur = channel, cur.id != c.id { previous = (self.list, cur); signals.remember(cur.id, level) }
        if channel?.id != c.id && !inPiP { forceApple = false }
        if channel?.id != c.id {
            samples = []; stalls = 0; lastStall = nil; level = signals.level(c.id) ?? .none
            pictureOn = false; useOtherFormat = false
        }
        self.list = list.isEmpty ? [c] : list
        channel = c
        retries = 0; lastError = nil
        library?.prefs.watched(c.id)
        library?.prefs.lastChannel = c.id
        start()
    }

    /// The PiP button: the channel in a floating window that stays when you leave the app (a VLC channel moves to the
    /// iPhone's player first — VLC can't do PiP — and starts as soon as it plays).
    func startPiP() {
        guard pip != nil, channel != nil else { status = "Picture-in-picture isn't available on this iPhone"; return }
        pipWanted = true
        if !useApple { forceApple = true; retries = 0; start() } else { tryStartPiP() }
    }

    private func tryStartPiP() {
        guard pipWanted, let pip, av.timeControlStatus == .playing, pip.isPictureInPicturePossible else { return }
        pipWanted = false
        pip.startPictureInPicture()
    }

    nonisolated func pictureInPictureControllerDidStartPictureInPicture(_ c: AVPictureInPictureController) {
        Task { @MainActor in self.inPiP = true; self.fullScreen = false }
    }
    nonisolated func pictureInPictureControllerDidStopPictureInPicture(_ c: AVPictureInPictureController) {
        Task { @MainActor in
            self.inPiP = false
            // back from PiP: the chosen engine again (VLC)
            if self.forceApple && self.library?.prefs.playerEngine != "apple-hls" && UIApplication.shared.applicationState == .active {
                self.forceApple = false; self.retries = 0; self.start()
            }
        }
    }
    nonisolated func pictureInPictureController(_ c: AVPictureInPictureController,
                                                restoreUserInterfaceForPictureInPictureStopWithCompletionHandler done: @escaping (Bool) -> Void) {
        Task { @MainActor in self.fullScreen = true; done(true) }
    }

    func stop() {
        retryTask?.cancel(); ticker?.invalidate()
        if let c = channel { signals.remember(c.id, level) }
        player.stop(); av.replaceCurrentItem(with: nil)
        channel = nil; status = nil; pictureOn = false; fullScreen = false
    }

    /// ▲▼ on the Fire TV remote: the next or previous channel in the list you're in.
    func step(_ by: Int) {
        guard let c = channel, !list.isEmpty, let i = list.firstIndex(where: { $0.id == c.id }) else { return }
        play(list[(i + by + list.count) % list.count], in: list)
    }

    func flipBack() { if let p = previous { play(p.channel, in: p.list) } }

    /// The stream format for this channel: the setting (MPEG-TS unless changed), or the other one if it wouldn't open.
    private var format: String {
        let chosen = library?.prefs.liveFormat ?? "ts"
        return useOtherFormat ? (chosen == "ts" ? "m3u8" : "ts") : chosen
    }

    /// Settings › Player: Buffer (Low 1 s, Normal 3 s, High 10 s), and the weak-signal cushion on top (8, 15, 25 s).
    private func cacheMs() -> Int {
        let prefs = library?.prefs
        let base = switch prefs?.bufferMode ?? 1 { case 0: 1500; case 2: 12000; default: 5000 }
        let cushion = (prefs?.cushion ?? false) ? Int(Cushion.seconds(afterStalls: cushionStalls) * 1000) : 0
        return max(base, cushion)
    }

    private func start() {
        guard let c = channel, let url = library?.liveURL(c, format: useApple ? "m3u8" : format) else { return }
        retryTask?.cancel()
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
        if !(status?.hasPrefix("Reconnecting") ?? false) { status = "Loading" }
        wasReady = false; lastTime = -1; lastShown = -1; stuckFor = 0; avLastTime = -1
        if useApple {
            // the iPhone's own player (HLS)
            player.stop(); player.drawable = nil
            canvas.subviews.forEach { $0.removeFromSuperview() }        // VLC's picture out of the way
            let item = AVPlayerItem(asset: AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": ["User-Agent": XtreamAPI.defaultAgent]]))
            item.preferredForwardBufferDuration = Double(cacheMs()) / 1000
            av.replaceCurrentItem(with: item)
            av.play()
            startTicker()
            return
        }
        av.replaceCurrentItem(with: nil)
        let media = VLCMedia(url: url)
        let cache = cacheMs()
        media.addOptions(["network-caching": cache, "live-caching": cache, "http-user-agent": XtreamAPI.defaultAgent,
                          "http-reconnect": true])
        player.drawable = canvas
        player.media = media
        player.play()
        startTicker()
    }

    // MARK: what VLC tells us

    nonisolated func mediaPlayerStateChanged(_ aNotification: Notification) {
        Task { @MainActor in self.stateChanged() }
    }

    private func stateChanged() {
        guard !useApple else { return }                 // VLC isn't the one playing
        switch player.state {
        case .playing:
            if player.videoSize.width > 0 { pictureOn = true }
        case .error:
            lastError = "VLC couldn't open the stream (\(format.uppercased()))"
            failed()
        case .ended, .stopped:
            // a live channel never ends by itself: the connection dropped
            if channel != nil && retryTask == nil && wasReady { lastError = "The stream ended"; failed() }
        default: break
        }
    }

    /// Once a second: is the picture moving? (and the signal readings)
    private func startTicker() {
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func tick() {
        guard let c = channel else { return }
        let moving: Bool
        var size = CGSize.zero
        if useApple {
            if av.currentItem?.status == .failed {
                lastError = (av.currentItem?.error as NSError?).map { "Apple player: \($0.domain) \($0.code) \($0.localizedDescription)" }
                failed(); return
            }
            let t = av.currentTime().seconds
            moving = av.timeControlStatus == .playing && t.isFinite && t != avLastTime
            avLastTime = t
            size = av.currentItem?.presentationSize ?? .zero
        } else {
            let t = player.time.intValue
            // VLC's clock doesn't tick steadily on live streams: new pictures on screen (or sound playing on) count too
            let shown = Int(player.media?.numberOfDisplayedPictures ?? 0)
            moving = player.isPlaying && ((t != lastTime && t > 0) || (shown > lastShown && lastShown >= 0) || player.state == .playing)
            lastShown = shown
            lastTime = t
            size = player.videoSize
        }
        if moving && useApple { tryStartPiP() }
        if moving {
            if !wasReady { wasReady = true; retries = 0 }
            if size.width > 0 { pictureOn = true; pictureSize = size }
            stuckFor = 0
            if status != nil { status = nil }
        } else if wasReady {
            stuckFor += 1
            if stuckFor == 3 {
                // it was playing and stopped to wait: a dropout
                stalls += 1; cushionStalls += 1; lastStall = Date()
                signals.note(c.name, "Dropped out")
                status = library?.prefs.cushion == true
                    ? "Weak connection: saving \(Int(Cushion.seconds(afterStalls: cushionStalls))) s ahead so it keeps playing" : "Loading"
            }
            if stuckFor >= 20 { stuckFor = 0; signals.note(c.name, "Stuck for 20 s: reconnected"); reconnect(after: 0) }
        } else {
            stuckFor += 1
            if stuckFor >= 25 { lastError = "Nothing arrived in 25 s (\(format.uppercased()))"; stuckFor = 0; failed() }   // never started
        }
        // the signal: how fast it arrives against the stream's own speed, and lost pictures
        var st = VLCStats(player.media)
        if useApple, let ev = av.currentItem?.accessLog()?.events.last {
            st.inputBps = max(ev.observedBitrate, 0); st.streamBps = max(ev.indicatedBitrate, 0); st.lostPictures = max(ev.numberOfDroppedVideoFrames, 0)
        }
        if st.inputBps > 0 || st.streamBps > 0 {
            samples = Array((samples + [SignalSample(at: Date(), observedBps: st.inputBps, indicatedBps: st.streamBps,
                                                     droppedFrames: st.lostPictures, stalls: stalls)]).suffix(60))
            level = SignalMeter.level(samples, lastStall: lastStall)
            if samples.count % 10 == 0 { signals.remember(c.id, level) }
        }
    }

    private func reconnect(after seconds: Double) {
        retryTask?.cancel()
        retryTask = Task { [weak self] in
            if seconds > 0 { try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)) }
            guard let self, !Task.isCancelled else { return }
            self.retryTask = nil
            self.status = "Reconnecting…"
            self.start()
        }
    }

    /// Couldn't open, or lost: try again, waiting a little longer each time; a channel that never opened tries the other
    /// stream format once. After about a minute and a quarter, say so.
    private func failed() {
        guard let c = channel else { return }
        if !wasReady && retries == 1 && !useOtherFormat {
            useOtherFormat = true
            signals.note(c.name, "Wouldn't open as \((library?.prefs.liveFormat ?? "ts").uppercased()): trying the other format")
        }
        if useApple { useOtherFormat = false }          // the iPhone's player only plays HLS
        if retries < Self.waits.count {
            let wait = Self.waits[retries]; retries += 1
            status = "Reconnecting…"
            reconnect(after: wait); return
        }
        ticker?.invalidate()
        pictureOn = false                               // black behind the message, never a leftover picture
        signals.note(c.name, "Couldn't play" + (lastError.map { " — \($0)" } ?? ""))
        let screens = library?.info?.maxConnections ?? 1
        status = "Can't play this channel right now. If something else is playing on your plan (\(screens) screen\(screens == 1 ? "" : "s") at once), stop it and tap the channel to try again."
    }

    /// Full screen: fill the screen (cropping the edges) or show the whole picture.
    func setFill(_ fill: Bool, size: CGSize) {
        canvas.avLayer.videoGravity = fill ? .resizeAspectFill : .resizeAspect
        if fill && size.width > 0 && size.height > 0 {
            let w = Int(size.width.rounded()), h = Int(size.height.rounded())
            let geometry = strdup("\(w):\(h)")          // VLC keeps the pointer
            player.videoCropGeometry = geometry
        } else {
            player.videoCropGeometry = nil
        }
    }
}

/// The live picture: VLC's canvas, moved into whichever window shows it (preview or full screen).
struct VideoSurface: UIViewRepresentable {
    let isFull: Bool
    let fullOpen: Bool
    func makeUIView(context: Context) -> UIView {
        let host = UIView(); host.backgroundColor = .black; host.clipsToBounds = true
        host.isUserInteractionEnabled = false           // taps go to the app (tap the preview: full screen)
        if isFull == fullOpen { Task { @MainActor in VideoSurface.adopt(host) } }
        return host
    }
    func updateUIView(_ host: UIView, context: Context) { if isFull == fullOpen { VideoSurface.adopt(host) } }
    @MainActor static func adopt(_ host: UIView) {
        let canvas = LivePlayer.shared.canvas
        guard canvas.superview !== host else { return }
        canvas.removeFromSuperview()
        canvas.frame = host.bounds
        canvas.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        host.addSubview(canvas)
    }
}

struct LiveVideo: View {
    @ObservedObject var live = LivePlayer.shared
    var fill = false
    var isFull = false
    var body: some View {
        GeometryReader { g in
            ZStack {
                Color.black
                // the picture is in full screen while it's open, otherwise in the preview window
                VideoSurface(isFull: isFull, fullOpen: live.fullScreen)
                if !live.pictureOn { Color.black }
                if let s = live.status {
                    if s == "Loading" || s.hasPrefix("Reconnecting") {
                        VStack(spacing: 10) {
                            ProgressView().tint(Nova.accent)
                            Text(s).font(.caption.bold()).foregroundStyle(.white)
                        }.padding(14).background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 12))
                    } else {
                        Text(s).font(.footnote.bold()).foregroundStyle(.white).multilineTextAlignment(.center)
                            .padding(14).background(Nova.panel.opacity(0.92), in: RoundedRectangle(cornerRadius: 12)).padding(20)
                    }
                }
            }
            .onAppear { live.setFill(fill, size: g.size) }
            .onChange(of: fill) { f in live.setFill(f, size: g.size) }
        }
    }
}
