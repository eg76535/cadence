import SwiftUI

enum WallKind: String { case solid, gradient, aurora, cover }
enum TabsPos: String { case bar, dock, top }
enum MiniStyle: String { case bar, float }
enum FlowAlign: String { case center, top, low }
enum FontKind: String { case sys, jb, plex, space }

/// Тема оформления. Те же поля, что в JSON из дизайн-стенда (HTML).
/// Любое поле можно не указывать: подставится значение по умолчанию (стиль Rockbox).
struct ThemeSpec: Equatable {
    var name = "Rockbox"
    var bg = "#000000"
    var fg = "#ffffff"
    var dim = "#8c8c8c"
    var accent = "#ff5c33"

    var wall = WallKind.solid
    var wA = "#0e7c86"
    var wB = "#1b4f7a"
    var wC = "#6fd3c9"
    var wAngle = 160.0
    var wBlur = 40.0
    var wDim = 0.35
    var waves = 0.0
    var waveCol = "#9be7e0"

    var glass = false
    var gBlur = 22.0
    var gTint = 0.12
    var gBorder = 0.25
    var gSat = 1.6

    var font = FontKind.sys
    var radius = 0.0
    var uiR = 18.0

    var tabs = TabsPos.bar
    var mini = MiniStyle.bar
    var align = FlowAlign.center
    var hdr = true

    var angle = 62.0
    var flip = false
    var spread = 0.42
    var sideScale = 0.82
    var overlap = 0.62
    var cover = 0.56
    var refl = 0.35
    var persp = 900.0

    var coverL = 1.0
    var spreadL = 0.5
    var overlapL = 0.66

    var isLight: Bool { ThemeSpec.luminance(bg) > 0.45 }

    // MARK: parsing

    static func parse(_ data: Data) -> ThemeSpec? {
        guard let any = try? JSONSerialization.jsonObject(with: data),
              let o = any as? [String: Any] else { return nil }
        var t = ThemeSpec()
        let d = ThemeSpec()
        t.name = text(o["name"], d.name)
        t.bg = color(o["bg"], d.bg)
        t.fg = color(o["fg"], d.fg)
        t.dim = color(o["dim"], d.dim)
        t.accent = color(o["accent"], d.accent)
        t.wall = pick(o["wall"], d.wall)
        t.wA = color(o["wA"], d.wA)
        t.wB = color(o["wB"], d.wB)
        t.wC = color(o["wC"], d.wC)
        t.wAngle = num(o["wAngle"], d.wAngle, 0, 360)
        t.wBlur = num(o["wBlur"], d.wBlur, 0, 80)
        t.wDim = num(o["wDim"], d.wDim, 0, 0.85)
        t.waves = num(o["waves"], d.waves, 0, 1)
        t.waveCol = color(o["waveCol"], d.waveCol)
        t.glass = flag(o["glass"], d.glass)
        t.gBlur = num(o["gBlur"], d.gBlur, 0, 40)
        t.gTint = num(o["gTint"], d.gTint, 0, 0.4)
        t.gBorder = num(o["gBorder"], d.gBorder, 0, 0.6)
        t.gSat = num(o["gSat"], d.gSat, 1, 2.4)
        t.font = pick(o["font"], d.font)
        t.radius = num(o["radius"], d.radius, 0, 24)
        t.uiR = num(o["uiR"], d.uiR, 0, 32)
        t.tabs = pick(o["tabs"], d.tabs)
        t.mini = pick(o["mini"], d.mini)
        t.align = pick(o["align"], d.align)
        t.hdr = flag(o["hdr"], d.hdr)
        t.angle = num(o["angle"], d.angle, 20, 85)
        t.flip = flag(o["flip"], d.flip)
        t.spread = num(o["spread"], d.spread, 0, 0.8)
        t.sideScale = num(o["sideScale"], d.sideScale, 0.6, 1)
        t.overlap = num(o["overlap"], d.overlap, 0.3, 0.8)
        t.cover = num(o["cover"], d.cover, 0.4, 0.7)
        t.refl = num(o["refl"], d.refl, 0, 0.6)
        t.persp = num(o["persp"], d.persp, 300, 1600)
        t.coverL = num(o["coverL"], d.coverL, 0.5, 1.2)
        t.spreadL = num(o["spreadL"], d.spreadL, 0, 0.8)
        t.overlapL = num(o["overlapL"], d.overlapL, 0.3, 0.8)
        return t
    }

