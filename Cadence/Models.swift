import Foundation

struct Track: Identifiable, Hashable, Codable {
    let id: String          // путь относительно Documents
    var title: String
    var artist: String
    var albumArtist: String // "" = нет
    var album: String
    var number: Int         // 0 = номер не найден
    var disc: Int
    var duration: TimeInterval
    var genre: String = ""
    var year: Int = 0
    /// Ключ альбома. Считает Library: папка + название, чтобы одноимённые альбомы
    /// разных исполнителей не склеивались, а сборники из одной папки не разваливались.
    var albumID: String = ""

    /// Путь собирается заново при каждом запуске: контейнер приложения может переехать
    /// после переустановки, поэтому в кеше хранится только относительный id.
    var url: URL { Library.documentsURL.appendingPathComponent(id) }

    var artistID: String { artist.lowercased() }
    var sortNumber: Int { number == 0 ? 9999 : number }
}

struct Album: Identifiable, Hashable {
    let id: String          // = Track.albumID
    let title: String
    let artist: String
    let year: Int
    let tracks: [Track]

    var duration: TimeInterval { tracks.reduce(0) { $0 + $1.duration } }
}

/// Ручная правка тегов. Хранится отдельно от кеша, поэтому переживает пересканирование.
struct TrackEdit: Codable, Equatable {
    var title: String?
    var artist: String?
    var albumArtist: String?
    var album: String?
    var number: Int?
    var disc: Int?
    var year: Int?

    var isEmpty: Bool {
        title == nil && artist == nil && albumArtist == nil && album == nil
            && number == nil && disc == nil && year == nil
    }
}

enum RepeatMode {
    case off, all, one

    var next: RepeatMode {
        switch self {
        case .off: return .all
        case .all: return .one
        case .one: return .off
        }
    }
}
