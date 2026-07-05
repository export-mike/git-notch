import AVFoundation
import AppKit

/// Plays bundled alert sounds. Holds a strong reference to the player so it
/// isn't deallocated mid-playback.
@MainActor
final class SoundPlayer {
    private var player: AVAudioPlayer?

    func play(resource name: String, ext: String) {
        guard let url = Bundle.main.url(forResource: name, withExtension: ext) else {
            NSLog("[gitnotch] sound resource missing: %@.%@", name, ext)
            return
        }
        do {
            let p = try AVAudioPlayer(contentsOf: url)
            p.prepareToPlay()
            p.play()
            player = p
        } catch {
            NSLog("[gitnotch] sound play error: %@", error.localizedDescription)
        }
    }
}
