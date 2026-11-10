import Foundation
import Observation

/// Служебные файлы приложения лежат в Application Support, а не в Documents:
/// так они не светятся в «Файлах» и не сканируются как музыка.
enum Persist {
    static func url(_ name: String) -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Cadence", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent(name)
    }
}

struct TrackStats: Codable {
    var plays = 0
    var skips = 0
    var liked = false
    var lastPlayed: Date?
    var listenedSeconds: Double = 0
}

struct WishItem: Codable, Identifiable, Hashable {
    var id = UUID()
    var artist: String
    var album: String
    var why: String
}

/// История прослушиваний, лайки и вишлист. Всё локально, один JSON.
/// Ключ статистики = Track.id (путь относительно Documents).
@MainActor @Observable
final class TasteStore {
    private(set) var stats: [String: TrackStats] = [:]
    /// artistID -> сколько раз слушали в [ночь, утро, день, вечер]
    private(set) var artistDayparts: [String: [Int]] = [:]
    private(set) var wishlist: [WishItem] = []

    @ObservationIgnored private var saveTask: Task<Void, Never>?

    private struct Snapshot: Codable {
        var stats: [String: TrackStats]
        var artistDayparts: [String: [Int]]
        var wishlist: [WishItem]
    }

    init() {
        load()
    }

    // MARK: - Чтение

    func stat(_ id: String) -> TrackStats { stats[id] ?? TrackStats() }

    func isLiked(_ id: String) -> Bool { stats[id]?.liked ?? false }

    /// 0 ночь (0-6), 1 утро (6-12), 2 день (12-18), 3 вечер (18-24)
    static func daypart(_ date: Date = Date()) -> Int {
        let hour = Calendar.current.component(.hour, from: date)
        switch hour {
        case 0..<6: return 0
        case 6..<12: return 1
        case 12..<18: return 2
        default: return 3
        }
    }

    // MARK: - Запись событий (зовёт PlayerEngine)

    func toggleLike(_ id: String) {
        var s = stats[id] ?? TrackStats()
        s.liked.toggle()
        stats[id] = s
        scheduleSave()
    }

    func recordPlay(track: Track) {
        var s = stats[track.id] ?? TrackStats()
        s.plays += 1
        s.lastPlayed = Date()
        stats[track.id] = s

        var dp = artistDayparts[track.artistID] ?? [0, 0, 0, 0]
        dp[Self.daypart()] += 1
        artistDayparts[track.artistID] = dp
        scheduleSave()
    }

    func recordSkip(track: Track) {
        var s = stats[track.id] ?? TrackStats()
        s.skips += 1
        stats[track.id] = s
        scheduleSave()
    }

    func addListening(track: Track, seconds: TimeInterval) {
        var s = stats[track.id] ?? TrackStats()
        s.listenedSeconds += seconds
        stats[track.id] = s
        scheduleSave()
    }

    // MARK: - Вишлист

    func addWish(artist: String, album: String, why: String) {
        let exists = wishlist.contains {
            $0.artist.lowercased() == artist.lowercased() && $0.album.lowercased() == album.lowercased()
        }
        guard !exists else { return }
        wishlist.insert(WishItem(artist: artist, album: album, why: why), at: 0)
        scheduleSave()
    }

    func removeWish(_ item: WishItem) {
        wishlist.removeAll { $0.id == item.id }
        scheduleSave()
    }

    // MARK: - Диск

    private func load() {
        guard let data = try? Data(contentsOf: Persist.url("taste.json")),
              let snap = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        stats = snap.stats
        artistDayparts = snap.artistDayparts
        wishlist = snap.wishlist
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    func saveNow() {
        let snap = Snapshot(stats: stats, artistDayparts: artistDayparts, wishlist: wishlist)
        guard let data = try? JSONEncoder().encode(snap) else { return }
        try? data.write(to: Persist.url("taste.json"), options: .atomic)
    }
}
