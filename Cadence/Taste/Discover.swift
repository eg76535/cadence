import Foundation

enum RandomMode: String, CaseIterable {
    case any = "ANY"
    case taste = "TASTE"
    case unheard = "NEW"
}

struct ForYouLists {
    var forgotten: [Album] = []
    var unheard: [Album] = []
    var rotation: [Album] = []
}

struct ArtistPlays: Identifiable {
    let name: String
    let plays: Int
    var id: String { name }
}

struct TasteSummary {
    var plays = 0
    var hours = 0.0
    var liked = 0
    var topArtists: [ArtistPlays] = []
}

/// Рандом и локальные подборки. Никакой сети, всё из истории прослушиваний.
@MainActor
enum Discover {

    // MARK: - Рандом

    static func randomTrack(_ lib: Library, _ taste: TasteStore, _ mode: RandomMode) -> Track? {
        var pool = lib.tracks
        if mode == .unheard {
            let fresh = pool.filter { isUnheard($0, taste) }
            if !fresh.isEmpty { pool = fresh }
        }
        guard !pool.isEmpty else { return nil }
        if mode == .taste {
            let aff = WaveEngine.artistAffinity(lib.tracks, taste)
            return weightedPick(pool) { exp(aff[$0.artistID] ?? 0) * (taste.isLiked($0.id) ? 2 : 1) }
        }
        return pool.randomElement()
    }

    static func randomAlbum(_ lib: Library, _ taste: TasteStore, _ mode: RandomMode) -> Album? {
        var pool = lib.albums
        if mode == .unheard {
            let fresh = pool.filter { album in album.tracks.allSatisfy { isUnheard($0, taste) } }
            if !fresh.isEmpty { pool = fresh }
        }
        guard !pool.isEmpty else { return nil }
        if mode == .taste {
            let aff = WaveEngine.artistAffinity(lib.tracks, taste)
            return weightedPick(pool) { exp(aff[$0.tracks.first?.artistID ?? ""] ?? 0) }
        }
        return pool.randomElement()
    }

    static func randomArtist(_ lib: Library, _ taste: TasteStore, _ mode: RandomMode) -> (name: String, tracks: [Track])? {
        let groups = Dictionary(grouping: lib.tracks, by: { $0.artistID })
        var keys = Array(groups.keys)
        if mode == .unheard {
            let fresh = keys.filter { key in (groups[key] ?? []).allSatisfy { isUnheard($0, taste) } }
            if !fresh.isEmpty { keys = fresh }
        }
        guard !keys.isEmpty else { return nil }
        let key: String?
        if mode == .taste {
            let aff = WaveEngine.artistAffinity(lib.tracks, taste)
            key = weightedPick(keys) { exp(aff[$0] ?? 0) }
        } else {
            key = keys.randomElement()
        }
        guard let key, let tracks = groups[key], let first = tracks.first else { return nil }
        return (first.artist, tracks)
    }

    // MARK: - Подборки «Для тебя»

    static func forYou(_ lib: Library, _ taste: TasteStore, limit: Int = 12) -> ForYouLists {
        var out = ForYouLists()

        struct Row {
            let album: Album
            let plays: Int
            let liked: Int
            let last: Date?

            var score: Double { log1p(Double(plays)) + Double(liked) * 2 }
            var idleDays: Double {
                guard let last else { return .infinity }
                return Date().timeIntervalSince(last) / 86400
            }
        }
        let rows: [Row] = lib.albums.map { album in
            var plays = 0
            var liked = 0
            var last: Date?
            for t in album.tracks {
                guard let st = taste.stats[t.id] else { continue }
                plays += st.plays
                if st.liked { liked += 1 }
                if let lp = st.lastPlayed, lp > (last ?? .distantPast) { last = lp }
            }
            return Row(album: album, plays: plays, liked: liked, last: last)
        }

        // Забытое: когда-то любил, давно не слушал
        let loved = rows.filter { $0.plays >= 3 || $0.liked > 0 }
        let gone = loved.filter { $0.idleDays > 45 }
        let bestGone = gone.sorted { $0.score > $1.score }.prefix(40)
        out.forgotten = Array(bestGone.shuffled().prefix(limit)).map { $0.album }

        // Ни разу не слушал
        let fresh = rows.filter { $0.plays == 0 && $0.liked == 0 && $0.last == nil }
        out.unheard = Array(fresh.shuffled().prefix(limit)).map { $0.album }

        // В ротации: недавно и часто
        let recent = rows.filter { $0.plays > 0 && $0.idleDays < 14 }
        let byRecency = recent.sorted { $0.idleDays < $1.idleDays }
        out.rotation = byRecency.prefix(limit).map { $0.album }
        return out
    }

