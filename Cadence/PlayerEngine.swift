import UIKit
import AVFoundation
import MediaPlayer
import SwiftUI

@MainActor @Observable
final class PlayerEngine {
    private(set) var queue: [Track] = []
    private(set) var index = 0
    private(set) var isPlaying = false
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    var shuffle = false
    var repeatMode: RepeatMode = .off

    /// Нужен, чтобы брать обложки; выставляется из RootView
    @ObservationIgnored var library: Library?

    var current: Track? { queue.indices.contains(index) ? queue[index] : nil }

    var cover: UIImage? {
        guard let t = current else { return nil }
        return library?.covers[t.albumID]
    }

    var progress: Double {
        duration > 0 ? min(max(currentTime / duration, 0), 1) : 0
    }

    private let player = AVPlayer()
    @ObservationIgnored private var timeObserver: Any?

    init() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)

        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self else { return }
                let s = time.seconds
                self.currentTime = s.isFinite ? s : 0
            }
        }

        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.trackEnded() }
        }

        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            MainActor.assumeIsolated {
                if let raw, AVAudioSession.InterruptionType(rawValue: raw) == .began {
                    self?.isPlaying = false
                    self?.updateNowPlayingInfo()
                }
            }
        }

        setupRemoteCommands()
    }

    // MARK: - Управление

    func play(_ tracks: [Track], startAt start: Int = 0, shuffled: Bool? = nil) {
        guard !tracks.isEmpty else { return }
        queue = tracks
        if let shuffled { shuffle = shuffled }
        var first = min(max(start, 0), tracks.count - 1)
        if shuffled == true { first = Int.random(in: 0..<tracks.count) }
        load(first)
    }

    func toggle() {
        guard current != nil else { return }
        isPlaying ? pause() : resume()
    }

    func resume() {
        guard current != nil else { return }
        try? AVAudioSession.sharedInstance().setActive(true)
        player.play()
        isPlaying = true
        updateNowPlayingInfo()
    }

    func pause() {
        player.pause()
        isPlaying = false
        updateNowPlayingInfo()
    }

    func next() {
        guard !queue.isEmpty else { return }
        if shuffle && queue.count > 1 {
            var n = Int.random(in: 0..<queue.count)
            while n == index { n = Int.random(in: 0..<queue.count) }
            load(n)
        } else if index + 1 < queue.count {
            load(index + 1)
        } else if repeatMode == .all {
            load(0)
        } else {
            pause()
            seek(to: 0)
        }
    }

    func previous() {
        guard !queue.isEmpty else { return }
        if currentTime > 3 || index == 0 {
            seek(to: 0)
        } else {
            load(index - 1)
        }
    }

    func seek(to seconds: TimeInterval) {
        let t = max(0, seconds)
        player.seek(to: CMTime(seconds: t, preferredTimescale: 600))
        currentTime = t
        updateNowPlayingInfo()
    }

    func cycleRepeat() { repeatMode = repeatMode.next }

    // MARK: - Внутреннее

    private func load(_ i: Int) {
        guard queue.indices.contains(i) else { return }
        index = i
        let item = AVPlayerItem(url: queue[i].url)
        player.replaceCurrentItem(with: item)
        duration = queue[i].duration
        currentTime = 0
        try? AVAudioSession.sharedInstance().setActive(true)
        player.play()
        isPlaying = true
        updateNowPlayingInfo()
    }

    private func trackEnded() {
        if repeatMode == .one {
            player.seek(to: .zero)
            player.play()
            return
        }
        next()
    }

    // MARK: - Экран блокировки

    private func setupRemoteCommands() {
        let c = MPRemoteCommandCenter.shared()

        c.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.resume() }
            return .success
        }
        c.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.pause() }
            return .success
        }
        c.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.toggle() }
            return .success
        }
        c.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.next() }
            return .success
        }
        c.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.previous() }
            return .success
        }
        c.changePlaybackPositionCommand.addTarget { [weak self] event in
            let position = (event as? MPChangePlaybackPositionCommandEvent)?.positionTime ?? 0
            Task { @MainActor in self?.seek(to: position) }
            return .success
        }
    }

    private func updateNowPlayingInfo() {
        guard let t = current else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: t.title,
            MPMediaItemPropertyArtist: t.artist,
            MPMediaItemPropertyAlbumTitle: t.album,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]
        if let img = cover {
            info[MPMediaItemPropertyArtwork] = Self.makeArtwork(img)
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    /// nonisolated, чтобы замыкание не считалось main-actor (иначе краш на фоновой очереди)
    private nonisolated static func makeArtwork(_ img: UIImage) -> MPMediaItemArtwork {
        MPMediaItemArtwork(boundsSize: img.size) { _ in img }
    }
}
