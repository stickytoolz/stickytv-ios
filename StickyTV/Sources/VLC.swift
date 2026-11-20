// VLC, the player engine (as most iPhone IPTV apps use): it plays what providers send — MPEG-TS and HLS live
// channels, and MKV / AVI / MP4 movies — the way the Fire TV's player does.
#if canImport(MobileVLCKit)
@_exported import MobileVLCKit
#elseif canImport(VLCKit)
@_exported import VLCKit
#endif
import VLCKitSPM
import UIKit
import AVFoundation

/// The view VLC draws into. One per player; it moves between the preview window and full screen.
final class VideoCanvas: UIView {
    /// The iPhone's own player draws here (Settings › Player › Player engine › Apple); VLC adds its own view on top.
    let avLayer = AVPlayerLayer()
    override init(frame: CGRect) {
        super.init(frame: frame); backgroundColor = .black; clipsToBounds = true
        avLayer.videoGravity = .resizeAspect
        layer.addSublayer(avLayer)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layoutSubviews() { super.layoutSubviews(); avLayer.frame = bounds }
}

/// VLC's measurements, read from the media: speeds in bits per second (VLC counts bytes per microsecond).
struct VLCStats {
    var inputBps: Double
    var streamBps: Double
    var lostPictures: Int
    var shownPictures: Int
    init(_ m: VLCMedia?) {
        inputBps = Double(m?.inputBitrate ?? 0) * 8_000_000
        streamBps = Double(m?.demuxBitrate ?? 0) * 8_000_000
        lostPictures = Int(m?.numberOfLostPictures ?? 0)
        shownPictures = Int(m?.numberOfDisplayedPictures ?? 0)
    }
}
