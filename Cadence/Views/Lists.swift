import SwiftUI

struct AlbumListView: View {
    @Environment(Library.self) private var library

    let albums: [Album]
    var onOpen: (Album) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(albums) { album in
                    Button {
                        onOpen(album)
                    } label: {
                        HStack(spacing: 14) {
                            CoverImage(image: library.covers[album.id], title: album.title, size: 46)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(album.title)
                                    .font(Theme.mono(14, .semibold))
                                    .foregroundStyle(Theme.fg)
                                    .lineLimit(1)
                                Text(album.artist)
                                    .font(Theme.mono(11))
                                    .foregroundStyle(Theme.dim)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Text("\(album.tracks.count)")
                                .font(Theme.mono(11))
                                .foregroundStyle(Theme.dim)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Hairline().padding(.leading, 80)
                }
            }
        }
    }
}

struct SongListView: View {
    @Environment(Library.self) private var library
    @Environment(PlayerEngine.self) private var player

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(library.tracks.enumerated()), id: \.element.id) { i, track in
                    Button {
                        player.play(library.tracks, startAt: i)
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(track.title)
                                    .font(Theme.mono(14, .semibold))
                                    .foregroundStyle(player.current?.id == track.id ? Theme.accent : Theme.fg)
                                    .lineLimit(1)
                                Text("\(track.artist) — \(track.album)")
                                    .font(Theme.mono(11))
                                    .foregroundStyle(Theme.dim)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Text(formatTime(track.duration))
                                .font(Theme.mono(11))
                                .foregroundStyle(Theme.dim)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Hairline().padding(.leading, 20)
                }
            }
        }
    }
}
