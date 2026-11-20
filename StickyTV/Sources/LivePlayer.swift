import SwiftUI
import AVFoundation
import AVKit
import StickyKit

/// The one live player (preview window and full screen share it), with the Fire TV app's rules:
/// HLS for every channel; a provider saying "too many screens" (401/403/429/456/458/509+) is waited out for about a
/// minute (a reconnect can overlap its previous session); network blips are retried; the picture stays black until
/// the channel's own picture is there.
@MainActor
final class LivePlayer: ObservableObject {
    static let shared = LivePlayer()

    let player = AVPlayer()
    @Published private(set) var channel: Channel?
    @Published private(set) var list: [Channel] = []
    @Published private(set) var status: String?
    @Published private(set) var pictureOn = false
    @Published var fullScreen = false
    @Published private(set) var previous: (list: [Channel], channel: Channel)?

    private weak var library: Library?
    private var playerObs: NSKeyValueObservation?
    private var observers: [NSKeyValueObservation] = []
    private var notes: [NSObjectProtocol] = []
    private var retries = 0
    private var busyTries = 0
    private var wasReady = false
    private var lastHTTPStatus: Int?
    private var retryTask: Task<Void, Never>?
    private var waitingSince: Date?
    private var watchdog: Timer?
    private static let busyWaits: [Double] = [3, 5, 8, 10, 12, 15]          // about a minute in all

    private init() {
        player.automaticallyWaitsToMinimizeStalling = true
        playerObs = player.observe(\.timeControlStatus, options: [.new]) { [weak self] p, _ in
            let s = p.timeControlStatus
            Task { @MainActor in self?.timeControlChanged(s) }
        }
    }

    func attach(_ library: Library) { self.library = library }

    /// Plays [c] (from [list], for swiping to the next and previous channel).
    func play(_ c: Channel, in list: [Channel]) {
        if let cur = channel, cur.id != c.id { previous = (self.list, cur) }
        self.list = list.isEmpty ? [c] : list
        if channel?.id != c.id { pictureOn = false }
        channel = c
        retries = 0; busyTries = 0
        library?.prefs.watched(c.id)
        library?.prefs.lastChannel = c.id
        start()
    }

    func stop() {
        retryTask?.cancel(); watchdog?.invalidate()
        player.replaceCurrentItem(with: nil)
        channel = nil; status = nil; pictureOn = false; fullScreen = false
    }

    /// ▲▼ on the Fire TV remote: the next or previous channel in the list you're in.
    func step(_ by: Int) {
        guard let c = channel, !list.isEmpty, let i = list.firstIndex(where: { $0.id == c.id }) else { return }
        let n = (i + by + list.count) % list.count
        play(list[n], in: list)
    }

    func flipBack() { if let p = previous { play(p.channel, in: p.list) } }

    private func start() {
        guard let c = channel, let url = library?.liveURL(c) else { return }
        retryTask?.cancel()
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
        status = "Loading"
        wasReady = false
        lastHTTPStatus = nil
        let item = AVPlayerItem(asset: AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": ["User-Agent": XtreamAPI.defaultAgent]]))
        item.preferredForwardBufferDuration = 0          // the player decides (like the plain Fire TV player)
        watch(item)
        player.replaceCurrentItem(with: item)
        player.play()
        startWatchdog()
    }

    private func watch(_ item: AVPlayerItem) {
        observers = []
        notes.forEach(NotificationCenter.default.removeObserver)
        notes = []
        observers.append(item.observe(\.status, options: [.new]) { [weak self] it, _ in
            Task { @MainActor in
                guard let self else { return }
                if it.status == .failed { self.failed(it.error) }
            }
        })
        observers.append(item.observe(\.presentationSize, options: [.new]) { [weak self] it, _ in
            Task { @MainActor in if it.presentationSize.width > 0 { self?.pictureOn = true } }
        })
        let nc = NotificationCenter.default
        notes.append(nc.addObserver(forName: .AVPlayerItemNewErrorLogEntry, object: item, queue: .main) { [weak self] n in
            let code = (n.object as? AVPlayerItem)?.errorLog()?.events.last?.errorStatusCode
            Task { @MainActor in if let code, code >= 400 { self?.lastHTTPStatus = code } }
        })
        notes.append(nc.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main) { [weak self] n in
            let err = n.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
            Task { @MainActor in self?.failed(err) }
        })
        // a live stream "ending" is the connection dropping: reconnect
        notes.append(nc.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.reconnect(after: 1) }
        })
    }

    private func timeControlChanged(_ s: AVPlayer.TimeControlStatus) {
        switch s {
        case .playing:
            status = nil; retries = 0; busyTries = 0; wasReady = true; waitingSince = nil
        case .waitingToPlayAtSpecifiedRate:
            if waitingSince == nil { waitingSince = Date() }
            if status == nil { status = "Loading" }
        default: break
        }
    }

    /// Nothing arriving for a long time while waiting (55 s): reconnect.
    private func startWatchdog() {
        watchdog?.invalidate()
        watchdog = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.channel != nil else { return }
                if let w = self.waitingSince, Date().timeIntervalSince(w) > 55 { self.waitingSince = nil; self.reconnect(after: 0) }
            }
        }
    }

    private func reconnect(after seconds: Double) {
        retryTask?.cancel()
        retryTask = Task { [weak self] in
            if seconds > 0 { try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)) }
            guard !Task.isCancelled else { return }
            self?.status = "Reconnecting…"
            self?.start()
        }
    }

    private func failed(_ error: Error?) {
        let code = lastHTTPStatus
        let busy = code.map { [401, 403, 429, 456, 458].contains($0) || $0 >= 509 } ?? false
        if busy && busyTries < Self.busyWaits.count {
            status = "Reconnecting…"
            let wait = Self.busyWaits[busyTries]; busyTries += 1
            reconnect(after: wait); return
        }
        if !busy && retries < 5 && (wasReady || code == nil || code! >= 500) {
            retries += 1
            status = "Reconnecting (\(retries))"
            reconnect(after: 1.5 * Double(retries)); return
        }
        pictureOn = false                               // black behind the message, never a leftover picture
        let screens = library?.info?.maxConnections ?? 1
        if let code, busy {
            status = "The provider refused this stream (\(code)). Your plan allows \(screens) screen\(screens == 1 ? "" : "s") at once: if nothing else is playing, tap the channel to try again."
        } else if code == 404 || code == 410 {
            status = "This channel isn't available from your provider right now."
        } else if let code {
            status = "The provider answered with an error (\(code)). Try again in a moment."
        } else {
            status = "Can't play this channel right now. Check the internet connection and try again."
        }
    }
}

/// The live picture (black until the channel's own picture arrives).
struct VideoSurface: UIViewRepresentable {
    let player: AVPlayer
    var fill = false
    func makeUIView(context: Context) -> PlayerUIView { let v = PlayerUIView(); v.playerLayer.player = player; v.backgroundColor = .black; return v }
    func updateUIView(_ v: PlayerUIView, context: Context) {
        v.playerLayer.player = player
        v.playerLayer.videoGravity = fill ? .resizeAspectFill : .resizeAspect
    }
    final class PlayerUIView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}

struct LiveVideo: View {
    @ObservedObject var live = LivePlayer.shared
    var fill = false
    var body: some View {
        ZStack {
            Color.black
            VideoSurface(player: live.player, fill: fill)
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
    }
}

/// Movies and episodes: the iPhone's own player (scrubbing, AirPlay, picture-in-picture), resuming where you left off.
struct VodPlayer: UIViewControllerRepresentable {
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
