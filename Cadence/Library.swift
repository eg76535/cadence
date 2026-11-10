import UIKit
import Observation

/// Что делать с треками, у которых нет тега альбома и которые лежат не в папке альбома.
enum AlbumFallback: String, CaseIterable, Identifiable {
    case single     // каждая песня = свой «альбом» с её названием
    case artist     // все такие песни исполнителя в одном альбоме «Артист · Singles»
    case unknown    // всё в один «Unknown Album»

    var id: String { rawValue }

    var label: String {
        switch self {
        case .single: return "SONG TITLE"
        case .artist: return "ARTIST · SINGLES"
        case .unknown: return "UNKNOWN ALBUM"
        }
    }
}

/// Одна запись кеша: теги ровно как в файле ("" = тега нет). Догадки по папкам и правки
/// применяются при каждой сборке библиотеки, поэтому смена настроек не требует пересканирования.
struct CacheEntry: Codable {
    var id: String
    var mtime: Double
    var size: Int
    var title: String
    var artist: String
    var albumArtist: String
    var album: String
    var number: Int
    var disc: Int
    var duration: Double
    var genre: String
    var year: Int
    var cover: String?
}

private struct CacheFile: Codable {
    var version: Int
    var entries: [CacheEntry]
}

struct ScanFile: Sendable {
    let url: URL
    let id: String
    let mtime: Double
    let size: Int
}

struct ChangeReport {
    var added = 0
    var changed = 0
    var removed = 0
    var total: Int { added + changed + removed }
}

struct LibraryStats {
    var tracks = 0
    var albums = 0
    var noAlbumTag = 0
    var noArtistTag = 0
    var albumsNoCover = 0
    var edited = 0
}

/// Библиотека живёт в кеше `library.json`. Папка Documents читается только по кнопке
/// (Settings → Library) и при самом первом запуске.
@MainActor @Observable
final class Library {
    private(set) var albums: [Album] = []
    private(set) var tracks: [Track] = []
    let covers = CoverStore()

    private(set) var isScanning = false
    private(set) var scanDone = 0
    private(set) var scanTotal = 0
    private(set) var scanNote = ""
    private(set) var lastScan: Date?
    private(set) var hasCache = false
    private(set) var changes: ChangeReport?
    private(set) var fallback: AlbumFallback = .single
    private(set) var edits: [String: TrackEdit] = [:]
    private(set) var stats = LibraryStats()
    /// Песни без тега альбома, которым ещё не назначили альбом вручную (для экрана «Fix albums»).
    private(set) var untagged: [Track] = []

    @ObservationIgnored private var entries: [CacheEntry] = []

    nonisolated static let cacheVersion = 2

    nonisolated static let audioExtensions: Set<String> = [
        "mp3", "m4a", "aac", "flac", "wav", "aif", "aiff", "caf", "alac"
    ]

    nonisolated static var documentsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    init() {
        let defaults = UserDefaults.standard
        fallback = AlbumFallback(rawValue: defaults.string(forKey: "lib.fallback") ?? "") ?? .single
        let stamp = defaults.double(forKey: "lib.lastScan")
        if stamp > 0 { lastScan = Date(timeIntervalSince1970: stamp) }

        if let data = try? Data(contentsOf: Persist.url("library.json")),
           let file = try? JSONDecoder().decode(CacheFile.self, from: data),
           file.version == Library.cacheVersion {
            entries = file.entries
            hasCache = true
        }
        if let data = try? Data(contentsOf: Persist.url("edits.json")),
           let saved = try? JSONDecoder().decode([String: TrackEdit].self, from: data) {
            edits = saved
        }
        regroup()
    }

    // MARK: - Сканирование

    /// Первый запуск (или кеш из старой версии): читаем всё один раз.
    func bootstrapIfNeeded() async {
        if !hasCache && !isScanning {
            await rescan(full: true)
        }
    }

