import SwiftUI
import UIKit

// MARK: - Шиты и навигация через Environment

/// Всё, что открывается поверх приложения. Один `.sheet(item:)` в корне.
enum AppSheet: Identifiable {
    case settings
    case themeEditor
    case classicThemes
    case editTrack(Track)
    case editAlbum(Album)

    var id: String {
        switch self {
        case .settings: return "settings"
        case .themeEditor: return "editor"
        case .classicThemes: return "classic-themes"
        case .editTrack(let t): return "track:" + t.id
        case .editAlbum(let a): return "album:" + a.id
        }
    }
}

private struct OpenSheetKey: EnvironmentKey {
    static let defaultValue: (AppSheet) -> Void = { _ in }
}

private struct OpenAlbumKey: EnvironmentKey {
    static let defaultValue: (Album) -> Void = { _ in }
}

extension EnvironmentValues {
    var openSheet: (AppSheet) -> Void {
        get { self[OpenSheetKey.self] }
        set { self[OpenSheetKey.self] = newValue }
    }

    var openAlbum: (Album) -> Void {
        get { self[OpenAlbumKey.self] }
        set { self[OpenAlbumKey.self] = newValue }
    }
}

// MARK: - Мелкие элементы

struct PressScaleStyle: ButtonStyle {
    var scale: CGFloat = 0.96

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Круглая кнопка-иконка в заголовках.
struct RoundIcon: View {
    let systemName: String
    var filled = false

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(filled ? Theme.bg : Theme.fg)
            .frame(width: 36, height: 36)
            .background(filled ? Theme.accent : Theme.card, in: Circle())
    }
}

struct ScreenHeader<Trailing: View>: View {
    @Environment(\.openSheet) private var openSheet

    let title: String
    var subtitle: String?
    var showSettings = true
    let trailing: () -> Trailing

    init(
        title: String,
        subtitle: String? = nil,
        showSettings: Bool = true,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.title = title
        self.subtitle = subtitle
        self.showSettings = showSettings
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(Theme.font(32, .bold))
                    .foregroundStyle(Theme.fg)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let subtitle {
                    Text(subtitle)
                        .font(Theme.font(13))
                        .foregroundStyle(Theme.dim)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            trailing()
            if showSettings {
                Button {
                    Haptics.tap()
                    openSheet(.settings)
                } label: {
                    RoundIcon(systemName: "gearshape")
                }
                .buttonStyle(PressScaleStyle(scale: 0.9))
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }
}

extension ScreenHeader where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil, showSettings: Bool = true) {
        self.init(title: title, subtitle: subtitle, showSettings: showSettings, trailing: { EmptyView() })
    }
}

struct SearchField: View {
    @Binding var text: String
    var prompt: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.dim)
            TextField("", text: $text, prompt: Text(prompt).foregroundStyle(Theme.dim))
                .font(Theme.font(16))
                .foregroundStyle(Theme.fg)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.dim)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// Поиск без учёта регистра и диакритики.
func textMatch(_ query: String, _ fields: String...) -> Bool {
    for f in fields where f.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil {
        return true
    }
    return false
}

func durationText(_ seconds: TimeInterval) -> String {
    let m = Int((seconds / 60).rounded())
    if m >= 60 { return "\(m / 60) h \(m % 60) min" }
    return "\(max(m, 1)) min"
}

// MARK: - Цвета и безопасные поля

extension Color {
    /// "#rrggbb" из любого цвета (для ColorPicker).
    var hexString: String {
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        func byte(_ v: CGFloat) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
        return String(format: "#%02x%02x%02x", byte(r), byte(g), byte(b))
    }
}

enum SafeInsets {
    /// Вырезы экрана из окна: запасной вариант, если GeometryReader отдал нули.
    static var window: UIEdgeInsets {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.first(where: { $0.activationState == .foregroundActive })?.windows.first(where: { $0.isKeyWindow })
            ?? scenes.first?.windows.first
        return window?.safeAreaInsets ?? .zero
    }
}
