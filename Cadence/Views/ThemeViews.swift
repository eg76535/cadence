import SwiftUI

/// Фон экрана по теме: плоский, градиент, aurora, размытая обложка, плюс волны.
struct WallView: View {
    var cover: UIImage?
    private let store = ThemeStore.shared

    var body: some View {
        let s = store.spec
        ZStack {
            Color(hex: s.bg)
            switch s.wall {
            case .solid:
                EmptyView()
            case .gradient:
                LinearGradient(
                    gradient: Gradient(stops: [
                        .init(color: Color(hex: s.wA), location: 0),
                        .init(color: Color(hex: s.wB), location: 0.55),
                        .init(color: Color(hex: s.wC), location: 1)
                    ]),
                    startPoint: Self.start(s.wAngle),
                    endPoint: Self.end(s.wAngle)
                )
            case .aurora:
                GeometryReader { geo in
                    let r = max(geo.size.width, geo.size.height)
                    ZStack {
                        blob(Color(hex: s.wA), 0.95, UnitPoint(x: 0.16, y: 0.10), r * 0.55)
                        blob(Color(hex: s.wB), 0.90, UnitPoint(x: 0.88, y: 0.34), r * 0.50)
                        blob(Color(hex: s.wC), 0.85, UnitPoint(x: 0.46, y: 1.02), r * 0.60)
                    }
                }
            case .cover:
                GeometryReader { geo in
                    if let cover {
                        Image(uiImage: cover)
                            .resizable()
                            .scaledToFill()
                            .frame(width: geo.size.width, height: geo.size.height)
                            .scaleEffect(1.25)
                            .blur(radius: s.wBlur)
                            .saturation(1.35)
                            .clipped()
                    }
                }
            }
            if s.wall != .solid {
                Color(hex: s.bg).opacity(s.wDim)
            }
            if s.waves > 0.001 {
                WavesView(color: Color(hex: s.waveCol), opacity: s.waves)
            }
        }
        .animation(.easeInOut(duration: 0.4), value: s)
        .allowsHitTesting(false)
    }

    private func blob(_ c: Color, _ a: Double, _ center: UnitPoint, _ radius: CGFloat) -> some View {
        RadialGradient(colors: [c.opacity(a), c.opacity(0)], center: center, startRadius: 0, endRadius: radius)
    }

    // угол как в CSS: 0 = снизу вверх, по часовой
    private static func start(_ deg: Double) -> UnitPoint {
        let r = deg * Double.pi / 180
        return UnitPoint(x: 0.5 - sin(r) / 2, y: 0.5 + cos(r) / 2)
    }
    private static func end(_ deg: Double) -> UnitPoint {
        let r = deg * Double.pi / 180
        return UnitPoint(x: 0.5 + sin(r) / 2, y: 0.5 - cos(r) / 2)
    }
}

/// Медленные морские волны внизу экрана.
struct WavesView: View {
    let color: Color
    let opacity: Double

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { tl in
                Canvas { ctx, size in
                    let t = tl.date.timeIntervalSinceReferenceDate
                    for layer in 0..<2 {
                        let amp: Double = layer == 0 ? 14 : 9
                        let phase: Double = t * (layer == 0 ? 0.35 : -0.5)
                        let base: Double = Double(size.height) * (layer == 0 ? 0.80 : 0.86)
                        var path = Path()
                        path.move(to: CGPoint(x: 0, y: size.height))
                        var x: Double = 0
                        while x <= Double(size.width) {
                            let wave = sin(x / Double(size.width) * Double.pi * 3 + phase) * amp
                            path.addLine(to: CGPoint(x: x, y: base + wave))
                            x += 4
                        }
                        path.addLine(to: CGPoint(x: size.width, y: size.height))
                        path.closeSubpath()
                        ctx.fill(path, with: .color(color.opacity(opacity * (layer == 0 ? 0.9 : 0.5))))
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}

/// Плашка для вкладок и мини-плеера: стекло, плавающая карточка или просто полоса.
struct PanelStyle: ViewModifier {
    let floating: Bool
    private let store = ThemeStore.shared

    func body(content: Content) -> some View {
        let s = store.spec
        let radius: CGFloat = floating ? CGFloat(s.uiR) : 0
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        if s.glass {
            content
                .background {
                    ZStack {
                        shape.fill(.ultraThinMaterial)
                        shape.fill(Color.white.opacity(s.gTint))
                        shape.fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.28), .clear, .clear, Color.white.opacity(0.12)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .opacity(min(s.gBorder * 2.2, 1))
                        shape.strokeBorder(Color.white.opacity(s.gBorder), lineWidth: floating ? 1 : 0)
                    }
                }
                .clipShape(shape)
        } else if floating {
            content
                .background(Theme.bg, in: shape)
                .overlay(shape.strokeBorder(Theme.line, lineWidth: 1))
                .clipShape(shape)
        } else {
            content
        }
    }
}

extension View {
    func panelStyle(floating: Bool) -> some View {
        modifier(PanelStyle(floating: floating))
    }
}

/// Экран выбора темы.
struct ThemesView: View {
    @Environment(\.dismiss) private var dismiss
    private let store = ThemeStore.shared

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Text("THEMES")
                        .font(Theme.mono(12, .bold))
                        .foregroundStyle(Theme.dim)
                    Spacer()
                    Button("DONE") { dismiss() }
                        .font(Theme.mono(12, .bold))
                        .foregroundStyle(Theme.accent)
                        .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)

                Hairline()

                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(store.themes) { t in
                            row(t)
                            Hairline().padding(.leading, 20)
                        }
                    }

                    Button {
                        store.importFromClipboard()
                    } label: {
                        Text("ВСТАВИТЬ ТЕМУ ИЗ БУФЕРА")
                            .font(Theme.mono(12, .bold))
                            .foregroundStyle(Theme.accent)
                            .padding(.vertical, 22)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)

                    if let note = store.notice {
                        Text(note)
                            .font(Theme.mono(11))
                            .foregroundStyle(Theme.dim)
                            .padding(.horizontal, 24)
                            .multilineTextAlignment(.center)
                    }

                    Text("Скопируй JSON в дизайн-стенде и нажми кнопку выше.\nИли положи файл theme.json (или папку Themes) в Files → На iPhone → Cadence.")
                        .font(Theme.mono(11))
                        .foregroundStyle(Theme.dim)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 20)
                }
            }
        }
    }

    private func row(_ t: SavedTheme) -> some View {
        let active = t.id == store.activeID
        return Button {
            store.activate(t.id)
        } label: {
            HStack(spacing: 14) {
                HStack(spacing: 0) {
                    Rectangle().fill(Color(hex: t.spec.bg))
                    Rectangle().fill(Color(hex: t.spec.wall == .solid ? t.spec.fg : t.spec.wA))
                    Rectangle().fill(Color(hex: t.spec.accent))
                }
                .frame(width: 42, height: 24)
                .overlay(Rectangle().stroke(Theme.line, lineWidth: 1))

                Text(t.spec.name)
                    .font(Theme.mono(14, active ? .bold : .regular))
                    .foregroundStyle(active ? Theme.accent : Theme.fg)
                    .lineLimit(1)
                Spacer()
                Text(t.builtin ? "PRESET" : "MINE")
                    .font(Theme.mono(10))
                    .foregroundStyle(Theme.dim)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            if !t.builtin {
                Button("Удалить", role: .destructive) { store.delete(t.id) }
            }
        }
    }
}