    /// full = false: читаются только новые и изменённые файлы, пропавшие убираются.
    /// full = true: кеш выбрасывается и все теги и обложки читаются заново.
    func rescan(full: Bool = false) async {
        guard !isScanning else { return }
        isScanning = true
        scanDone = 0
        scanTotal = 0
        scanNote = "LISTING FILES"
        defer {
            isScanning = false
            scanNote = ""
        }

        let root = Library.documentsURL
        let files: [ScanFile] = await Task.detached(priority: .userInitiated) {
            Library.listFiles(root: root)
        }.value

        var known: [String: CacheEntry] = [:]
        if !full {
            for e in entries { known[e.id] = e }
        }

        var keep: [CacheEntry] = []
        var todo: [ScanFile] = []
        for f in files {
            if let e = known[f.id], e.mtime == f.mtime, e.size == f.size {
                keep.append(e)
            } else {
                todo.append(f)
            }
        }

        scanTotal = todo.count
        scanNote = todo.isEmpty ? "COVERS" : "READING TAGS"
        let progress: @Sendable (Int) -> Void = { [weak self] done in
            Task { @MainActor in self?.scanDone = done }
        }
        let fresh: [CacheEntry] = await Library.readAll(todo, progress: progress)

        scanNote = "COVERS"
        let merged: [CacheEntry] = keep + fresh
        let finished: [CacheEntry] = await Task.detached(priority: .utility) { () -> [CacheEntry] in
            var list = Library.fillFolderArt(merged, root: root)
            list.sort { $0.id < $1.id }
            return list
        }.value

        entries = finished
        hasCache = true
        lastScan = Date()
        UserDefaults.standard.set(lastScan?.timeIntervalSince1970 ?? 0, forKey: "lib.lastScan")
        changes = nil
        saveCache()
        regroup()

        let used = Set(finished.compactMap { $0.cover })
        Task.detached(priority: .background) { CoverDisk.prune(keeping: used) }
    }

    /// Дешёвая проверка без чтения тегов: сколько файлов новых, изменённых и удалённых.
    func checkChanges() async {
        guard !isScanning else { return }
        let root = Library.documentsURL
        let files: [ScanFile] = await Task.detached(priority: .userInitiated) {
            Library.listFiles(root: root)
        }.value

        var known: [String: CacheEntry] = [:]
        for e in entries { known[e.id] = e }

        var report = ChangeReport()
        var seen = Set<String>()
        for f in files {
            seen.insert(f.id)
            if let e = known[f.id] {
                if e.mtime != f.mtime || e.size != f.size { report.changed += 1 }
            } else {
                report.added += 1
            }
        }
        for e in entries where !seen.contains(e.id) {
            report.removed += 1
        }
        changes = report
    }

    // MARK: - Настройки и правки

    func setFallback(_ value: AlbumFallback) {
        guard value != fallback else { return }
        fallback = value
        UserDefaults.standard.set(value.rawValue, forKey: "lib.fallback")
        regroup()
    }

    /// Применяет правку к набору треков. Пустая правка удаляется.
    func editTracks(_ ids: [String], _ change: (inout TrackEdit) -> Void) {
        for id in ids {
            var e = edits[id] ?? TrackEdit()
            change(&e)
            edits[id] = e.isEmpty ? nil : e
        }
        saveEdits()
        regroup()
    }

    func resetEdits(_ ids: [String]) {
        for id in ids { edits[id] = nil }
        saveEdits()
        regroup()
    }

    func hasEdits(_ ids: [String]) -> Bool {
        ids.contains { edits[$0] != nil }
    }

    // MARK: - Сборка альбомов

