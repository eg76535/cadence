import SwiftUI

struct AlbumDetailView: View {
    @Environment(Library.self) private var library
    @Environment(PlayerEngine.self) private var player
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openSheet) private var openSheet

    let album: Album

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                VStack(spacing: 8) {
                    AlbumArt(albumID: album.id, title: album.title, size: .mid)
                        .frame(width: 190, height: 190)
                        .padding(.top, 28)
                    Text(album.title)
                        .font(Theme.mono(17, .bold))
                        .foregroundStyle(Theme.fg)
                        .multilineTextAlignment(.center)
                        .padding(.top, 10)
                    Text(album.artist)
                        .font(Theme.mono(12))
                        .foregroundStyle(Theme.dim)
                    Text("\(album.tracks.count) TRK · \(formatTime(album.duration))")
                        .font(Theme.mono(11))
                        .foregroundStyle(Theme.dim)

                    HStack(spacing: 28) {
                        Button {
                            player.play(album.tracks, startAt: 0, shuffled: false)
                        } label: {
                            Text("PLAY")
                                .font(Theme.mono(13, .bold))
                                .foregroundStyle(Theme.accent)
                        }
                        Button {
                            player.play(album.tracks, shuffled: true)
                        } label: {
                            Text("SHUFFLE")
                                .font(Theme.mono(13, .bold))
                                .foregroundStyle(Theme.fg)
                        }
                        Button {
                            dismiss()
                            openSheet(.editAlbum(album))
                        } label: {
                            Text("EDIT")
                                .font(Theme.mono(13, .bold))
                                .foregroundStyle(Theme.dim)
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 10)
                    .padding(.bottom, 22)
                }
                .padding(.horizontal, 24)

                Hairline()

                ForEach(Array(album.tracks.enumerated()), id: \.element.id) { i, track in
                    Button {
                        player.play(album.tracks, startAt: i)
                    } label: {
                        HStack(spacing: 14) {
                            Text(String(format: "%02d", i + 1))
                                .font(Theme.mono(11))
                                .foregroundStyle(Theme.dim)
                                .frame(width: 24, alignment: .leading)
                            Text(track.title)
                                .font(Theme.mono(14))
                                .foregroundStyle(player.current?.id == track.id ? Theme.accent : Theme.fg)
                                .lineLimit(1)
                            Spacer()
                            Text(formatTime(track.duration))
                                .font(Theme.mono(11))
                                .foregroundStyle(Theme.dim)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Hairline().padding(.leading, 58)
                }
            }
        }
    }
}
