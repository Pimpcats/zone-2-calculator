import Foundation
import AVFoundation

/// Keeps the app running in the background (so heart-rate readings keep arriving and
/// zone alerts keep firing while the screen is locked) by holding an active audio
/// session playing inaudible, mixable silence. Started while a strap is connected.
final class KeepAlive {
    private var player: AVAudioPlayer?

    func start() {
        guard player == nil else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
            let p = try AVAudioPlayer(data: KeepAlive.silentWav)
            p.numberOfLoops = -1
            p.volume = 0
            p.prepareToPlay()
            p.play()
            player = p
        } catch {
            // If audio can't start we silently fall back to BLE-only background wakes.
        }
    }

    func stop() {
        player?.stop()
        player = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
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