    private static func text(_ v: Any?, _ d: String) -> String {
        guard let s = v as? String else { return d }
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? d : String(trimmed.prefix(40))
    }

    private static func color(_ v: Any?, _ d: String) -> String {
        guard let s = v as? String, let h = normalizedHex(s) else { return d }
        return h
    }

    private static func num(_ v: Any?, _ d: Double, _ lo: Double, _ hi: Double) -> Double {
        if let n = v as? Double { return min(max(n, lo), hi) }
        if let s = v as? String, let n = Double(s) { return min(max(n, lo), hi) }
        return d
    }

    private static func flag(_ v: Any?, _ d: Bool) -> Bool {
        if let b = v as? Bool { return b }
        return d
    }

    private static func pick<E: RawRepresentable>(_ v: Any?, _ d: E) -> E where E.RawValue == String {
        if let s = v as? String, let e = E(rawValue: s) { return e }
        return d
    }

    // MARK: colors

    static func normalizedHex(_ s: String) -> String? {
        var h = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if h.hasPrefix("#") { h.removeFirst() }
        let hexDigits = Set("0123456789abcdef")
        guard h.allSatisfy({ hexDigits.contains($0) }) else { return nil }
        if h.count == 3 { h = h.map { "\($0)\($0)" }.joined() }
        return h.count == 6 ? "#" + h : nil
    }

    static func rgb(_ hex: String) -> (r: Double, g: Double, b: Double) {
        var n: UInt64 = 0
        _ = Scanner(string: String(hex.dropFirst())).scanHexInt64(&n)
        return (Double((n >> 16) & 255) / 255, Double((n >> 8) & 255) / 255, Double(n & 255) / 255)
    }

    static func luminance(_ hex: String) -> Double {
        let c = rgb(hex)
        func lin(_ v: Double) -> Double { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b)
    }
}

extension Color {
    init(hex: String) {
        let c = ThemeSpec.rgb(hex)
        self.init(red: c.r, green: c.g, blue: c.b)
    }

    /// Смесь двух hex-цветов, t = 0 даёт a, t = 1 даёт b
    static func blend(_ a: String, _ b: String, _ t: Double) -> Color {
        let x = ThemeSpec.rgb(a), y = ThemeSpec.rgb(b)
        return Color(red: x.r + (y.r - x.r) * t, green: x.g + (y.g - x.g) * t, blue: x.b + (y.b - x.b) * t)
    }
}

/// Встроенные темы, те же, что в дизайн-стенде.
enum BuiltinThemes {
    static let all: [(id: String, json: String)] = [
        ("builtin:rockbox", #"{"name":"Rockbox"}"#),
        ("builtin:seaglass", """
        {"name":"Sea Glass","bg":"#031a22","fg":"#f1fbfb","dim":"#9cc3c7","accent":"#7ff0e4",
         "wall":"aurora","wA":"#0c8a94","wB":"#16447a","wC":"#2a9d9a","wDim":0.3,"waves":0.38,"waveCol":"#86e0d8",
         "glass":true,"gBlur":24,"gTint":0.11,"gBorder":0.3,"gSat":1.7,"radius":14,"uiR":24,
         "tabs":"dock","mini":"float","align":"center","angle":58,"spread":0.46,"overlap":0.6}
        """),
        ("builtin:paper", """
        {"name":"Paper Light","bg":"#f2f0ea","fg":"#16161a","dim":"#6c6a63","accent":"#d4472a","wall":"solid",
         "radius":2,"font":"plex","tabs":"bar","mini":"bar","angle":55,"refl":0.2}
        """),
        ("builtin:coverglow", """
        {"name":"Cover Glow","bg":"#08080b","fg":"#ffffff","dim":"#b4b4bc","accent":"#ffffff",
         "wall":"cover","wBlur":50,"wDim":0.62,"glass":true,"gBlur":28,"gTint":0.1,"gBorder":0.26,
         "radius":10,"uiR":22,"tabs":"dock","mini":"float","hdr":false,"align":"low"}
        """)
    ]
}
