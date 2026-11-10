import SwiftUI
import UIKit

/// Редактор темы прямо в приложении. Любое изменение сразу видно на всём приложении
/// (живой предпросмотр), на диск пишется только по кнопке Save.
@MainActor
struct ThemeEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ServerAI.self) private var ai
    private let store = ThemeStore.shared

    @State private var draft: ThemeSpec
    @State private var editingID: String?
    @State private var aiPrompt = ""
    @State private var aiError: String?
    @State private var aiBusy = false
    @State private var saved = false
    @State private var note: String?

    init() {
        let shared = ThemeStore.shared
        let current = shared.activeTheme
        let builtin = current?.builtin ?? true
        var spec = shared.spec
        if builtin { spec.name = spec.name + " Copy" }
        _draft = State(initialValue: spec)
        _editingID = State(initialValue: builtin ? nil : current?.id)
    }

    var body: some View {
        NavigationStack {
            Form {
                previewSection
                aiSection
                basicsSection
                colorsSection
                wallpaperSection
                glassSection
                shapeSection
                layoutSection
                flowSection
                shareSection
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .navigationTitle("Theme Editor")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        store.endPreview()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                }
            }
        }
        .tint(Theme.accent)
        .onAppear { store.preview(draft) }
        .onChange(of: draft) { _, new in store.preview(new) }
        .onDisappear {
            if !saved { store.endPreview() }
        }
    }

    // MARK: разделы

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        Section {
            content()
        } header: {
            Text(title).foregroundStyle(Theme.dim)
        }
    }

    private var previewSection: some View {
        group("Preview") {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: CGFloat(draft.radius), style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: draft.accent), Color(hex: draft.wB)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 54, height: 54)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Song Title")
                        .font(Theme.font(16, .semibold))
                        .foregroundStyle(Theme.fg)
                    Text("Artist · Album")
                        .font(Theme.font(13))
                        .foregroundStyle(Theme.dim)
                }
                Spacer()
                Image(systemName: "play.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Theme.accent)
            }
            .padding(12)
            .background(Theme.cardStrong, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
        }
    }

    private var aiSection: some View {
        group("Design with AI") {
            TextField("e.g. warm sunset, soft and calm", text: $aiPrompt, axis: .vertical)
                .font(Theme.font(15))
                .foregroundStyle(Theme.fg)
                .lineLimit(1...3)
                .listRowBackground(Theme.card)

            Button {
                generate()
            } label: {
                HStack(spacing: 8) {
                    if aiBusy { ProgressView() }
                    Text(aiBusy ? "Designing…" : "Generate with AI")
                    Spacer()
                }
                .font(Theme.font(15, .semibold))
                .foregroundStyle(Theme.accent)
            }
            .disabled(aiBusy || aiPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !ai.isConfigured)
            .listRowBackground(Theme.card)

            if !ai.isConfigured {
                Text("Адрес сервера не задан: Settings → AI Server.")
                    .font(Theme.font(12))
                    .foregroundStyle(Theme.dim)
                    .listRowBackground(Theme.card)
            }
            if let aiError {
                Text(aiError)
                    .font(Theme.font(12))
                    .foregroundStyle(Color.red)
                    .listRowBackground(Theme.card)
            }

            Button {
                Haptics.tap()
                draft = Self.randomized(draft)
            } label: {
                HStack {
                    Label("Random Palette", systemImage: "dice")
                    Spacer()
                }
                .font(Theme.font(15))
                .foregroundStyle(Theme.accent)
            }
            .listRowBackground(Theme.card)
        }
    }

    private var basicsSection: some View {
        group("Basics") {
            HStack {
                Text("Name").foregroundStyle(Theme.dim)
                TextField("Theme name", text: $draft.name)
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(Theme.fg)
            }
            .font(Theme.font(15))
            .listRowBackground(Theme.card)

            Picker("Style", selection: $draft.ui) {
                Text("Modern").tag(UIStyle.modern)
                Text("Classic").tag(UIStyle.classic)
            }
            .pickerStyle(.segmented)
            .listRowBackground(Theme.card)

            Picker("Font", selection: $draft.font) {
                ForEach(FontKind.allCases, id: \.self) { kind in
                    Text(Self.fontLabel(kind)).tag(kind)
                }
            }
            .font(Theme.font(15))
            .listRowBackground(Theme.card)
        }
    }

    private var colorsSection: some View {
        group("Colors") {
            colorRow("Background", \.bg)
            colorRow("Text", \.fg)
            colorRow("Secondary text", \.dim)
            colorRow("Accent", \.accent)
        }
    }

    private var wallpaperSection: some View {
        group("Wallpaper") {
            Picker("Type", selection: $draft.wall) {
                ForEach(WallKind.allCases, id: \.self) { kind in
                    Text(kind.rawValue.capitalized).tag(kind)
                }
            }
            .font(Theme.font(15))
            .listRowBackground(Theme.card)

            if draft.wall == .gradient || draft.wall == .aurora {
                colorRow("Color 1", \.wA)
                colorRow("Color 2", \.wB)
                colorRow("Color 3", \.wC)
            }
            if draft.wall == .gradient {
                sliderRow("Angle", $draft.wAngle, 0...360, format: "%.0f")
            }
            if draft.wall == .cover {
                sliderRow("Blur", $draft.wBlur, 0...80, format: "%.0f")
            }
            if draft.wall != .solid {
                sliderRow("Darken", $draft.wDim, 0...0.85)
            }
            sliderRow("Sea waves", $draft.waves, 0...1)
            if draft.waves > 0.01 {
                colorRow("Waves color", \.waveCol)
            }
        }
    }

    private var glassSection: some View {
        group("Glass") {
            Toggle("Translucent bars", isOn: $draft.glass)
                .font(Theme.font(15))
                .foregroundStyle(Theme.fg)
                .listRowBackground(Theme.card)
            if draft.glass {
                sliderRow("Tint", $draft.gTint, 0...0.4)
                sliderRow("Border", $draft.gBorder, 0...0.6)
            }
        }
    }

    private var shapeSection: some View {
        group("Shape") {
            sliderRow("Cover corners", $draft.radius, 0...24, format: "%.0f")
            sliderRow("Panel corners", $draft.uiR, 0...32, format: "%.0f")
        }
    }

    private var layoutSection: some View {
        group("Layout") {
            if !draft.modern {
                Picker("Tabs", selection: $draft.tabs) {
                    ForEach(TabsPos.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                }
                .font(Theme.font(15))
                .listRowBackground(Theme.card)

                Picker("Mini player", selection: $draft.mini) {
                    ForEach(MiniStyle.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                }
                .font(Theme.font(15))
                .listRowBackground(Theme.card)

                Toggle("Header line", isOn: $draft.hdr)
                    .font(Theme.font(15))
                    .foregroundStyle(Theme.fg)
                    .listRowBackground(Theme.card)
            }
            Picker("Cover Flow position", selection: $draft.align) {
                ForEach(FlowAlign.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
            }
            .font(Theme.font(15))
            .listRowBackground(Theme.card)
        }
    }

    private var flowSection: some View {
        group("Cover Flow") {
            sliderRow("Tilt", $draft.angle, 20...85, format: "%.0f")
            sliderRow("Spread", $draft.spread, 0...0.8)
            sliderRow("Overlap", $draft.overlap, 0.3...0.8)
            sliderRow("Side scale", $draft.sideScale, 0.6...1)
            sliderRow("Cover size", $draft.cover, 0.4...0.7)
            sliderRow("Reflection", $draft.refl, 0...0.6)
            Toggle("Flip tilt direction", isOn: $draft.flip)
                .font(Theme.font(15))
                .foregroundStyle(Theme.fg)
                .listRowBackground(Theme.card)
        }
    }

    private var shareSection: some View {
        group("Share") {
            Button {
                UIPasteboard.general.string = draft.jsonString()
                Haptics.success()
                note = "JSON скопирован"
            } label: {
                HStack {
                    Label("Copy JSON", systemImage: "doc.on.doc")
                    Spacer()
                }
                .font(Theme.font(15))
                .foregroundStyle(Theme.accent)
            }
            .listRowBackground(Theme.card)

            Button {
                if let text = UIPasteboard.general.string,
                   let data = text.data(using: .utf8),
                   let parsed = ThemeSpec.parse(data) {
                    draft = parsed
                    note = "Тема из буфера применена к редактору"
                } else {
                    note = "В буфере нет темы"
                }
            } label: {
                HStack {
                    Label("Paste JSON into Editor", systemImage: "doc.on.clipboard")
                    Spacer()
                }
                .font(Theme.font(15))
                .foregroundStyle(Theme.accent)
            }
            .listRowBackground(Theme.card)

            if let note {
                Text(note)
                    .font(Theme.font(12))
                    .foregroundStyle(Theme.dim)
                    .listRowBackground(Theme.card)
            }
        }
    }

    // MARK: строки

    private func colorRow(_ title: String, _ path: WritableKeyPath<ThemeSpec, String>) -> some View {
        let binding = Binding<Color>(
            get: { Color(hex: draft[keyPath: path]) },
            set: { draft[keyPath: path] = $0.hexString }
        )
        return ColorPicker(selection: binding, supportsOpacity: false) {
            HStack {
                Text(title)
                    .font(Theme.font(15))
                    .foregroundStyle(Theme.fg)
                Spacer()
                Text(draft[keyPath: path])
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Theme.dim)
            }
        }
        .listRowBackground(Theme.card)
    }

    private func sliderRow(
        _ title: String,
        _ value: Binding<Double>,
        _ range: ClosedRange<Double>,
        format: String = "%.2f"
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                    .font(Theme.font(15))
                    .foregroundStyle(Theme.fg)
                Spacer()
                Text(String(format: format, value.wrappedValue))
                    .font(Theme.font(13))
                    .monospacedDigit()
                    .foregroundStyle(Theme.dim)
            }
            Slider(value: value, in: range)
        }
        .listRowBackground(Theme.card)
    }

    // MARK: действия

    private func save() {
        var spec = draft
        let trimmed = spec.name.trimmingCharacters(in: .whitespacesAndNewlines)
        spec.name = trimmed.isEmpty ? "My Theme" : trimmed
        if store.save(spec, replacing: editingID) {
            saved = true
            Haptics.success()
            dismiss()
        }
    }

    private func generate() {
        let prompt = aiPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        aiBusy = true
        aiError = nil
        let base = draft
        Task {
            do {
                let result = try await ai.generateTheme(prompt: prompt, current: base)
                draft = result
                Haptics.success()
            } catch {
                aiError = error.localizedDescription
            }
            aiBusy = false
        }
    }

    // MARK: помощники

    private static func fontLabel(_ kind: FontKind) -> String {
        switch kind {
        case .sf: return "System"
        case .rounded: return "Rounded"
        case .serif: return "Serif"
        case .sys: return "Mono"
        case .jb: return "Mono (JetBrains)"
        case .plex: return "Mono (Plex)"
        case .space: return "Mono (Space)"
        }
    }

    /// Случайная гармоничная палитра. Светлая или тёмная остаётся такой же, как у текущей темы.
    private static func randomized(_ base: ThemeSpec) -> ThemeSpec {
        var t = base
        let hue = Double.random(in: 0..<1)
        let shift = [0.0, 0.08, 0.5, 0.33].randomElement() ?? 0.5

        func hex(_ h: Double, _ s: Double, _ b: Double) -> String {
            var hh = h.truncatingRemainder(dividingBy: 1)
            if hh < 0 { hh += 1 }
            return Color(hue: hh, saturation: s, brightness: b).hexString
        }

        if base.isLight {
            t.bg = hex(hue, 0.07, 0.97)
            t.fg = hex(hue, 0.45, 0.13)
            t.dim = hex(hue, 0.12, 0.46)
            t.accent = hex(hue + shift, 0.78, 0.86)
        } else {
            t.bg = hex(hue, 0.55, 0.09)
            t.fg = hex(hue, 0.05, 0.98)
            t.dim = hex(hue, 0.16, 0.68)
            t.accent = hex(hue + shift, 0.68, 1.0)
        }
        t.wA = hex(hue, 0.72, 0.56)
        t.wB = hex(hue + 0.1, 0.72, 0.42)
        t.wC = hex(hue - 0.1, 0.62, 0.62)
        t.waveCol = hex(hue, 0.35, 0.9)
        if t.wall == .solid, Bool.random() {
            t.wall = .aurora
            t.wDim = 0.45
        }
        t.name = "Random"
        return t
    }
}