    // MARK: - Статистика

    static func summary(_ lib: Library, _ taste: TasteStore) -> TasteSummary {
        var out = TasteSummary()
        var perArtist: [String: (name: String, plays: Int)] = [:]
        var seconds = 0.0
        for t in lib.tracks {
            guard let st = taste.stats[t.id] else { continue }
            out.plays += st.plays
            seconds += st.listenedSeconds
            if st.liked { out.liked += 1 }
            let cur = perArtist[t.artistID] ?? (name: t.artist, plays: 0)
            perArtist[t.artistID] = (name: cur.name, plays: cur.plays + st.plays)
        }
        out.hours = seconds / 3600
        out.topArtists = perArtist.values
            .filter { $0.plays > 0 }
            .sorted { $0.plays > $1.plays }
            .prefix(5)
            .map { ArtistPlays(name: $0.name, plays: $0.plays) }
        return out
    }

    // MARK: - Для запросов к ИИ

    static func topGenres(_ lib: Library, limit: Int) -> [String] {
        var count: [String: Int] = [:]
        for t in lib.tracks where !t.genre.isEmpty {
            count[t.genre.lowercased(), default: 0] += 1
        }
        return count.sorted { $0.value > $1.value }.prefix(limit).map { $0.key }
    }

    /// Короткий портрет вкуса для промпта + ключи альбомов, которые уже есть в библиотеке.
    static func profile(_ lib: Library, _ taste: TasteStore, _ tags: TagStore) -> (text: String, ownedAlbums: Set<String>) {
        let aff = WaveEngine.artistAffinity(lib.tracks, taste)
        var names: [String: String] = [:]
        var trackCount: [String: Int] = [:]
        for t in lib.tracks {
            names[t.artistID] = t.artist
            trackCount[t.artistID, default: 0] += 1
        }

        var favKeys = names.keys.filter { (aff[$0] ?? 0) > 0.05 }.sorted { (aff[$0] ?? 0) > (aff[$1] ?? 0) }
        if favKeys.isEmpty {
            // истории ещё нет: берём тех, у кого больше всего треков
            favKeys = names.keys.sorted { (trackCount[$0] ?? 0) > (trackCount[$1] ?? 0) }
        }
        let favorites = favKeys.prefix(25).compactMap { names[$0] }

        let genres = topGenres(lib, limit: 8)

        var moodCount: [String: Int] = [:]
        for album in lib.albums {
            guard let first = album.tracks.first, let tag = tags.tag(for: first) else { continue }
            for m in tag.moods { moodCount[m, default: 0] += 1 }
        }
        let moods = moodCount.sorted { $0.value > $1.value }.prefix(6).map { $0.key }

        let owned = Array(Set(names.values)).sorted().prefix(250)
        let likedCount = taste.stats.values.filter { $0.liked }.count

        var text = "Favorite artists: \(favorites.joined(separator: "; "))\n"
        text += "Top genres: \(genres.joined(separator: ", "))\n"
        if !moods.isEmpty { text += "Typical moods: \(moods.joined(separator: ", "))\n" }
        text += "Liked tracks: \(likedCount)\n"
        text += "Artists already in my library: \(owned.joined(separator: "; "))"

        let ownedAlbums = Set(lib.albums.map { normalize($0.artist) + "|" + normalize($0.title) })
        return (text, ownedAlbums)
    }

    static func normalize(_ s: String) -> String {
        s.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    // MARK: - Внутреннее

    private static func isUnheard(_ t: Track, _ taste: TasteStore) -> Bool {
        let st = taste.stat(t.id)
        return st.plays == 0 && st.skips == 0
    }

    private static func weightedPick<T>(_ items: [T], weight: (T) -> Double) -> T? {
        guard !items.isEmpty else { return nil }
        let w = items.map { max(weight($0), 0.0001) }
        let total = w.reduce(0, +)
        var r = Double.random(in: 0..<total)
        for (i, x) in w.enumerated() {
            r -= x
            if r <= 0 { return items[i] }
        }
        return items.last
    }
}
