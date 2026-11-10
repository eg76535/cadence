import Foundation
import AVFoundation

/// Сырые теги, как они лежат в файле (без догадок по папкам).
struct RawTags {
    var title: String?
    var artist: String?
    var albumArtist: String?
    var album: String?
    var number = 0
    var disc = 0
    var year = 0
    var genre: String?
    var duration: TimeInterval = 0
    var artwork: Data?
}

// MARK: - FLAC

/// AVFoundation на iOS не отдаёт теги и обложки из FLAC, поэтому читаем заголовок сами:
/// блоки STREAMINFO (длительность), VORBIS_COMMENT (теги) и PICTURE (обложка).
enum FlacReader {
    static func read(_ url: URL) -> RawTags? {
        guard let fh = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? fh.close() }

        // иногда перед fLaC лежит ID3v2-заголовок
        guard let first = try? fh.read(upToCount: 4), first.count == 4 else { return nil }
        var magic = [UInt8](first)
        if magic[0] == 0x49, magic[1] == 0x44, magic[2] == 0x33 {         // "ID3"
            guard let rest = try? fh.read(upToCount: 6), rest.count == 6 else { return nil }
            let r = [UInt8](rest)
            var size = 0
            for i in 2..<6 { size = (size << 7) | Int(r[i] & 0x7F) }
            guard (try? fh.seek(toOffset: UInt64(10 + size))) != nil,
                  let again = try? fh.read(upToCount: 4), again.count == 4 else { return nil }
            magic = [UInt8](again)
        }
        guard magic == [0x66, 0x4C, 0x61, 0x43] else { return nil }        // "fLaC"

        var tags = RawTags()
        var bestPicture: (type: Int, data: Data)?
        var isLast = false
        var blocks = 0

