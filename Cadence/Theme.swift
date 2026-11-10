import UIKit
import SwiftUI

/// Вся эстетика в одном месте. Значения берутся из активной темы (ThemeStore),
/// поэтому экраны перерисовываются сами, когда тема меняется.
enum Theme {
    private static var spec: ThemeSpec { ThemeStore.shared.spec }

    static var bg: Color { Color(hex: spec.bg) }
    static var fg: Color { Color(hex: spec.fg) }
    static var dim: Color { Color(hex: spec.dim) }
    static var accent: Color { Color(hex: spec.accent) }
    static var line: Color { Color.blend(spec.bg, spec.fg, spec.glass ? 0.24 : 0.16) }
    static var coverRadius: CGFloat { CGFloat(spec.radius) }

    static var modern: Bool { spec.modern }
    static var isLight: Bool { spec.isLight }

    /// Фон карточек и плашек: чуть светлее (тёмная тема) или темнее (светлая) основного фона.
    static var card: Color { Color.blend(spec.bg, spec.fg, spec.isLight ? 0.06 : 0.10) }
    static var cardStrong: Color { Color.blend(spec.bg, spec.fg, spec.isLight ? 0.11 : 0.17) }

    /// Скругление карточек и кнопок в modern-теме.
    static var cardRadius: CGFloat { CGFloat(max(spec.uiR * 0.7, 8)) }

    /// Шрифт темы. sf/rounded/serif дают системные шрифты, остальные (sys, jb, plex, space)
    /// пока без вшитых файлов и рисуются системным моноширинным.
    static func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        switch spec.font {
        case .sf: return .system(size: size, weight: weight, design: .default)
        case .rounded: return .system(size: size, weight: weight, design: .rounded)
        case .serif: return .system(size: size, weight: weight, design: .serif)
        default: return .system(size: size, weight: weight, design: .monospaced)
        }
    }

    /// Старое имя, под ним шрифты вызываются по всему приложению.
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        font(size, weight)
    }
}

func formatTime(_ t: TimeInterval) -> String {
    guard t.isFinite, t >= 0 else { return "0:00" }
    let s = Int(t)
    return String(format: "%d:%02d", s / 60, s % 60)
}

extension UIImage {
    func downscaled(maxSide: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maxSide else { return self }
        let k = maxSide / longest
        let newSize = CGSize(width: size.width * k, height: size.height * k)
        return UIGraphicsImageRenderer(size: newSize).image { _ in
            self.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}

extension UIImage {
    /// Средний цвет картинки (для подсветки фона под обложку).
    var averageColor: UIColor? {
        guard let cg = cgImage else { return nil }
        var pixel: [UInt8] = [0, 0, 0, 0]
        let space = CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        let made: Bool = pixel.withUnsafeMutableBytes { raw in
            guard let ctx = CGContext(
                data: raw.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
                bytesPerRow: 4, space: space, bitmapInfo: info
            ) else { return false }
            ctx.interpolationQuality = .medium
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        guard made else { return nil }
        return UIColor(
            red: CGFloat(pixel[0]) / 255,
            green: CGFloat(pixel[1]) / 255,
            blue: CGFloat(pixel[2]) / 255,
            alpha: 1
        )
    }
}

enum Haptics {
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func soft() { UIImpactFeedbackGenerator(style: .soft).impactOccurred() }
    static func select() { UISelectionFeedbackGenerator().selectionChanged() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
}
