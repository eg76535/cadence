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

    /// Шрифты из темы (JetBrains/Plex/Space Mono) пока не вшиты в приложение,
    /// поэтому везде системный моноширинный.
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
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
