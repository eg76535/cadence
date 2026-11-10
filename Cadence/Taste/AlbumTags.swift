import Foundation
import Observation

/// Настроение альбома. energy/valence 0...1:
/// energy = от тихого к бешеному, valence = от мрачного к светлому.
struct AlbumTag: Codable, Hashable {
    var energy: Double
    var valence: Double
    var moods: [String]
    var genres: [String]
    var source: String      // "ai" | "genre"
}

enum Mood {
    static let all = [
        "energetic", "chill", "focus", "happy", "sad", "dark", "romantic",
        "nostalgic", "night", "party", "workout", "dreamy", "aggressive", "epic"
    ]
}

/// Теги от ИИ хранятся по альбому (а не по треку): так запросов к серверу в десятки раз меньше.
/// Пока ИИ ничего не разметила, настроение грубо выводится из жанрового тега в файле.
@MainActor @Observable
final class TagStore {
    private(set) var ai: [String: AlbumTag] = [:]

    @ObservationIgnored private var saveTask: Task<Void, Never>?

    init() {
        if let data = try? Data(contentsOf: Persist.url("album_tags.json")),
           let decoded = try? JSONDecoder().decode([String: AlbumTag].self, from: data) {
            ai = decoded
        }
    }

    func tag(for track: Track) -> AlbumTag? {
        if let t = ai[track.albumID] { return t }
        return HeuristicTagger.tag(genre: track.genre)
    }

    func merge(_ new: [String: AlbumTag]) {
        ai.merge(new) { _, fresh in fresh }
        scheduleSave()
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    func saveNow() {
        guard let data = try? JSONEncoder().encode(ai) else { return }
        try? data.write(to: Persist.url("album_tags.json"), options: .atomic)
    }
}

/// Грубая разметка по жанру из тегов файла. Работает без сервера с первого запуска.
enum HeuristicTagger {
    private static let rules: [(keys: [String], energy: Double, valence: Double, moods: [String])] = [
        (["metal", "hardcore", "grind", "thrash"], 0.92, 0.30, ["aggressive", "workout", "dark"]),
        (["punk"], 0.85, 0.50, ["energetic", "aggressive", "workout"]),
        (["drum and bass", "dnb", "jungle", "techno", "trance", "hardstyle"], 0.88, 0.55, ["energetic", "party", "workout"]),
        (["house", "dance", "edm", "electro", "disco"], 0.80, 0.70, ["party", "energetic", "happy"]),
        (["hip hop", "hip-hop", "rap", "trap"], 0.70, 0.45, ["energetic", "night"]),
        (["ambient", "drone", "new age", "meditation"], 0.12, 0.45, ["chill", "focus", "dreamy"]),
        (["classical", "orchestra", "piano", "baroque", "opera", "chamber"], 0.25, 0.45, ["focus", "chill", "epic"]),
        (["soundtrack", "score", "ost", "cinematic"], 0.40, 0.40, ["epic", "focus"]),
        (["lo-fi", "lofi", "chillout", "downtempo", "trip hop", "trip-hop"], 0.30, 0.50, ["chill", "focus", "night"]),
        (["jazz", "blues", "soul", "bossa", "swing"], 0.40, 0.55, ["chill", "night", "romantic"]),
        (["shoegaze", "dream", "post-rock", "post rock"], 0.45, 0.40, ["dreamy", "night"]),
        (["folk", "acoustic", "country", "singer"], 0.35, 0.50, ["chill", "nostalgic"]),
        (["reggae", "ska", "latin", "funk"], 0.60, 0.80, ["happy", "party"]),
        (["pop", "synth"], 0.65, 0.70, ["happy", "energetic"]),
        (["rock", "grunge", "alternative", "indie"], 0.70, 0.50, ["energetic", "nostalgic"])
    ]

    static func tag(genre: String) -> AlbumTag? {
        let g = genre.lowercased()
        guard !g.isEmpty else { return nil }
        for rule in rules where rule.keys.contains(where: { g.contains($0) }) {
            return AlbumTag(energy: rule.energy, valence: rule.valence,
                            moods: rule.moods, genres: [g], source: "genre")
        }
        return nil
    }
}