    func regroup() {
        var buckets: [String: [Track]] = [:]
        var coverByAlbum: [String: String] = [:]
        var noAlbumTag = 0
        var noArtistTag = 0
        var loose: [Track] = []

        for e in entries {
            let track = resolve(e)
            buckets[track.albumID, default: []].append(track)
            if coverByAlbum[track.albumID] == nil, let c = e.cover {
                coverByAlbum[track.albumID] = c
            }
            if e.album.isEmpty {
                noAlbumTag += 1
                // в подпапке альбом берётся из имени папки, чинить нужно только то, что лежит в корне
                if edits[e.id]?.album == nil && !e.id.contains("/") { loose.append(track) }
            }
            if e.artist.isEmpty { noArtistTag += 1 }
        }

        var list: [Album] = []
        list.reserveCapacity(buckets.count)
        for (id, items) in buckets {
            let sorted = items.sorted { Library.trackBefore($0, $1) }
            let first = sorted[0]
            let named = sorted.first(where: { !$0.albumArtist.isEmpty })?.albumArtist
            let artists = Set(sorted.map { $0.artist.lowercased() })
            let artist: String = named ?? (artists.count == 1 ? first.artist : "Various Artists")
            let years = sorted.map { $0.year }.filter { $0 > 0 }
            list.append(Album(id: id, title: first.album, artist: artist, year: years.min() ?? 0, tracks: sorted))
        }
        list.sort {
            ($0.artist.lowercased(), $0.title.lowercased()) < ($1.artist.lowercased(), $1.title.lowercased())
        }

        albums = list
        tracks = list.flatMap { $0.tracks }.sorted { $0.title.lowercased() < $1.title.lowercased() }
        covers.setKeys(coverByAlbum)
        untagged = loose.sorted { $0.id < $1.id }

        var s = LibraryStats()
        s.tracks = tracks.count
        s.albums = list.count
        s.noAlbumTag = noAlbumTag
        s.noArtistTag = noArtistTag
        s.albumsNoCover = list.filter { coverByAlbum[$0.id] == nil }.count
        s.edited = edits.count
        stats = s
    }

    private nonisolated static func trackBefore(_ a: Track, _ b: Track) -> Bool {
        (a.disc, a.sortNumber, a.title.lowercased()) < (b.disc, b.sortNumber, b.title.lowercased())
    }

    /// Теги из кеша + правки пользователя + догадки по имени файла и папкам.
    private func resolve(_ e: CacheEntry) -> Track {
        let edit = edits[e.id]
        let comps = e.id.split(separator: "/").map { String($0) }
        let lastName = comps.last ?? e.id
        let dirs = Array(comps.dropLast())

        // папки CD1 / Disc 2 не считаются папкой альбома
        var albumDirs = dirs
        if let last = albumDirs.last, Library.isDiscFolder(last) { albumDirs.removeLast() }
        let albumFolder: String? = albumDirs.last
        let artistFolder: String? = albumDirs.count >= 2 ? albumDirs[albumDirs.count - 2] : nil
        let folderKey = albumDirs.joined(separator: "/").lowercased()

        // имя файла: "01 - Artist - Title"
        let base = (lastName as NSString).deletingPathExtension
        let parsed = Library.parseFileName(base)
        var fileTitle = parsed.title
        var fileArtist = ""
        if e.title.isEmpty, let r = fileTitle.range(of: " - ") {
            let left = String(fileTitle[..<r.lowerBound]).trimmingCharacters(in: .whitespaces)
            let right = String(fileTitle[r.upperBound...]).trimmingCharacters(in: .whitespaces)
            if !left.isEmpty && !right.isEmpty {
                fileArtist = left
                fileTitle = right
            }
        }

        let title: String = Library.nonEmpty(edit?.title) ?? Library.nonEmpty(e.title) ?? fileTitle

        var artistGuess: String? = Library.nonEmpty(edit?.artist) ?? Library.nonEmpty(e.artist)
        if artistGuess == nil && !fileArtist.isEmpty { artistGuess = fileArtist }
        if artistGuess == nil { artistGuess = artistFolder }
        let artist: String = artistGuess ?? "Unknown Artist"

        let albumArtist: String = Library.nonEmpty(edit?.albumArtist) ?? Library.nonEmpty(e.albumArtist) ?? ""

        let editedAlbum: String? = Library.nonEmpty(edit?.album)
        let taggedAlbum: String? = editedAlbum ?? Library.nonEmpty(e.album)

        let albumTitle: String
        var key: String
        if let real = taggedAlbum {
            albumTitle = real
            key = real.lowercased() + "|" + albumArtist.lowercased()
            // без исполнителя альбома одноимённые альбомы из разных папок не склеиваем
            if editedAlbum == nil && albumArtist.isEmpty { key += "|" + folderKey }
        } else if let folder = albumFolder {
            albumTitle = folder
            key = folder.lowercased() + "||" + folderKey
        } else {
            switch fallback {
            case .single:
                albumTitle = title
                key = "s|" + title.lowercased() + "|" + artist.lowercased()
            case .artist:
                albumTitle = artist + " · Singles"
                key = "a|" + artist.lowercased()
            case .unknown:
                albumTitle = "Unknown Album"
                key = "u|"
            }
        }

        let number = edit?.number ?? (e.number > 0 ? e.number : parsed.number)
        let disc = edit?.disc ?? e.disc
        let year = edit?.year ?? e.year

        return Track(
            id: e.id,
            title: title,
            artist: artist,
            albumArtist: albumArtist,
            album: albumTitle,
            number: number,
            disc: disc,
            duration: e.duration,
            genre: e.genre,
            year: year,
            albumID: key
        )
    }

