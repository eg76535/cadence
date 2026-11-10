import SwiftUI

enum AlbumSort: String, CaseIterable, Identifiable {
    case artist, title, year, size

    var id: String { rawValue }

    var label: String {
        switch self {
        case .artist: return "Artist"
        case .title: return "Title"
        case .year: return "Year (newest first)"
        case .size: return "Most songs"
        }
    }
}

/// Сетка альбомов в духе Apple Music.
@MainActor
struct AlbumsScreen: View {
    @Environment(Library.self) private var library
    @AppStorage("albums.sort") private var sortRaw = AlbumSort.artist.rawValue
    @State private var query = ""

    private let columns = [GridItem(.adaptive(minimum: 150, maximum: 240), spacing: 16)]

    private var sort: AlbumSort { AlbumSort(rawValue: sortRaw) ?? .artist }

    private var shown: [Album] {
        var list = library.albums
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !q.isEmpty {
            list = list.filter { textMatch(q, $0.title, $0.artist) }
        }
        switch sort {
        case .artist:
            break   // библиотека уже отсортирована по исполнителю и названию
        case .title:
            list.sort { $0.title.lowercased() < $1.title.lowercased() }
        case .year:
            list.sort { ($0.year, $1.title.lowercased()) > ($1.year, $0.title.lowercased()) }
        case .size:
            list.sort { $0.tracks.count > $1.tracks.count }
        }
        return list
    }

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: "Albums", subtitle: "\(library.albums.count) albums · \(library.tracks.count) songs") {
                Menu {
                    Picker("Sort", selection: $sortRaw) {
                        ForEach(AlbumSort.allCases) { option in
                            Text(option.label).tag(option.rawValue)
                        }
                    }
                } label: {
                    RoundIcon(systemName: "arrow.up.arrow.down")
                }
            }

            SearchField(text: $query, prompt: "Search albums")
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

            ScrollView {
                if shown.isEmpty {
                    Text("Nothing found")
                        .font(Theme.font(15))
                        .foregroundStyle(Theme.dim)
                        .padding(.top, 60)
                } else {
                    LazyVGrid(columns: columns, spacing: 22) {
                        ForEach(shown) { album in
                            AlbumCell(album: album)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 20)
                }
            }
            .refreshable { await library.rescan() }
            .scrollDismissesKeyboard(.interactively)
        }
    }
}

private struct AlbumCell: View {
    @Environment(PlayerEngine.self) private var player
    @Environment(\.openAlbum) private var openAlbum
    @Environment(\.openSheet) private var openSheet

    let album: Album

    var body: some View {
        Button {
            openAlbum(album)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                AlbumArt(albumID: album.id, title: album.title, size: .mid)
                    .shadow(color: Color.black.opacity(Theme.isLight ? 0.12 : 0.38), radius: 8, y: 4)
                VStack(alignment: .leading, spacing: 1) {
                    Text(album.title)
                        .font(Theme.font(14, .semibold))
                        .foregroundStyle(Theme.fg)
                        .lineLimit(1)
                    Text(album.artist)
                        .font(Theme.font(13))
                        .foregroundStyle(Theme.dim)
                        .lineLimit(1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle())
        .contextMenu {
            Button("Play", systemImage: "play.fill") {
                player.play(album.tracks, startAt: 0, shuffled: false)
            }
            Button("Shuffle", systemImage: "shuffle") {
                player.play(album.tracks, startAt: 0, shuffled: true)
            }
            Button("Edit Album…", systemImage: "pencil") {
                openSheet(.editAlbum(album))
            }
        }
    }
}
