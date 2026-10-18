import UIKit
import AVFoundation
import SwiftUI

/// Сканирует Documents, читает теги и обложки, группирует по альбомам.
@MainActor @Observable
final class Library {
    private(set) var albums: [Album] = []
    private(set) var tracks: [Track] = []
    private(set) var covers: [String: UIImage] = [:]
    private(set) var isScanning = false

    private struct CachedEntry {
        let date: Date
        let track: Track
        let cover: UIImage?
    }

    private struct FileInfo {
        let url: URL
        let date: Date
    }

    @ObservationIgnored private var cache: [String: CachedEntry] = [:]

    nonisolated static let audioExtensions: Set<String> = [
        "mp3", "m4a", "aac", "flac", "wav", "aif", "aiff", "caf", "alac"
    ]

    nonisolated static var documentsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    func rescan() async {
        guard !isScanning else { return }
        isScanning = true
        defer { isScanning = false }

        let root = Self.documentsURL
        let files = Self.audioFiles(in: root)

        var result: [(Track, UIImage?)] = []
        var newCache: [String: CachedEntry] = [:]

        for file in files {
            let key = file.url.path
            if let hit = cache[key], hit.date == file.date {
                newCache[key] = hit
                result.append((hit.track, hit.cover))
                continue
            }
            if let read = await Self.readTrack(url: file.url, root: root) {
                newCache[key] = CachedEntry(date: file.date, track: read.0, cover: read.1)
                result.append(read)
            }
        }

        cache = newCache
        let grouped = Self.group(result)
        albums = grouped.albums
        covers = grouped.covers
        tracks = result.map { $0.0 }.sorted { $0.title.lowercased() < $1.title.lowercased() }
    }

    // MARK: - Файлы

    private nonisolated static func audioFiles(in root: URL) -> [FileInfo] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .contentModificationDateKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var out: [FileInfo] = []
        for case let url as URL in enumerator {
            guard audioExtensions.contains(url.pathExtension.lowercased()) else { continue }
            let values = try? url.resourceValues(forKeys: Set(keys))
            guard values?.isRegularFile == true else { continue }
            out.append(FileInfo(url: url, date: values?.contentModificationDate ?? .distantPast))
        }
        return out
    }

    // MARK: - Теги

    private nonisolated static func readTrack(url: URL, root: URL) async -> (Track, UIImage?)? {
        let asset = AVURLAsset(url: url)
        let meta = (try? await asset.load(.commonMetadata)) ?? []
        let duration = (try? await asset.load(.duration))?.seconds ?? 0

        func string(_ id: AVMetadataIdentifier) async -> String? {
            guard let item = AVMetadataItem.metadataItems(from: meta, filteredByIdentifier: id).first else {
                return nil
            }
            let value = try? await item.load(.stringValue)
            guard let s = value?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else {
                return nil
            }
            return s
        }

        // Имя файла: "01 - Название" -> номер 1, название "Название"
        let base = url.deletingPathExtension().lastPathComponent
        var number = 0
        var cleaned = base
        let digits = base.prefix(while: { $0.isNumber })
        if !digits.isEmpty, digits.count <= 3, let n = Int(digits) {
            number = n
            cleaned = String(base.dropFirst(digits.count))
                .trimmingCharacters(in: CharacterSet(charactersIn: " .-_)"))
        }
        if cleaned.isEmpty { cleaned = base }

        let parent = url.deletingLastPathComponent()
        let folderName = parent.standardizedFileURL.path == root.standardizedFileURL.path
            ? nil
            : parent.lastPathComponent

        let title = await string(.commonIdentifierTitle) ?? cleaned
        let artist = await string(.commonIdentifierArtist) ?? "Unknown Artist"
        let album = await string(.commonIdentifierAlbumName) ?? folderName ?? "Unknown Album"

        var cover: UIImage?
        if let artItem = AVMetadataItem.metadataItems(
            from: meta, filteredByIdentifier: .commonIdentifierArtwork
        ).first,
            let data = try? await artItem.load(.dataValue),
            let img = UIImage(data: data) {
            cover = img.downscaled(maxSide: 700)
        }
        if cover == nil {
            cover = folderArt(in: parent)
        }

        let relative = url.path.replacingOccurrences(of: root.path + "/", with: "")
        let track = Track(
            id: relative,
            url: url,
            title: title,
            artist: artist,
            album: album,
            number: number,
            duration: duration.isFinite ? duration : 0
        )
        return (track, cover)
    }

    /// cover.jpg / folder.png и т.п. рядом с файлом (FLAC часто без встроенной обложки)
    private nonisolated static func folderArt(in dir: URL) -> UIImage? {
        let names: Set<String> = ["cover", "folder", "front", "album"]
        let exts: Set<String> = ["jpg", "jpeg", "png"]
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil
        ) else { return nil }
        for url in items {
            let base = url.deletingPathExtension().lastPathComponent.lowercased()
            guard names.contains(base), exts.contains(url.pathExtension.lowercased()) else { continue }
            if let data = try? Data(contentsOf: url), let img = UIImage(data: data) {
                return img.downscaled(maxSide: 700)
            }
        }
        return nil
    }

    // MARK: - Группировка

    private nonisolated static func group(
        _ items: [(Track, UIImage?)]
    ) -> (albums: [Album], covers: [String: UIImage]) {
        var buckets: [String: [Track]] = [:]
        var covers: [String: UIImage] = [:]

        for (track, cover) in items {
            buckets[track.albumID, default: []].append(track)
            if covers[track.albumID] == nil, let cover {
                covers[track.albumID] = cover
            }
        }

        var albums: [Album] = buckets.map { id, tracks in
            let sorted = tracks.sorted {
                ($0.sortNumber, $0.title.lowercased()) < ($1.sortNumber, $1.title.lowercased())
            }
            let artists = Set(sorted.map { $0.artist })
            return Album(
                id: id,
                title: sorted[0].album,
                artist: artists.count == 1 ? sorted[0].artist : "Various Artists",
                tracks: sorted
            )
        }
        albums.sort {
            ($0.artist.lowercased(), $0.title.lowercased()) < ($1.artist.lowercased(), $1.title.lowercased())
        }
        return (albums, covers)
    }
}
