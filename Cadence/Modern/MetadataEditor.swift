import SwiftUI

/// Строка формы: подпись слева, поле справа. Цвета из темы.
private struct EditRow: View {
    let label: String
    @Binding var text: String
    var numeric = false

    var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .font(Theme.font(15))
                .foregroundStyle(Theme.dim)
                .frame(width: 104, alignment: .leading)
            TextField("", text: $text)
                .font(Theme.font(16))
                .foregroundStyle(Theme.fg)
                .multilineTextAlignment(.trailing)
                .keyboardType(numeric ? .numberPad : .default)
                .autocorrectionDisabled()
        }
        .listRowBackground(Theme.card)
    }
}

private func clean(_ s: String) -> String {
    s.trimmingCharacters(in: .whitespacesAndNewlines)
}

// MARK: - Одна песня

@MainActor
struct TrackEditSheet: View {
    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss

    let track: Track

    @State private var title = ""
    @State private var artist = ""
    @State private var albumArtist = ""
    @State private var album = ""
    @State private var number = ""
    @State private var disc = ""
    @State private var year = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    EditRow(label: "Title", text: $title)
                    EditRow(label: "Artist", text: $artist)
                } header: {
                    Text("Song").foregroundStyle(Theme.dim)
                }
                Section {
                    EditRow(label: "Album", text: $album)
                    EditRow(label: "Album Artist", text: $albumArtist)
                } header: {
                    Text("Album").foregroundStyle(Theme.dim)
                } footer: {
                    Text("Песни с одинаковым названием альбома и исполнителем альбома собираются в один альбом.")
                        .foregroundStyle(Theme.dim)
                }
                Section {
                    EditRow(label: "Track #", text: $number, numeric: true)
                    EditRow(label: "Disc #", text: $disc, numeric: true)
                    EditRow(label: "Year", text: $year, numeric: true)
                } header: {
                    Text("Numbers").foregroundStyle(Theme.dim)
                }
                Section {
                    Text(track.id)
                        .font(Theme.font(12))
                        .foregroundStyle(Theme.dim)
                        .listRowBackground(Theme.card)
                } header: {
                    Text("File").foregroundStyle(Theme.dim)
                }
                if library.hasEdits([track.id]) {
                    Section {
                        Button("Reset to File Tags", role: .destructive) {
                            library.resetEdits([track.id])
                            dismiss()
                        }
                        .listRowBackground(Theme.card)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .navigationTitle("Edit Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                }
            }
        }
        .tint(Theme.accent)
        .onAppear(perform: load)
    }

    private func load() {
        title = track.title
        artist = track.artist
        albumArtist = track.albumArtist
        album = track.album
        number = track.number > 0 ? String(track.number) : ""
        disc = track.disc > 0 ? String(track.disc) : ""
        year = track.year > 0 ? String(track.year) : ""
    }

    private func save() {
        let t = clean(title), a = clean(artist), aa = clean(albumArtist), al = clean(album)
        let n = Int(clean(number)) ?? 0
        let d = Int(clean(disc)) ?? 0
        let y = Int(clean(year)) ?? 0
        library.editTracks([track.id]) { e in
            if t != track.title { e.title = t.isEmpty ? nil : t }
            if a != track.artist { e.artist = a.isEmpty ? nil : a }
            if aa != track.albumArtist { e.albumArtist = aa.isEmpty ? nil : aa }
            if al != track.album { e.album = al.isEmpty ? nil : al }
            if n != track.number { e.number = n > 0 ? n : nil }
            if d != track.disc { e.disc = d > 0 ? d : nil }
            if y != track.year { e.year = y > 0 ? y : nil }
        }
        Haptics.success()
        dismiss()
    }
}

// MARK: - Целый альбом

@MainActor
struct AlbumEditSheet: View {
    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss

    let album: Album

