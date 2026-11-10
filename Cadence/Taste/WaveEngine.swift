import Foundation

// «Моя волна»: бесконечная очередь, собранная под вкус и настроение.
// Всё считается на телефоне и ничего не стоит: ИИ нужна только чтобы один раз
// разметить альбомы и (по желанию) разобрать текстовый запрос в фильтр.

/// Фильтр волны. Пустой запрос = просто «моя волна» по вкусу и времени суток.
struct WaveRequest: Equatable {
    var title: String = "MY WAVE"
    var moods: [String] = []
    var energy: ClosedRange<Double>?
    var valence: ClosedRange<Double>?
    var genres: [String] = []
    var avoidGenres: [String] = []
    var artists: [String] = []
    /// 0 = только знакомое, 1 = в основном то, что ещё не слушал
    var novelty: Double = 0.2
}

extension WaveRequest {
    /// Разбор JSON от ИИ. Терпимый: числа могут быть 0...1 или 0...100, поля можно не указывать.
    static func from(json: [String: Any]) -> WaveRequest {
        var r = WaveRequest()
        if let t = json["title"] as? String, !t.trimmingCharacters(in: .whitespaces).isEmpty {
            r.title = String(t.uppercased().prefix(24))
        }
        r.moods = strings(json["moods"]).map { $0.lowercased() }.filter { Mood.all.contains($0) }
        r.energy = range(json["energy"])
        r.valence = range(json["valence"])
        r.genres = strings(json["genres"]).map { $0.lowercased() }
        r.avoidGenres = strings(json["avoid_genres"]).map { $0.lowercased() }
        r.artists = strings(json["artists"]).map { $0.lowercased() }
        if let n = number(json["novelty"]) {
            r.novelty = min(max(n > 1 ? n / 100 : n, 0), 1)
        }
        return r
    }

    private static func number(_ v: Any?) -> Double? {
        if let d = v as? Double { return d }
        if let i = v as? Int { return Double(i) }
        if let s = v as? String { return Double(s) }
        return nil
    }

    private static func strings(_ v: Any?) -> [String] {
        (v as? [Any])?.compactMap { $0 as? String } ?? []
    }

    private static func range(_ v: Any?) -> ClosedRange<Double>? {
        guard let a = v as? [Any], a.count == 2,
              var lo = number(a[0]), var hi = number(a[1]) else { return nil }
        if lo > 1 || hi > 1 { lo /= 100; hi /= 100 }
        lo = min(max(lo, 0), 1)
        hi = min(max(hi, 0), 1)
        return min(lo, hi)...max(lo, hi)
    }

    // MARK: - Локальный разбор текста (когда сервер недоступен)

    private static let keywordRules: [(keys: [String], moods: [String], energy: ClosedRange<Double>?, valence: ClosedRange<Double>?)] = [
        (["спокой", "calm", "relax", "расслаб", "chill", "чил", "уют"], ["chill"], 0.0...0.5, nil),
        (["энерг", "бодр", "energy", "energetic", "драйв"], ["energetic"], 0.6...1.0, nil),
        (["груст", "sad", "меланхол", "дожд", "rain", "тоск"], ["sad", "nostalgic"], 0.0...0.6, 0.0...0.45),
        (["фокус", "работ", "учёб", "учеб", "focus", "study", "concentr", "код", "coding"], ["focus"], 0.0...0.6, nil),
        (["трен", "спорт", "gym", "workout", "бег", "run", "качал"], ["workout", "energetic"], 0.65...1.0, nil),
        (["ноч", "night", "late"], ["night"], nil, nil),
        (["вечерин", "party", "танц", "dance", "тусов"], ["party"], 0.6...1.0, nil),
        (["романт", "love", "любов"], ["romantic"], nil, nil),
        (["мрач", "dark", "тёмн", "темн", "злой", "зло"], ["dark"], nil, 0.0...0.5),
        (["счаст", "happy", "весел", "радост", "позитив"], ["happy"], nil, 0.6...1.0),
        (["тяжел", "тяжёл", "heavy", "metal", "метал", "агресс"], ["aggressive"], 0.75...1.0, nil),
        (["мечт", "dream", "космос", "space", "ambient", "эмбиент", "море", "sea"], ["dreamy"], 0.0...0.6, nil),
        (["ностальг", "retro", "ретро"], ["nostalgic"], nil, nil),
        (["эпич", "epic", "кино", "cinema"], ["epic"], nil, nil)
    ]

