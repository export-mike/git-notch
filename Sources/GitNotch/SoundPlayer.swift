import AVFoundation
import AppKit

/// Plays bundled alert sounds. Holds a strong reference to the player so it
/// isn't deallocated mid-playback, and reports start/stop so the UI can offer a
/// "silence" control only while a sound is actually playing.
@MainActor
final class SoundPlayer: NSObject, AVAudioPlayerDelegate {
    private var player: AVAudioPlayer?

    /// Fired on the main actor when playback starts (`true`) or ends (`false`),
    /// whether it finished on its own or was stopped.
    var onPlayingChange: ((Bool) -> Void)?

    func play(resource name: String, ext: String) {
        guard let url = Bundle.main.url(forResource: name, withExtension: ext) else {
            NSLog("[gitnotch] sound resource missing: %@.%@", name, ext)
            return
        }
        do {
            let p = try AVAudioPlayer(contentsOf: url)
            p.delegate = self
            p.prepareToPlay()
            p.play()
            player = p
            onPlayingChange?(true)
        } catch {
            NSLog("[gitnotch] sound play error: %@", error.localizedDescription)
        }
    }

    /// Stop any in-progress playback immediately.
    func stop() {
        guard player?.isPlaying == true else { return }
        player?.stop()
        player = nil
        onPlayingChange?(false)
    }

    // AVFoundation calls this off the main actor; hop back before touching state.
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.player = nil
            self.onPlayingChange?(false)
        }
    }
}