        while !isLast && blocks < 64 {
            blocks += 1
            guard let headData = try? fh.read(upToCount: 4), headData.count == 4 else { break }
            let head = [UInt8](headData)
            isLast = (head[0] & 0x80) != 0
            let type = Int(head[0] & 0x7F)
            var length = 0
            for i in 1..<4 { length = (length << 8) | Int(head[i]) }

            switch type {
            case 0, 4, 6:
                guard length < 32_000_000,
                      let bodyData = try? fh.read(upToCount: length), bodyData.count == length else {
                    isLast = true
                    continue
                }
                let body = [UInt8](bodyData)
                if type == 0 {
                    parseStreamInfo(body, into: &tags)
                } else if type == 4 {
                    parseVorbis(body, into: &tags)
                } else if let pic = parsePicture(body) {
                    if bestPicture == nil || (pic.type == 3 && bestPicture?.type != 3) {
                        bestPicture = pic
                    }
                }
            default:
                guard let pos = try? fh.offset(),
                      (try? fh.seek(toOffset: pos + UInt64(length))) != nil else {
                    isLast = true
                    continue
                }
            }
        }
        tags.artwork = bestPicture?.data
        return tags
    }

    // MARK: блоки

    private static func parseStreamInfo(_ b: [UInt8], into t: inout RawTags) {
        guard b.count >= 18 else { return }
        var sampleRate = 0
        for i in 10..<13 { sampleRate = (sampleRate << 8) | Int(b[i]) }
        sampleRate >>= 4                                  // 20 бит из 24
        var total = Int(b[13] & 0x0F)                     // 36 бит: 4 + 4 байта
        for i in 14..<18 { total = (total << 8) | Int(b[i]) }
        if sampleRate > 0 && total > 0 {
            t.duration = Double(total) / Double(sampleRate)
        }
    }

    private static func parseVorbis(_ b: [UInt8], into t: inout RawTags) {
        var o = 0
        guard let vendor = le32(b, o) else { return }
        o += 4 + vendor
        guard let count = le32(b, o) else { return }
        o += 4
        for _ in 0..<min(count, 512) {
            guard let len = le32(b, o) else { return }
            o += 4
            guard len >= 0, o + len <= b.count else { return }
            let text = String(decoding: b[o..<(o + len)], as: UTF8.self)
            o += len
            guard let eq = text.firstIndex(of: "=") else { continue }
            let key = text[..<eq].uppercased()
            let value = String(text[text.index(after: eq)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if value.isEmpty { continue }
            switch key {
            case "TITLE": if t.title == nil { t.title = value }
            case "ARTIST": if t.artist == nil { t.artist = value }
            case "ALBUM": if t.album == nil { t.album = value }
            case "ALBUMARTIST", "ALBUM ARTIST", "BAND": if t.albumArtist == nil { t.albumArtist = value }
            case "TRACKNUMBER", "TRACK": if t.number == 0 { t.number = leadingInt(value) }
            case "DISCNUMBER", "DISC": if t.disc == 0 { t.disc = leadingInt(value) }
            case "DATE", "YEAR", "ORIGINALDATE": if t.year == 0 { t.year = leadingInt(String(value.prefix(4))) }
            case "GENRE": if t.genre == nil { t.genre = value }
            default: break
            }
        }
    }

    private static func parsePicture(_ b: [UInt8]) -> (type: Int, data: Data)? {
        var o = 0
        guard let type = be32(b, o) else { return nil }
        o += 4
        guard let mimeLen = be32(b, o) else { return nil }
        o += 4 + mimeLen
        guard let descLen = be32(b, o) else { return nil }
        o += 4 + descLen + 16                       // ширина, высота, глубина, число цветов
        guard let dataLen = be32(b, o) else { return nil }
        o += 4
        guard dataLen > 0, o + dataLen <= b.count else { return nil }
        return (type, Data(b[o..<(o + dataLen)]))
    }

    // MARK: байты

    private static func le32(_ b: [UInt8], _ o: Int) -> Int? {
        guard o >= 0, o + 4 <= b.count else { return nil }
        var v = 0
        for i in 0..<4 { v |= Int(b[o + i]) << (8 * i) }
        return v
    }

    private static func be32(_ b: [UInt8], _ o: Int) -> Int? {
        guard o >= 0, o + 4 <= b.count else { return nil }
        var v = 0
        for i in 0..<4 { v = (v << 8) | Int(b[o + i]) }
        return v
    }

    private static func leadingInt(_ s: String) -> Int {
        let digits = s.trimmingCharacters(in: .whitespaces).prefix(while: { $0.isNumber })
        return Int(digits) ?? 0
    }
}

// MARK: - Всё остальное (MP3, M4A, AAC, WAV, AIFF, ALAC) через AVFoundation

enum AVTagReader {
    static func read(_ url: URL) async -> RawTags {
        let asset = AVURLAsset(url: url)
        var t = RawTags()

        if let d = try? await asset.load(.duration).seconds, d.isFinite, d > 0 {
            t.duration = d
        }

        let common = (try? await asset.load(.commonMetadata)) ?? []
        t.title = await text(common, .commonIdentifierTitle)
        t.artist = await text(common, .commonIdentifierArtist)
        t.album = await text(common, .commonIdentifierAlbumName)
        t.genre = await text(common, .commonIdentifierType)
        if let y = await text(common, .commonIdentifierCreationDate) {
            t.year = Int(y.prefix(4)) ?? 0
        }
        if let art = AVMetadataItem.metadataItems(from: common, filteredByIdentifier: .commonIdentifierArtwork).first {
            t.artwork = try? await art.load(.dataValue)
        }

        // то, чего нет в общих тегах: исполнитель альбома, номер трека и диска
        let all = (try? await asset.load(.metadata)) ?? []
        for item in all {
            let id = item.identifier?.rawValue ?? ""
            switch id {
            case "id3/TPE2", "itsk/aART":
                if t.albumArtist == nil { t.albumArtist = clean(try? await item.load(.stringValue)) }
            case "id3/TRCK":
                if t.number == 0 { t.number = leadingInt(try? await item.load(.stringValue)) }
            case "id3/TPOS":
                if t.disc == 0 { t.disc = leadingInt(try? await item.load(.stringValue)) }
            case "itsk/trkn":
                if t.number == 0, let d = try? await item.load(.dataValue) {
                    let b = [UInt8](d)
                    if b.count >= 4 { t.number = (Int(b[2]) << 8) + Int(b[3]) }
                }
            case "itsk/disk":
                if t.disc == 0, let d = try? await item.load(.dataValue) {
                    let b = [UInt8](d)
                    if b.count >= 4 { t.disc = (Int(b[2]) << 8) + Int(b[3]) }
                }
            default:
                break
            }
        }
        return t
    }

    private static func text(_ items: [AVMetadataItem], _ id: AVMetadataIdentifier) async -> String? {
        guard let item = AVMetadataItem.metadataItems(from: items, filteredByIdentifier: id).first else { return nil }
        return clean(try? await item.load(.stringValue))
    }

    private static func clean(_ s: String?) -> String? {
        guard let s else { return nil }
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func leadingInt(_ s: String?) -> Int {
        guard let s else { return 0 }
        let digits = s.trimmingCharacters(in: .whitespaces).prefix(while: { $0.isNumber })
        return Int(digits) ?? 0
    }
}