    @State private var title = ""
    @State private var artist = ""
    @State private var year = ""
    @State private var alsoTrackArtist = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    EditRow(label: "Title", text: $title)
                    EditRow(label: "Artist", text: $artist)
                    EditRow(label: "Year", text: $year, numeric: true)
                } header: {
                    Text("Album (\(album.tracks.count) songs)").foregroundStyle(Theme.dim)
                } footer: {
                    Text("Правка применится ко всем песням альбома. Файлы не меняются, правки лежат в приложении и переживают пересканирование.")
                        .foregroundStyle(Theme.dim)
                }
                Section {
                    Toggle("Also set as artist of every song", isOn: $alsoTrackArtist)
                        .font(Theme.font(15))
                        .foregroundStyle(Theme.fg)
                        .listRowBackground(Theme.card)
                }
                if library.hasEdits(album.tracks.map { $0.id }) {
                    Section {
                        Button("Reset All Edits in Album", role: .destructive) {
                            library.resetEdits(album.tracks.map { $0.id })
                            dismiss()
                        }
                        .listRowBackground(Theme.card)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .navigationTitle("Edit Album")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                }
            }
        }
        .tint(Theme.accent)
        .onAppear {
            title = album.title
            artist = album.artist == "Various Artists" ? "" : album.artist
            year = album.year > 0 ? String(album.year) : ""
        }
    }

    private func save() {
        let ids = album.tracks.map { $0.id }
        let t = clean(title), a = clean(artist)
        let y = Int(clean(year)) ?? 0
        let titleChanged = !t.isEmpty && t != album.title
        let artistChanged = !a.isEmpty && a != album.artist
        let setTrackArtist = alsoTrackArtist
        library.editTracks(ids) { e in
            if titleChanged { e.album = t }
            if artistChanged {
                e.albumArtist = a
                if setTrackArtist { e.artist = a }
            } else if setTrackArtist && !a.isEmpty {
                e.artist = a
            }
            if y > 0 && y != album.year { e.year = y }
        }
        Haptics.success()
        dismiss()
    }
}

// MARK: - Массово: назначить альбом выбранным песням

@MainActor
struct BulkAlbumSheet: View {
    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss

    let ids: [String]
    var onDone: () -> Void

    @State private var title = ""
    @State private var artist = ""
    @State private var alsoTrackArtist = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    EditRow(label: "Album", text: $title)
                    EditRow(label: "Album Artist", text: $artist)
                } header: {
                    Text("\(ids.count) songs selected").foregroundStyle(Theme.dim)
                }
                Section {
                    Toggle("Also set as artist of every song", isOn: $alsoTrackArtist)
                        .font(Theme.font(15))
                        .foregroundStyle(Theme.fg)
                        .listRowBackground(Theme.card)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .navigationTitle("Set Album")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") { apply() }
                        .fontWeight(.semibold)
                        .disabled(clean(title).isEmpty)
                }
            }
        }
        .tint(Theme.accent)
    }

    private func apply() {
        let t = clean(title), a = clean(artist)
        let setTrackArtist = alsoTrackArtist
        library.editTracks(ids) { e in
            e.album = t
            if !a.isEmpty {
                e.albumArtist = a
                if setTrackArtist { e.artist = a }
            }
        }
        Haptics.success()
        dismiss()
        onDone()
    }
}

// MARK: - Песни без альбома

@MainActor
struct LooseTracksView: View {
    @Environment(Library.self) private var library

    @State private var selection = Set<String>()
    @State private var query = ""
    @State private var showBulk = false
    @State private var editMode: EditMode = .active

    private var shown: [Track] {
        let q = clean(query)
        if q.isEmpty { return library.untagged }
        return library.untagged.filter { textMatch(q, $0.title, $0.artist, $0.id) }
    }

    var body: some View {
        let list = shown
        Group {
            if library.untagged.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 40, weight: .light))
                        .foregroundStyle(Theme.dim)
                    Text("Все песни с альбомом")
                        .font(Theme.font(16))
                        .foregroundStyle(Theme.fg)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $selection) {
                    Section {
                        ForEach(list) { track in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(track.title)
                                    .font(Theme.font(15))
                                    .foregroundStyle(Theme.fg)
                                    .lineLimit(1)
                                Text(track.artist + " · " + track.id)
                                    .font(Theme.font(12))
                                    .foregroundStyle(Theme.dim)
                                    .lineLimit(1)
                            }
                            .listRowBackground(Theme.card)
                        }
                    } footer: {
                        Text("Отметь песни одного альбома (поиск сверху помогает выбрать всех одного исполнителя), потом Set Album.")
                            .foregroundStyle(Theme.dim)
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .searchable(text: $query, prompt: "Filter")
                .environment(\.editMode, $editMode)
            }
        }
        .background(Theme.bg)
        .navigationTitle("Fix Albums (\(library.untagged.count))")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .bottomBar) {
                Button(selection.count == list.count && !list.isEmpty ? "Select None" : "Select All") {
                    if selection.count == list.count {
                        selection.removeAll()
                    } else {
                        selection = Set(list.map { $0.id })
                    }
                }
                .disabled(list.isEmpty)
                Spacer()
                Button("Set Album…") { showBulk = true }
                    .fontWeight(.semibold)
                    .disabled(selection.isEmpty)
            }
        }
        .sheet(isPresented: $showBulk) {
            BulkAlbumSheet(ids: Array(selection)) { selection.removeAll() }
        }
    }
}
