import UIKit
import ImageIO
import CryptoKit
import Observation

/// Обложки лежат на диске как небольшие JPEG (до 800 px) в Application Support/Cadence/covers.
/// В память они попадают лениво и в нужном размере, поэтому тысячи альбомов не раздувают приложение.
enum CoverDisk {
    static let storeSide = 800

    static let dir: URL = {
        let d = Persist.url("covers")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    static func fileURL(_ key: String) -> URL {
        dir.appendingPathComponent(key + ".jpg")
    }

    /// Сохраняет картинку любого размера как JPEG не больше 800 px. Ключ = sha1 исходных данных,
    /// поэтому одинаковая обложка у всех треков альбома хранится один раз.
    static func store(_ data: Data) -> String? {
        let key = sha1(data)
        let url = fileURL(key)
        if FileManager.default.fileExists(atPath: url.path) { return key }
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let cg = thumbnail(src, maxSide: storeSide),
              let jpeg = UIImage(cgImage: cg).jpegData(compressionQuality: 0.86) else { return nil }
        do {
            try jpeg.write(to: url, options: .atomic)
        } catch {
            return nil
        }
        return key
    }

    static func storeFile(_ url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return store(data)
    }

    /// Читает с диска уменьшенную копию (уже декодированную, чтобы не тормозить прокрутку).
    static func load(_ key: String, maxSide: Int) -> UIImage? {
        guard let src = CGImageSourceCreateWithURL(fileURL(key) as CFURL, nil),
              let cg = thumbnail(src, maxSide: maxSide) else { return nil }
        return UIImage(cgImage: cg)
    }

    /// Удаляет обложки, которые больше никому не нужны.
    static func prune(keeping used: Set<String>) {
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        for url in files where url.pathExtension == "jpg" {
            let key = url.deletingPathExtension().lastPathComponent
            if !used.contains(key) { try? FileManager.default.removeItem(at: url) }
        }
    }

    // MARK: - внутреннее

    static func sha1(_ data: Data) -> String {
        Insecure.SHA1.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func thumbnail(_ src: CGImageSource, maxSide: Int) -> CGImage? {
        // ImageIO умеет увеличивать маленькие картинки до maxSide: этого не хотим
        var side = maxSide
        if let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
           let w = props[kCGImagePropertyPixelWidth] as? Int,
           let h = props[kCGImagePropertyPixelHeight] as? Int {
            side = min(maxSide, max(w, h))
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: side
        ]
        return CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary)
    }
}

enum CoverSize {
    case full, mid, thumb

    var pixels: Int {
        switch self {
        case .full: return CoverDisk.storeSide
        case .mid: return 420
        case .thumb: return 160
        }
    }
}

/// Доступ к обложкам по ключу альбома: `library.covers[album.id]` (полный размер),
/// `cached(_:_:)` и `load(_:_:)` для сеток и списков (без блокировки главного потока).
@MainActor @Observable
final class CoverStore {
    /// Растёт, когда набор обложек меняется: вьюхи, которые читают обложки, перерисовываются.
    private(set) var revision = 0

    @ObservationIgnored private var keys: [String: String] = [:]
    @ObservationIgnored private let big = NSCache<NSString, UIImage>()
    @ObservationIgnored private let medium = NSCache<NSString, UIImage>()
    @ObservationIgnored private let small = NSCache<NSString, UIImage>()

    init() {
        big.totalCostLimit = 80_000_000
        medium.totalCostLimit = 60_000_000
        small.totalCostLimit = 20_000_000
    }

    func setKeys(_ new: [String: String]) {
        keys = new
        revision += 1
    }

    func hasCover(_ albumID: String) -> Bool { keys[albumID] != nil }

    /// Ключ файла обложки (для сравнения: сменилась ли картинка).
    func key(_ albumID: String) -> String? { keys[albumID] }

    /// Синхронно, полный размер. Для Now Playing, фона и одиночных мест.
    subscript(_ albumID: String) -> UIImage? {
        _ = revision
        guard let key = keys[albumID] else { return nil }
        if let hit = big.object(forKey: key as NSString) { return hit }
        guard let img = CoverDisk.load(key, maxSide: CoverSize.full.pixels) else { return nil }
        big.setObject(img, forKey: key as NSString, cost: Self.cost(img))
        return img
    }

    /// Только из памяти, ничего не читает с диска.
    func cached(_ albumID: String, _ size: CoverSize) -> UIImage? {
        _ = revision
        guard let key = keys[albumID] else { return nil }
        return cache(size).object(forKey: key as NSString)
    }

    /// Читает с диска вне главного потока и кладёт в кеш.
    func load(_ albumID: String, _ size: CoverSize) async -> UIImage? {
        guard let key = keys[albumID] else { return nil }
        if let hit = cache(size).object(forKey: key as NSString) { return hit }
        let px = size.pixels
        let img: UIImage? = await Task.detached(priority: .userInitiated) {
            CoverDisk.load(key, maxSide: px)
        }.value
        if let img {
            cache(size).setObject(img, forKey: key as NSString, cost: Self.cost(img))
        }
        return img
    }

    private func cache(_ size: CoverSize) -> NSCache<NSString, UIImage> {
        switch size {
        case .full: return big
        case .mid: return medium
        case .thumb: return small
        }
    }

    private static func cost(_ img: UIImage) -> Int {
        Int(img.size.width * img.size.height * img.scale * img.scale * 4)
    }
}
