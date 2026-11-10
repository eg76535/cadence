import Foundation
import UIKit
import Observation

// Клиент к твоей ИИ на домашнем сервере. Нужен любой OpenAI-совместимый endpoint
// (llama.cpp server, Open WebUI, Ollama, прокси перед Hermes: у всех есть /v1/chat/completions).
//
// Сервер у тебя на CPU, поэтому:
//  - запросы редкие и короткие, ответы маленькие (JSON на десятки токенов);
//  - разметка альбомов идёт один раз, пачками, и кешируется навсегда (TagStore);
//  - без сервера всё остальное (волна, рандом, подборки) работает как обычно.

enum AIError: LocalizedError {
    case notConfigured
    case http(Int)
    case badReply

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Сервер не настроен (WAVE → SERVER)"
        case .http(let code): return "Сервер ответил \(code)"
        case .badReply: return "ИИ вернула не JSON, попробуй ещё раз"
        }
    }
}

enum RecMode: String, CaseIterable {
    case similar = "MY TASTE"
    case expand = "EXPAND"
    case classics = "CLASSICS"
    case fresh = "FRESH"

    var instruction: String {
        switch self {
        case .similar: return "Albums very close to my taste that I probably don't know yet."
        case .expand: return "Albums from adjacent genres and scenes that would widen my horizons but still fit my taste."
        case .classics: return "Essential, canonical albums of my favorite genres that every fan should know."
        case .fresh: return "Good albums released in the last 3 years that fit my taste."
        }
    }
}

struct Recommendation: Identifiable, Hashable {
    let id = UUID()
    let artist: String
    let album: String
    let year: Int?
    let why: String
}

@MainActor @Observable
final class ServerAI {
    private(set) var busy = false
    private(set) var status = ""
    private(set) var lastError: String?

    private(set) var tagging = false
    private(set) var tagDone = 0
    private(set) var tagTotal = 0

