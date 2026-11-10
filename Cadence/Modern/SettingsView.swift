import SwiftUI

private func settingsRowBackground() -> Color { Theme.card }

/// Настройки: библиотека (обновить, пересобрать, починить альбомы), внешний вид, ИИ-сервер.
@MainActor
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(Library.self) private var library
    @Environment(\.openSheet) private var openSheet
    private let store = ThemeStore.shared

    @State private var confirmRebuild = false
    @State private var confirmReset = false

    var body: some View {
        NavigationStack {
            List {
                librarySection
                maintenanceSection
                appearanceSection
                aiSection
                aboutSection
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .task { await library.checkChanges() }
        }
        .tint(Theme.accent)
        .confirmationDialog(
            "Rebuild the whole library? All tags and covers will be read again. Your manual edits stay.",
            isPresented: $confirmRebuild,
            titleVisibility: .visible
        ) {
            Button("Rebuild", role: .destructive) {
                Task { await library.rescan(full: true) }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(
            "Remove all manual edits? Songs go back to what the files say.",
            isPresented: $confirmReset,
            titleVisibility: .visible
        ) {
            Button("Remove Edits", role: .destructive) {
                library.resetEdits(Array(library.edits.keys))
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: библиотека

    private var librarySection: some View {
        Section {
            HStack {
                Text("Library")
                    .foregroundStyle(Theme.fg)
                Spacer()
                Text("\(library.stats.tracks) songs · \(library.stats.albums) albums")
                    .foregroundStyle(Theme.dim)
            }
            .font(Theme.font(15))
            .listRowBackground(settingsRowBackground())

            VStack(alignment: .leading, spacing: 8) {
                Button {
                    Haptics.tap()
                    Task { await library.rescan() }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                        Text(library.isScanning ? "Updating…" : "Update Library")
                            .fontWeight(.semibold)
                        Spacer()
                    }
                    .font(Theme.font(16))
                    .foregroundStyle(Theme.accent)
                }
                .disabled(library.isScanning)

                if library.isScanning {
                    if library.scanTotal > 0 {
                        ProgressView(value: Double(library.scanDone), total: Double(max(library.scanTotal, 1)))
                            .tint(Theme.accent)
                        Text("\(library.scanNote.capitalized) \(library.scanDone) / \(library.scanTotal)")
                            .font(Theme.font(12))
                            .foregroundStyle(Theme.dim)
                    } else {
                        ProgressView().tint(Theme.accent)
                        Text(library.scanNote.capitalized)
                            .font(Theme.font(12))
                            .foregroundStyle(Theme.dim)
                    }
                } else {
                    Text(changesText)
                        .font(Theme.font(12))
                        .foregroundStyle(Theme.dim)
                }
            }
            .listRowBackground(settingsRowBackground())
        } header: {
            Text("Library").foregroundStyle(Theme.dim)
        } footer: {
            Text("Папка с музыкой читается только когда ты нажимаешь Update (или тянешь вниз список альбомов/песен). При запуске приложение ничего не сканирует: всё берётся из сохранённой базы. Обновление читает только новые и изменённые файлы.")
                .foregroundStyle(Theme.dim)
        }
    }

    private var changesText: String {
        var parts: [String] = []
        if let c = library.changes {
            if c.total == 0 {
                parts.append("No new or changed files")
            } else {
                var items: [String] = []
                if c.added > 0 { items.append("\(c.added) new") }
                if c.changed > 0 { items.append("\(c.changed) changed") }
                if c.removed > 0 { items.append("\(c.removed) removed") }
                parts.append(items.joined(separator: " · "))
            }
        }
        if let last = library.lastScan {
            parts.append("Updated " + last.formatted(date: .abbreviated, time: .shortened))
        }
        return parts.isEmpty ? "Not scanned yet" : parts.joined(separator: "\n")
    }

    private var maintenanceSection: some View {
        Section {
            NavigationLink {
                LooseTracksView()
            } label: {
                HStack {
                    Text("Fix Albums")
                        .foregroundStyle(Theme.fg)
                    Spacer()
                    Text("\(library.untagged.count) songs")
                        .foregroundStyle(Theme.dim)
                }
                .font(Theme.font(15))
            }
            .listRowBackground(settingsRowBackground())

            HStack {
                Text("Songs without album")
                    .foregroundStyle(Theme.fg)
                Spacer()
                Picker("", selection: Binding(
                    get: { library.fallback },
                    set: { library.setFallback($0) }
                )) {
                    ForEach(AlbumFallback.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }
            .font(Theme.font(15))
            .listRowBackground(settingsRowBackground())

            statRow("No album tag", library.stats.noAlbumTag)
            statRow("No artist tag", library.stats.noArtistTag)
            statRow("Albums without cover", library.stats.albumsNoCover)
            statRow("Manual edits", library.stats.edited)

            if library.stats.edited > 0 {
                Button("Remove All Manual Edits", role: .destructive) {
                    confirmReset = true
                }
                .font(Theme.font(15))
                .listRowBackground(settingsRowBackground())
            }

            Button("Rebuild Library from Scratch", role: .destructive) {
                confirmRebuild = true
            }
            .font(Theme.font(15))
            .disabled(library.isScanning)
            .listRowBackground(settingsRowBackground())
        } header: {
            Text("Albums & Tags").foregroundStyle(Theme.dim)
        } footer: {
            Text("Если у песни нет тега альбома и она лежит просто в корне, она попадает в альбом по правилу выше (по названию песни, по исполнителю или в один Unknown Album). Папка альбома используется, если она есть. Любую песню или альбом можно поправить вручную: долгое нажатие → Edit.")
                .foregroundStyle(Theme.dim)
        }
    }

    private func statRow(_ title: String, _ value: Int) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(Theme.fg)
            Spacer()
            Text("\(value)")
                .foregroundStyle(Theme.dim)
                .monospacedDigit()
        }
        .font(Theme.font(15))
        .listRowBackground(settingsRowBackground())
    }

    // MARK: внешний вид и ИИ

    private var appearanceSection: some View {
        Section {
            NavigationLink {
                AppearanceView()
            } label: {
                HStack(spacing: 12) {
                    ThemeSwatch(spec: store.spec)
                    Text("Theme")
                        .foregroundStyle(Theme.fg)
                    Spacer()
                    Text(store.spec.name)
                        .foregroundStyle(Theme.dim)
                }
                .font(Theme.font(15))
            }
            .listRowBackground(settingsRowBackground())

            Button {
                openSheet(.themeEditor)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "paintpalette")
                    Text("Edit Theme…")
                    Spacer()
                }
                .font(Theme.font(15))
                .foregroundStyle(Theme.accent)
            }
            .listRowBackground(settingsRowBackground())
        } header: {
            Text("Appearance").foregroundStyle(Theme.dim)
        } footer: {
            Text("Редактор тем открывается снизу: двигай ползунки и смотри, как меняется приложение прямо сейчас.")
                .foregroundStyle(Theme.dim)
        }
    }

    private var aiSection: some View {
        Section {
            NavigationLink {
                ScrollView {
                    ServerSection()
                        .padding(.vertical, 16)
                }
                .background(Theme.bg)
                .navigationTitle("AI Server")
                .navigationBarTitleDisplayMode(.inline)
            } label: {
                HStack {
                    Text("AI Server")
                        .foregroundStyle(Theme.fg)
                    Spacer()
                }
                .font(Theme.font(15))
            }
            .listRowBackground(settingsRowBackground())
        } header: {
            Text("Wave & AI").foregroundStyle(Theme.dim)
        }
    }

    private var aboutSection: some View {
        Section {
            HStack {
                Text("Cadence")
                    .foregroundStyle(Theme.fg)
                Spacer()
                Text(Self.versionText)
                    .foregroundStyle(Theme.dim)
            }
            .font(Theme.font(15))
            .listRowBackground(settingsRowBackground())
        }
    }

    private static var versionText: String {
        let info = Bundle.main.infoDictionary
        let v = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = info?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }
}

/// Мини-превью темы: фон, акцент, текст.
struct ThemeSwatch: View {
    let spec: ThemeSpec

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color(hex: spec.bg))
            if spec.wall != .solid {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: spec.wA).opacity(0.85), Color(hex: spec.wB).opacity(0.85)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            HStack(spacing: 3) {
                Circle().fill(Color(hex: spec.accent)).frame(width: 9, height: 9)
                VStack(alignment: .leading, spacing: 2) {
                    Capsule().fill(Color(hex: spec.fg)).frame(width: 14, height: 3)
                    Capsule().fill(Color(hex: spec.dim)).frame(width: 9, height: 3)
                }
            }
        }
        .frame(width: 46, height: 30)
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(Color.gray.opacity(0.35), lineWidth: 0.5)
        )
    }
}

