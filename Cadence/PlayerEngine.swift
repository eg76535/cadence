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

    /// Название активной «волны» (nil = обычная очередь)
    private(set) var waveTitle: String?
    /// Когда сработает таймер сна (nil = выключен)
    private(set) var sleepDeadline: Date?

    /// Нужен, чтобы брать обложки; выставляется из RootView
    @ObservationIgnored var library: Library?
    /// Сюда пишутся прослушивания, скипы, время; выставляется из RootView
    @ObservationIgnored var taste: TasteStore?

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

    // Волна: движок сам дописывает очередь, пока она не кончилась
    @ObservationIgnored private var waveProvider: (@MainActor ([Track]) -> [Track])?

    // Учёт прослушивания текущего трека
    @ObservationIgnored private var listeningTrack: Track?
    @ObservationIgnored private var listened: TimeInterval = 0
    @ObservationIgnored private var lastTick: TimeInterval = 0
    @ObservationIgnored private var countedPlay = false

    init() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)

        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self else { return }
                let s = time.seconds
                self.tick(s.isFinite ? s : 0)
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
        waveProvider = nil
        waveTitle = nil
        queue = tracks
        if let shuffled { shuffle = shuffled }
        var first = min(max(start, 0), tracks.count - 1)
        if shuffled == true { first = Int.random(in: 0..<tracks.count) }
        load(first)
    }

    /// Бесконечная очередь: `provider` получает последние треки и возвращает, чем её продолжить.
    func startWave(title: String, first: [Track], provider: @escaping @MainActor ([Track]) -> [Track]) {
        guard !first.isEmpty else { return }
        queue = first
        shuffle = false
        repeatMode = .off
        waveTitle = title
        waveProvider = provider
        load(0)
    }

    func stopWave() {
        waveProvider = nil
        waveTitle = nil
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
            finishListen()
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

    /// Сыграть следующим (после текущего трека). При включённом шафле порядок всё равно случайный.
    func playNext(_ track: Track) {
        guard !queue.isEmpty else {
            play([track])
            return
        }
        queue.insert(track, at: min(index + 1, queue.count))
    }

    func addToQueue(_ track: Track) {
        guard !queue.isEmpty else {
            play([track])
            return
        }
        queue.append(track)
    }

    /// Перейти к треку в очереди (для экрана очереди).
    func jump(to i: Int) {
        load(i)
    }

    /// nil = выключить. За 20 секунд до конца звук плавно затихает.
    func setSleep(minutes: Int?) {
        player.volume = 1
        sleepDeadline = minutes.map { Date().addingTimeInterval(Double($0) * 60) }
    }

    // MARK: - Внутреннее

    private func load(_ i: Int) {
        guard queue.indices.contains(i) else { return }
        finishListen()
        index = i
        listeningTrack = queue[i]
        let item = AVPlayerItem(url: queue[i].url)
        player.replaceCurrentItem(with: item)
        duration = queue[i].duration
        currentTime = 0
        try? AVAudioSession.sharedInstance().setActive(true)
        player.play()
        isPlaying = true
        updateNowPlayingInfo()
        refillWaveIfNeeded()
    }

    private func trackEnded() {
        if repeatMode == .one {
            finishListen()
            listeningTrack = current
            player.seek(to: .zero)
            player.play()
            return
        }
        next()
    }

    private func refillWaveIfNeeded() {
        guard let provider = waveProvider, queue.count - index <= 4 else { return }
        let more = provider(Array(queue.suffix(20)))
        queue.append(contentsOf: more)
        // не копим бесконечную историю
        if index > 60 {
            let drop = index - 30
            queue.removeFirst(drop)
            index -= drop
        }
    }

    // MARK: - Учёт прослушивания (для вкуса и волны)

    private func tick(_ t: TimeInterval) {
        let delta = t - lastTick
        lastTick = t
        currentTime = t

        // считаем только честное воспроизведение: перемотка (скачок больше 2 с) не в счёт
        if isPlaying, delta > 0, delta < 2 {
            listened += delta
        }
        checkCountedPlay()

        if let deadline = sleepDeadline {
            let left = deadline.timeIntervalSinceNow
            if left <= 0 {
                pause()
                sleepDeadline = nil
                player.volume = 1
            } else if left < 20 {
                player.volume = Float(left / 20)
            }
        }
    }

    /// «Прослушал» = минута или половина трека (но не меньше 15 с)
    private func checkCountedPlay() {
        guard !countedPlay, let t = listeningTrack, let taste else { return }
        let threshold = min(60, max(t.duration * 0.5, 15))
        if listened >= threshold {
            countedPlay = true
            taste.recordPlay(track: t)
        }
    }

    /// Закрывает учёт текущего трека: добавляет время, засчитывает скип, если бросил в начале.
    private func finishListen() {
        defer {
            listened = 0
            countedPlay = false
            lastTick = 0
        }
        guard let t = listeningTrack, let taste, listened > 1 else { return }
        taste.addListening(track: t, seconds: listened)
        if !countedPlay, listened < 25, listened / max(t.duration, 1) < 0.3 {
            taste.recordSkip(track: t)
        }
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