    static func fromText(_ text: String) -> WaveRequest {
        let low = text.lowercased()
        var r = WaveRequest()
        for rule in keywordRules where rule.keys.contains(where: { low.contains($0) }) {
            for m in rule.moods where !r.moods.contains(m) { r.moods.append(m) }
            if let e = rule.energy { r.energy = merged(r.energy, e) }
            if let v = rule.valence { r.valence = merged(r.valence, v) }
        }
        if ["нов", "незнаком", "new", "unknown", "откры", "неслушан"].contains(where: { low.contains($0) }) {
            r.novelty = 0.85
        }
        if ["знаком", "любим", "favorite", "fav", "привычн"].contains(where: { low.contains($0) }) {
            r.novelty = 0.0
        }
        let words = text.split(separator: " ").prefix(2).joined(separator: " ")
        r.title = words.isEmpty ? "CUSTOM" : String(words.uppercased().prefix(24))
        return r
    }

    private static func merged(_ old: ClosedRange<Double>?, _ new: ClosedRange<Double>) -> ClosedRange<Double> {
        guard let old else { return new }
        let lo = max(old.lowerBound, new.lowerBound)
        let hi = min(old.upperBound, new.upperBound)
        return lo <= hi ? lo...hi : new
    }
}

@MainActor
enum WaveEngine {
    /// Подбирает `count` треков. `recent` — то, что уже играло или стоит в очереди (не повторяем).
    static func pick(request: WaveRequest, library: Library, taste: TasteStore, tags: TagStore,
                     count: Int, recent: [Track]) -> [Track] {
        let all = library.tracks
        guard !all.isEmpty else { return [] }

        let affinity = artistAffinity(all, taste)
        let recentIDs = Set(recent.map { $0.id })
        let recentArtists = recent.suffix(4).map { $0.artistID }
        let daypart = TasteStore.daypart()
        let now = Date()

        func score(_ t: Track, strict: Bool) -> Double? {
            if recentIDs.contains(t.id) { return nil }
            let st = taste.stats[t.id] ?? TrackStats()
            let lowGenre = t.genre.lowercased()
            let tag = tags.tag(for: t)
            var s = 0.0

            // вкус
            s += min(log1p(Double(st.plays)), 3) * 0.6
            if st.liked { s += 1.6 }
            s -= Double(min(st.skips, 4)) * 0.45
            s += (affinity[t.artistID] ?? 0) * 1.2

            // жанры
            for g in request.avoidGenres where genreMatches(g, lowGenre, tag) { return nil }
            if !request.genres.isEmpty {
                if request.genres.contains(where: { genreMatches($0, lowGenre, tag) }) {
                    s += 2.0
                } else if strict {
                    return nil
                } else {
                    s -= 2.0
                }
            }
            if !request.artists.isEmpty, request.artists.contains(where: { t.artistID.contains($0) }) {
                s += 3.0
            }

            // настроение
            let wantsMood = !request.moods.isEmpty || request.energy != nil || request.valence != nil
            if let tag {
                if let r = request.energy {
                    let d = distance(tag.energy, r)
                    if d > 0.3 && strict { return nil }
                    s -= d * 4
                }
                if let r = request.valence {
                    let d = distance(tag.valence, r)
                    if d > 0.3 && strict { return nil }
                    s -= d * 4
                }
                if !request.moods.isEmpty {
                    let hit = request.moods.filter { tag.moods.contains($0) }.count
                    if hit == 0 && strict { return nil }
                    s += Double(hit) / Double(request.moods.count) * 2.5
                }
            } else if wantsMood {
                if strict { return nil }
                s -= 1.2
            }

            // время суток
            if let dp = taste.artistDayparts[t.artistID] {
                let total = dp.reduce(0, +)
                if total >= 5 {
                    s += (Double(dp[daypart]) / Double(total) - 0.25) * 1.6
                }
            }

            // знакомое / новое
            let unplayed = st.plays == 0 && st.skips == 0
            if unplayed {
                s += (request.novelty - 0.3) * 3
            } else {
                s += (0.3 - request.novelty) * min(log1p(Double(st.plays)), 2) * 0.7
            }

            // не гонять одно и то же
            if let lp = st.lastPlayed {
                let hours = now.timeIntervalSince(lp) / 3600
                if hours < 6 { s -= 2.5 } else if hours < 24 { s -= 1.0 } else if hours < 72 { s -= 0.3 }
            }
            return s
        }

        func ranked(strict: Bool) -> [(track: Track, key: Double)] {
            var out: [(track: Track, key: Double)] = []
            out.reserveCapacity(all.count)
            for t in all {
                guard let s = score(t, strict: strict) else { continue }
                // Gumbel-шум: взвешенная случайная выборка без повторов
                let u = Double.random(in: 1e-9..<1)
                out.append((t, s / 0.8 - log(-log(u))))
            }
            out.sort { $0.key > $1.key }
            return out
        }

        var pool = ranked(strict: true)
        if pool.count < count * 2 {
            pool = ranked(strict: false)
        }

        // разводим исполнителей: не подряд и не больше двух за пачку
        var picked: [Track] = []
        var pickedIDs = Set<String>()
        var perArtist: [String: Int] = [:]
        var lastArtists = recentArtists
        for item in pool {
            if picked.count >= count { break }
            let a = item.track.artistID
            if lastArtists.suffix(3).contains(a) { continue }
            if (perArtist[a] ?? 0) >= 2 { continue }
            picked.append(item.track)
            pickedIDs.insert(item.track.id)
            perArtist[a, default: 0] += 1
            lastArtists.append(a)
        }
        if picked.count < count {
            for item in pool where !pickedIDs.contains(item.track.id) {
                if picked.count >= count { break }
                picked.append(item.track)
            }
        }
        return picked
    }