// MARK: - Выбор темы

@MainActor
struct AppearanceView: View {
    @Environment(\.openSheet) private var openSheet
    private let store = ThemeStore.shared

    var body: some View {
        List {
            Section {
                ForEach(store.themes) { t in
                    Button {
                        Haptics.select()
                        store.activate(t.id)
                    } label: {
                        HStack(spacing: 12) {
                            ThemeSwatch(spec: t.spec)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(t.spec.name)
                                    .font(Theme.font(16, t.id == store.activeID ? .semibold : .regular))
                                    .foregroundStyle(Theme.fg)
                                Text((t.spec.modern ? "Modern" : "Classic") + (t.builtin ? "" : " · mine"))
                                    .font(Theme.font(12))
                                    .foregroundStyle(Theme.dim)
                            }
                            Spacer()
                            if t.id == store.activeID {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Theme.accent)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Theme.card)
                    .swipeActions(edge: .trailing) {
                        if !t.builtin {
                            Button(role: .destructive) {
                                store.delete(t.id)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            } header: {
                Text("Themes").foregroundStyle(Theme.dim)
            }

            Section {
                Button {
                    openSheet(.themeEditor)
                } label: {
                    Label("Edit Current Theme…", systemImage: "slider.horizontal.3")
                        .foregroundStyle(Theme.accent)
                }
                .listRowBackground(Theme.card)

                Button {
                    store.importFromClipboard()
                } label: {
                    Label("Paste Theme from Clipboard", systemImage: "doc.on.clipboard")
                        .foregroundStyle(Theme.accent)
                }
                .listRowBackground(Theme.card)

                Button {
                    UIPasteboard.general.string = store.spec.jsonString()
                    Haptics.success()
                } label: {
                    Label("Copy Current Theme JSON", systemImage: "doc.on.doc")
                        .foregroundStyle(Theme.accent)
                }
                .listRowBackground(Theme.card)
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    if let note = store.notice {
                        Text(note).foregroundStyle(Theme.fg)
                    }
                    Text("Тему можно скинуть другу JSON-ом или положить файл в Files → На iPhone → Cadence → Themes.")
                        .foregroundStyle(Theme.dim)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.bg)
        .navigationTitle("Theme")
        .navigationBarTitleDisplayMode(.inline)
    }
}