    @ObservationIgnored private var tagTask: Task<Void, Never>?
    @ObservationIgnored private let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 900      // CPU-модель может думать долго
        c.timeoutIntervalForResource = 1800
        return URLSession(configuration: c)
    }()

    var isConfigured: Bool {
        !(UserDefaults.standard.string(forKey: "ai.url") ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Публичное

    func ping() async throws -> String {
        busy = true
        status = "PING…"
        defer { busy = false; status = "" }
        return try await chat(system: "Reply with the single word: ok", user: "ping", maxTokens: 8)
    }

    /// Текстовый запрос -> фильтр волны.
    func waveRequest(from text: String, libraryGenres: [String]) async throws -> WaveRequest {
        busy = true
        status = "ASKING SERVER…"
        defer { busy = false; status = "" }

        let system = """
        You turn a music request into a JSON playlist filter for a music player. Reply with ONLY one JSON object, no prose.
        Keys (include only those that matter): "title" (max 3 words, English, UPPERCASE), \
        "moods" (choose from: \(Mood.all.joined(separator: ", "))), \
        "energy" [min,max] on 0-100, "valence" [min,max] on 0-100 (0 = dark/sad, 100 = bright/happy), \
        "genres" (lowercase, prefer ones from the library list), "avoid_genres", \
        "novelty" 0-100 (0 = only familiar music, 100 = only music I have not heard).
        """
        let user = "Request: \(text)\nLibrary genres: \(libraryGenres.joined(separator: ", "))"
        let reply = try await chat(system: system, user: user, maxTokens: 220)
        guard let obj = Self.extractJSON(reply) as? [String: Any] else { throw AIError.badReply }
        return WaveRequest.from(json: obj)
    }

    /// Описание словами -> тема оформления. Накладывается на текущую тему, поэтому раскладка
    /// и параметры Cover Flow остаются как были, меняется только внешний вид.
    func generateTheme(prompt: String, current: ThemeSpec) async throws -> ThemeSpec {
        busy = true
        status = "DESIGNING…"
        defer { busy = false; status = "" }

        let system = """
        You are a UI designer for a music player app. Turn the user's description into a color theme. \
        Reply with ONLY one JSON object, no prose. Keys: "name" (max 3 words), \
        "bg","fg","dim","accent" (hex #rrggbb; fg must contrast strongly with bg, dim is a muted version of fg, accent is a vivid highlight), \
        "wall" (solid|gradient|aurora|cover), "wA","wB","wC" (hex, used by gradient and aurora), \
        "wDim" 0-0.85 (how much the wallpaper is darkened), "glass" true/false (translucent bars), \
        "font" (sf|rounded|serif), "radius" 0-24 (cover corner radius), "uiR" 0-32 (panel corner radius).
        """
        let reply = try await chat(system: system, user: "Description: \(prompt)", maxTokens: 320, temperature: 0.7)
        guard let obj = Self.extractJSON(reply) as? [String: Any] else { throw AIError.badReply }

        let allowed: Set<String> = [
            "name", "bg", "fg", "dim", "accent", "wall", "wA", "wB", "wC",
            "wDim", "glass", "font", "radius", "uiR"
        ]
        var merged: [String: Any] = [:]
        if let base = try? JSONSerialization.jsonObject(with: Data(current.jsonString().utf8)) as? [String: Any] {
            merged = base
        }
        for (key, value) in obj where allowed.contains(key) {
            merged[key] = value
        }
        guard let data = try? JSONSerialization.data(withJSONObject: merged),
              let spec = ThemeSpec.parse(data) else { throw AIError.badReply }
        return spec
    }

    /// Альбомы, которых нет в библиотеке, под вкус.
    func recommend(mode: RecMode, hint: String, library: Library, taste: TasteStore, tags: TagStore) async throws -> [Recommendation] {
        busy = true
        status = "ASKING SERVER…"
        defer { busy = false; status = "" }

        let profile = Discover.profile(library, taste, tags)
        let system = """
        You are a music recommender. Reply with ONLY a JSON object: \
        {"recs":[{"artist":"","album":"","year":2000,"why":"max 12 words, in Russian"}]}. \
        Give exactly 10 real albums that exist. If you are not sure an album exists, pick another one. \
        Do not suggest albums by artists listed as already in my library unless it is clearly a different, notable album.
        """
        var user = "\(profile.text)\n\nTask: \(mode.instruction)"
        let cleanHint = hint.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanHint.isEmpty { user += "\nExtra wish: \(cleanHint)" }

        let reply = try await chat(system: system, user: user, maxTokens: 900, temperature: 0.6)
        let parsed = Self.extractJSON(reply)
        let items: [[String: Any]]
        if let obj = parsed as? [String: Any], let arr = obj["recs"] as? [[String: Any]] {
            items = arr
        } else if let arr = parsed as? [[String: Any]] {
            items = arr
        } else {
            throw AIError.badReply
        }

        var out: [Recommendation] = []
        for d in items {
            guard let artist = d["artist"] as? String, let album = d["album"] as? String else { continue }
            let key = Discover.normalize(artist) + "|" + Discover.normalize(album)
            if profile.ownedAlbums.contains(key) { continue }
            let year = (d["year"] as? Int) ?? Int(d["year"] as? String ?? "")
            out.append(Recommendation(artist: artist, album: album, year: year, why: (d["why"] as? String) ?? ""))
        }
        return out
    }

    // MARK: - Разметка альбомов

    func startTagging(library: Library, tags: TagStore, taste: TasteStore) {
        guard !tagging, isConfigured else { return }
        let plays: (Album) -> Int = { a in a.tracks.reduce(0) { $0 + taste.stat($1.id).plays } }
        // сначала то, что слушаешь чаще: волна быстрее становится умной
        let pending = library.albums
            .filter { tags.ai[$0.id] == nil }
            .sorted { plays($0) > plays($1) }
        guard !pending.isEmpty else { return }

        tagging = true
        tagTotal = pending.count
        tagDone = 0
        lastError = nil
        UIApplication.shared.isIdleTimerDisabled = true     // экран не гаснет, пока идёт разметка

        tagTask = Task { [weak self] in
            guard let self else { return }
            var i = 0
            while i < pending.count && !Task.isCancelled {
                let chunk = Array(pending[i..<min(i + 12, pending.count)])
                do {
                    let result = try await self.tagBatch(chunk)
                    tags.merge(result)
                } catch {
                    self.lastError = error.localizedDescription
                    break
                }
                i += chunk.count
                self.tagDone = i
            }
            self.tagging = false
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    func stopTagging() {
        tagTask?.cancel()
    }

    private func tagBatch(_ chunk: [Album]) async throws -> [String: AlbumTag] {
        let system = """
        You classify music albums for a mood-based player. Input lines: index|artist|album|genre tag|year|sample track titles. \
        Reply with ONLY a JSON array, one object per input line, same order: \
        {"i":index,"e":energy 0-100,"v":valence 0-100 (0 dark/sad, 100 bright/happy),"m":[1-4 moods],"g":[1-2 short lowercase genres]}. \
        Allowed moods: \(Mood.all.joined(separator: ", ")). \
        Use what you know about the artist and album; if unsure, infer from genre and titles. Never skip an item.
        """
        var lines: [String] = []
        for (i, a) in chunk.enumerated() {
            let genre = a.tracks.first(where: { !$0.genre.isEmpty })?.genre ?? ""
            let year = a.tracks.first(where: { $0.year > 0 })?.year
            let yearText = year.map { String($0) } ?? ""
            let sample = a.tracks.prefix(3).map { $0.title }.joined(separator: "; ")
            lines.append("\(i)|\(a.artist)|\(a.title)|\(genre)|\(yearText)|\(sample)")
        }

        let reply = try await chat(system: system, user: lines.joined(separator: "\n"),
                                   maxTokens: 70 * chunk.count + 60, temperature: 0.2)
        guard let arr = Self.extractJSON(reply) as? [[String: Any]] else { throw AIError.badReply }

        var out: [String: AlbumTag] = [:]
        for d in arr {
            guard let idx = (d["i"] as? Int) ?? Int(d["i"] as? String ?? ""),
                  chunk.indices.contains(idx) else { continue }
            let e = Self.unit(d["e"]) ?? 0.5
            let v = Self.unit(d["v"]) ?? 0.5
            let moods = ((d["m"] as? [Any]) ?? []).compactMap { $0 as? String }
                .map { $0.lowercased() }
                .filter { Mood.all.contains($0) }
            let genres = ((d["g"] as? [Any]) ?? []).compactMap { $0 as? String }
                .map { $0.lowercased() }
            out[chunk[idx].id] = AlbumTag(energy: e, valence: v, moods: Array(moods.prefix(4)),
                                          genres: Array(genres.prefix(2)), source: "ai")
        }
        return out
    }

    // MARK: - Транспорт

    private func chat(system: String, user: String, maxTokens: Int, temperature: Double = 0.3) async throws -> String {
        let d = UserDefaults.standard
        var base = (d.string(forKey: "ai.url") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty else { throw AIError.notConfigured }
        while base.hasSuffix("/") { base.removeLast() }
        if !base.hasSuffix("/v1") { base += "/v1" }
        guard let url = URL(string: base + "/chat/completions") else { throw AIError.notConfigured }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let key = d.string(forKey: "ai.key"), !key.isEmpty {
            req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }

        // Qwen3 любит сначала «думать»: на CPU это минуты. Просим не думать (оба способа безвредны, если не поддерживаются).
        var body: [String: Any] = [
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user + "\n/no_think"]
            ],
            "max_tokens": maxTokens,
            "temperature": temperature,
            "stream": false,
            "chat_template_kwargs": ["enable_thinking": false]
        ]
        if let model = d.string(forKey: "ai.model"), !model.isEmpty { body["model"] = model }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await session.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode != 200 {
            throw AIError.http(http.statusCode)
        }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = root["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let text = message["content"] as? String else { throw AIError.badReply }

        return text
            .replacingOccurrences(of: "(?s)<think>.*?</think>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Достаёт первый JSON-объект или массив из ответа (модели любят добавлять ```json и болтовню).
    private static func extractJSON(_ text: String) -> Any? {
        guard let start = text.firstIndex(where: { $0 == "{" || $0 == "[" }) else { return nil }
        let closer: Character = text[start] == "{" ? "}" : "]"
        guard let end = text.lastIndex(of: closer), end > start else { return nil }
        return try? JSONSerialization.jsonObject(with: Data(text[start...end].utf8))
    }

    /// 0-100 или 0-1 -> 0...1
    private static func unit(_ v: Any?) -> Double? {
        var x: Double?
        if let d = v as? Double { x = d }
        else if let i = v as? Int { x = Double(i) }
        else if let s = v as? String { x = Double(s) }
        guard var value = x else { return nil }
        if value > 1 { value /= 100 }
        return min(max(value, 0), 1)
    }
}