    // MARK: - Разбор имён

    private nonisolated static func nonEmpty(_ s: String?) -> String? {
        guard let s else { return nil }
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    private nonisolated static func isDiscFolder(_ name: String) -> Bool {
        let lower = name.lowercased().replacingOccurrences(of: " ", with: "")
        for prefix in ["cd", "disc", "disk"] where lower.hasPrefix(prefix) {
            let rest = lower.dropFirst(prefix.count)
            if !rest.isEmpty && rest.allSatisfy({ $0.isNumber }) { return true }
        }
        return false
    }

    /// "01 - Название", "01. Название", "01_Название", "01 Название" -> (1, "Название").
    /// "21 Guns" остаётся названием: без разделителя и без нуля впереди это не номер.
    private nonisolated static func parseFileName(_ base: String) -> (number: Int, title: String) {
        let digits = base.prefix(while: { $0.isNumber })
        guard !digits.isEmpty, digits.count <= 3, let n = Int(digits) else { return (0, base) }
        let after = base.dropFirst(digits.count)
        let separators = CharacterSet(charactersIn: ".-_)")
        let trimmed = after.trimmingCharacters(in: .whitespaces)
        guard let firstScalar = trimmed.unicodeScalars.first else { return (0, base) }
        let hasSeparator = separators.contains(firstScalar)
        let zeroPadded = digits.count == 2 && digits.hasPrefix("0")
        guard hasSeparator || zeroPadded else { return (0, base) }
        let title = String(after).trimmingCharacters(in: CharacterSet(charactersIn: " .-_)"))
        return title.isEmpty ? (0, base) : (n, title)
    }

    // MARK: - Диск

    private func saveCache() {
        let snapshot = entries
        let url = Persist.url("library.json")
        Task.detached(priority: .utility) {
            let file = CacheFile(version: Library.cacheVersion, entries: snapshot)
            if let data = try? JSONEncoder().encode(file) {
                try? data.write(to: url, options: .atomic)
            }
        }
    }

    private func saveEdits() {
        let snapshot = edits
        let url = Persist.url("edits.json")
        Task.detached(priority: .utility) {
            if let data = try? JSONEncoder().encode(snapshot) {
                try? data.write(to: url, options: .atomic)
            }
        }
    }

    // MARK: - Файлы

    private nonisolated static func listFiles(root: URL) -> [ScanFile] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else { return [] }

        let prefix = root.standardizedFileURL.path + "/"
        var out: [ScanFile] = []
        for case let url as URL in enumerator {
            guard audioExtensions.contains(url.pathExtension.lowercased()) else { continue }
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true else { continue }
            let full = url.standardizedFileURL.path
            guard full.hasPrefix(prefix) else { continue }
            let stamp = values.contentModificationDate?.timeIntervalSince1970 ?? 0
            out.append(ScanFile(
                url: url,
                id: String(full.dropFirst(prefix.count)),
                mtime: stamp,
                size: values.fileSize ?? 0
            ))
        }
        return out
    }

