import SwiftUI

/// Все песни списком с буквами-разделами, поиском и свайпами.
@MainActor
struct SongsScreen: View {
    @Environment(Library.self) private var library
    @Environment(PlayerEngine.self) private var player
    @Environment(TasteStore.self) private var taste
    @Environment(\.openAlbum) private var openAlbum
    @Environment(\.openSheet) private var openSheet

    @State private var query = ""

    private struct Section: Identifiable {
        let letter: String
        let tracks: [Track]
        var id: String { letter }
    }

    private var filtered: [Track] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty { return library.tracks }
        return library.tracks.filter { textMatch(q, $0.title, $0.artist, $0.album) }
    }

    private func sections(_ list: [Track]) -> [Section] {
        var buckets: [String: [Track]] = [:]
        for t in list {
            buckets[Self.letter(t.title), default: []].append(t)
        }
        let keys = buckets.keys.sorted { a, b in
            if a == "#" { return false }
            if b == "#" { return true }
            return a < b
        }
        return keys.map { Section(letter: $0, tracks: buckets[$0] ?? []) }
    }

    private static func letter(_ title: String) -> String {
        guard let first = title.unicodeScalars.first else { return "#" }
        let ch = String(first).folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).uppercased()
        guard let c = ch.first, c.isLetter else { return "#" }
        return String(c)
    }

    var body: some View {
        let list = filtered
        let groups = sections(list)
        let playingID = player.current?.id

        VStack(spacing: 0) {
            ScreenHeader(title: "Songs", subtitle: "\(library.tracks.count) songs") {
                Button {
                    Haptics.tap()
                    player.play(list, startAt: 0, shuffled: true)
                } label: {
                    RoundIcon(systemName: "shuffle")
                }
                .buttonStyle(PressScaleStyle(scale: 0.9))
                .disabled(list.isEmpty)
            }

            SearchField(text: $query, prompt: "Search songs")
                .padding(.horizontal, 16)
                .padding(.bottom, 6)

            if list.isEmpty {
                Text("Nothing found")
                    .font(Theme.font(15))
                    .foregroundStyle(Theme.dim)
                    .padding(.top, 60)
                Spacer()
            } else {
                List {
                    ForEach(groups) { group in
                        SwiftUI.Section {
                            ForEach(group.tracks) { track in
                                row(track, playing: track.id == playingID, queue: list)
                            }
                        } header: {
                            Text(group.letter)
                                .font(Theme.font(15, .bold))
                                .foregroundStyle(Theme.accent)
                                .textCase(nil)
                        }
                        .listSectionSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .refreshable { await library.rescan() }
                .scrollDismissesKeyboard(.interactively)
            }
        }
    }

    private func row(_ track: Track, playing: Bool, queue: [Track]) -> some View {
        Button {
            Haptics.tap()
            let start = queue.firstIndex(where: { $0.id == track.id }) ?? 0
            player.play(queue, startAt: start, shuffled: false)
        } label: {
            SongRow(track: track, playing: playing)
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.clear)
        .listRowSeparatorTint(Theme.line.opacity(0.5))
        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                Haptics.success()
                player.playNext(track)
            } label: {
                Label("Play Next", systemImage: "text.insert")
            }
            .tint(Theme.accent)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button {
                Haptics.success()
                player.addToQueue(track)
            } label: {
                Label("Queue", systemImage: "text.append")
            }
            .tint(Color.blue)
        }
        .contextMenu {
            Button("Play Next", systemImage: "text.insert") { player.playNext(track) }
            Button("Add to Queue", systemImage: "text.append") { player.addToQueue(track) }
            Button(taste.isLiked(track.id) ? "Unlike" : "Like", systemImage: taste.isLiked(track.id) ? "heart.slash" : "heart") {
                taste.toggleLike(track.id)
            }
            if let album = library.albums.first(where: { $0.id == track.albumID }) {
                Button("Show Album", systemImage: "square.stack") { openAlbum(album) }
            }
            Button("Edit Info…", systemImage: "pencil") { openSheet(.editTrack(track)) }
        }
    }
}

struct SongRow: View {
    let track: Track
    let playing: Bool

    var body: some View {
        HStack(spacing: 12) {
            AlbumArt(albumID: track.albumID, title: track.album, size: .thumb, radius: 7)
                .frame(width: 46, height: 46)
                .overlay {
                    if playing {
                        ZStack {
                            RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.black.opacity(0.4))
                            Image(systemName: "waveform")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Color.white)
                        }
                    }
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(Theme.font(16, .regular))
                    .foregroundStyle(playing ? Theme.accent : Theme.fg)
                    .lineLimit(1)
                Text(track.artist + " · " + track.album)
                    .font(Theme.font(13))
                    .foregroundStyle(Theme.dim)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(formatTime(track.duration))
                .font(Theme.font(13))
                .foregroundStyle(Theme.dim)
                .monospacedDigit()
        }
        .contentShape(Rectangle())
    }
}