    // MARK: - Помощники

    /// Симпатия к исполнителю, примерно -2...2: прослушивания, лайки, скипы.
    static func artistAffinity(_ tracks: [Track], _ taste: TasteStore) -> [String: Double] {
        var sum: [String: Double] = [:]
        var count: [String: Int] = [:]
        for t in tracks {
            count[t.artistID, default: 0] += 1
            if let st = taste.stats[t.id] {
                sum[t.artistID, default: 0] += log1p(Double(st.plays))
                    + (st.liked ? 2.5 : 0)
                    - Double(min(st.skips, 4)) * 0.5
            }
        }
        var out: [String: Double] = [:]
        var peak = 0.001
        for (k, v) in sum {
            let a = v / (1 + Double(count[k] ?? 1)).squareRoot()
            out[k] = a
            peak = max(peak, abs(a))
        }
        for (k, v) in out {
            out[k] = v / peak * 2
        }
        return out
    }

    private static func distance(_ x: Double, _ r: ClosedRange<Double>) -> Double {
        if x < r.lowerBound { return r.lowerBound - x }
        if x > r.upperBound { return x - r.upperBound }
        return 0
    }

    private static func genreMatches(_ g: String, _ lowGenre: String, _ tag: AlbumTag?) -> Bool {
        if lowGenre.contains(g) { return true }
        return tag?.genres.contains(where: { $0.lowercased().contains(g) }) ?? false
    }
}

/// Запускает волну в плеере и обещает ему подкидывать треки, пока очередь не кончится.
@MainActor
enum WaveRunner {
    static func start(_ request: WaveRequest, library: Library, player: PlayerEngine,
                      taste: TasteStore, tags: TagStore, seed: [Track] = []) {
        let seedIDs = Set(seed.map { $0.id })
        var first = seed
        let extra = WaveEngine.pick(request: request, library: library, taste: taste, tags: tags,
                                    count: 20, recent: seed)
        first += extra.filter { !seedIDs.contains($0.id) }

        player.startWave(title: request.title, first: first) { [weak library, weak taste, weak tags] recent in
            guard let library, let taste, let tags else { return [] }
            return WaveEngine.pick(request: request, library: library, taste: taste, tags: tags,
                                   count: 15, recent: recent)
        }
    }
}