    /// Теги читаются параллельно, но не больше шести файлов одновременно.
    private nonisolated static func readAll(
        _ items: [ScanFile],
        progress: @escaping @Sendable (Int) -> Void
    ) async -> [CacheEntry] {
        if items.isEmpty { return [] }
        var out: [CacheEntry] = []
        out.reserveCapacity(items.count)

        await withTaskGroup(of: CacheEntry.self, returning: Void.self) { group in
            var next = 0
            var done = 0
            let width = min(6, items.count)
            while next < width {
                let file = items[next]
                group.addTask { await Library.readEntry(file) }
                next += 1
            }
            for await entry in group {
                out.append(entry)
                done += 1
                if done % 8 == 0 || done == items.count { progress(done) }
                if next < items.count {
                    let file = items[next]
                    group.addTask { await Library.readEntry(file) }
                    next += 1
                }
            }
        }
        return out
    }

    private nonisolated static func readEntry(_ f: ScanFile) async -> CacheEntry {
        var raw: RawTags
        if f.url.pathExtension.lowercased() == "flac", let parsed = FlacReader.read(f.url) {
            raw = parsed
            if raw.duration <= 0 {
                raw.duration = await AVTagReader.read(f.url).duration
            }
        } else {
            raw = await AVTagReader.read(f.url)
        }

        var cover: String?
        if let art = raw.artwork {
            cover = CoverDisk.store(art)
        }

        return CacheEntry(
            id: f.id,
            mtime: f.mtime,
            size: f.size,
            title: raw.title ?? "",
            artist: raw.artist ?? "",
            albumArtist: raw.albumArtist ?? "",
            album: raw.album ?? "",
            number: raw.number,
            disc: raw.disc,
            duration: raw.duration,
            genre: raw.genre ?? "",
            year: raw.year,
            cover: cover
        )
    }

    // MARK: - Обложки из папки

    /// cover.jpg / folder.png рядом с треками. Для файлов прямо в корне Documents не ищем:
    /// иначе одна картинка достанется всей плоской библиотеке.
    private nonisolated static func fillFolderArt(_ input: [CacheEntry], root: URL) -> [CacheEntry] {
        var memo: [String: String?] = [:]
        var out = input
        for i in out.indices where out[i].cover == nil {
            let dir = (out[i].id as NSString).deletingLastPathComponent
            if dir.isEmpty { continue }
            if let hit = memo[dir] {
                out[i].cover = hit
                continue
            }
            var key = folderArtKey(root.appendingPathComponent(dir, isDirectory: true))
            if key == nil && isDiscFolder((dir as NSString).lastPathComponent) {
                let parent = (dir as NSString).deletingLastPathComponent
                if !parent.isEmpty {
                    key = folderArtKey(root.appendingPathComponent(parent, isDirectory: true))
                }
            }
            memo.updateValue(key, forKey: dir)
            out[i].cover = key
        }
        return out
    }

    private nonisolated static func folderArtKey(_ dir: URL) -> String? {
        let names: [String] = ["cover", "folder", "front", "album", "albumart", "artwork"]
        let exts: Set<String> = ["jpg", "jpeg", "png"]
        guard let items = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            return nil
        }
        var best: (rank: Int, url: URL)?
        for url in items where exts.contains(url.pathExtension.lowercased()) {
            let base = url.deletingPathExtension().lastPathComponent.lowercased()
            guard let rank = names.firstIndex(of: base) else { continue }
            if best == nil || rank < best!.rank { best = (rank, url) }
        }
        guard let found = best else { return nil }
        return CoverDisk.storeFile(found.url)
    }
}
