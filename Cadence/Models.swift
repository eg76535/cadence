import Foundation

struct Track: Identifiable, Hashable {
    let id: String          // путь относительно Documents
    let url: URL
    let title: String
    let artist: String
    let album: String
    let number: Int         // 0 = номер не найден
    let duration: TimeInterval

    var albumID: String { album.lowercased() }
    var sortNumber: Int { number == 0 ? 9999 : number }
}

struct Album: Identifiable, Hashable {
    let id: String          // = Track.albumID
    let title: String
    let artist: String
    let tracks: [Track]

    var duration: TimeInterval { tracks.reduce(0) { $0 + $1.duration } }
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
