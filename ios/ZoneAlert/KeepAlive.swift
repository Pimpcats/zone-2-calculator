import Foundation
import AVFoundation

/// Keeps the app running in the background (so heart-rate readings keep arriving and
/// zone alerts keep firing while the screen is locked) by holding an active audio
/// session playing inaudible, mixable silence. Restarts itself after interruptions
/// (e.g. voice cues, phone calls, route changes). Started while a strap is connected.
final class KeepAlive: NSObject, AVAudioPlayerDelegate {
    private var player: AVAudioPlayer?
    private var running = false

    override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleInterruption(_:)),
            name: AVAudioSession.interruptionNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleRouteChange(_:)),
            name: AVAudioSession.routeChangeNotification, object: nil)
    }

    func start() {
        running = true
        activate()
    }

    func stop() {
        running = false
        player?.stop()
        player = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    private func activate() {
        guard running else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
            if player == nil {
                let p = try AVAudioPlayer(data: KeepAlive.silentWav)
                p.numberOfLoops = -1
                p.volume = 0.01            // effectively silent, but non-zero keeps it "playing"
                p.delegate = self
                player = p
            }
            player?.prepareToPlay()
            player?.play()
        } catch {
            // Fall back to BLE-only background wakes if audio can't start.
        }
    }

    @objc private func handleInterruption(_ n: Notification) {
        guard running,
              let info = n.userInfo,
              let raw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        if type == .ended { activate() }     // resume after the interruption clears
    }

    @objc private func handleRouteChange(_ n: Notification) {
        if running { activate() }
    }

    // Restart if playback ever stops for any reason.
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        if running { activate() }
    }

    /// A 1-second mono 16-bit PCM WAV of pure silence, generated in code.
    static let silentWav: Data = {
        let sampleRate = 8000, seconds = 1, bytesPerSample = 2
        let numSamples = sampleRate * seconds
        let dataSize = numSamples * bytesPerSample
        var d = Data()
        func le32(_ v: UInt32) { var x = v.littleEndian; withUnsafeBytes(of: &x) { d.append(contentsOf: $0) } }
        func le16(_ v: UInt16) { var x = v.littleEndian; withUnsafeBytes(of: &x) { d.append(contentsOf: $0) } }
        d.append(contentsOf: Array("RIFF".utf8))
        le32(UInt32(36 + dataSize))
        d.append(contentsOf: Array("WAVE".utf8))
        d.append(contentsOf: Array("fmt ".utf8))
        le32(16); le16(1); le16(1)
        le32(UInt32(sampleRate))
        le32(UInt32(sampleRate * bytesPerSample))
        le16(UInt16(bytesPerSample)); le16(16)
        d.append(contentsOf: Array("data".utf8))
        le32(UInt32(dataSize))
        d.append(Data(count: dataSize))   // silence
        return d
    }()
}
