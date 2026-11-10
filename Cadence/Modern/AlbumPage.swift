import SwiftUI

/// Страница альбома: большая обложка, кнопки Play / Shuffle, список треков.
/// Назад: стрелка или свайп от левого края.
@MainActor
struct AlbumPage: View {
    @Environment(Library.self) private var library
    @Environment(PlayerEngine.self) private var player
    @Environment(TasteStore.self) private var taste
    @Environment(\.openSheet) private var openSheet

    let album: Album
    var onBack: () -> Void

    @State private var dragX: CGFloat = 0

    var body: some View {
        let playingID = player.current?.id
        let multiDisc = Set(album.tracks.map { $0.disc }).filter { $0 > 0 }.count > 1
        let variousArtists = album.artist == "Various Artists"

        GeometryReader { geo in
            let art = min(geo.size.width - 80, 300)
            ZStack(alignment: .topLeading) {
                Theme.bg.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 0) {
                        AlbumArt(albumID: album.id, title: album.title, size: .full)
                            .frame(width: art, height: art)
                            .shadow(color: Color.black.opacity(Theme.isLight ? 0.18 : 0.5), radius: 22, y: 12)
                            .padding(.top, 56)

                        Text(album.title)
                            .font(Theme.font(22, .bold))
                            .foregroundStyle(Theme.fg)
                            .multilineTextAlignment(.center)
                            .padding(.top, 20)
                            .padding(.horizontal, 24)

                        Text(album.artist)
                            .font(Theme.font(18))
                            .foregroundStyle(Theme.accent)
                            .padding(.top, 2)

                        Text(meta)
                            .font(Theme.font(13))
                            .foregroundStyle(Theme.dim)
                            .padding(.top, 4)

                        HStack(spacing: 12) {
                            bigButton("Play", icon: "play.fill", filled: true) {
                                player.play(album.tracks, startAt: 0, shuffled: false)
                            }
                            bigButton("Shuffle", icon: "shuffle", filled: false) {
                                player.play(album.tracks, startAt: 0, shuffled: true)
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 18)
                        .padding(.bottom, 14)

                        LazyVStack(spacing: 0) {
                            ForEach(Array(album.tracks.enumerated()), id: \.element.id) { i, track in
                                if multiDisc, i == 0 || album.tracks[i - 1].disc != track.disc {
                                    Text("Disc \(max(track.disc, 1))")
                                        .font(Theme.font(13, .semibold))
                                        .foregroundStyle(Theme.dim)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal, 20)
                                        .padding(.top, 14)
                                        .padding(.bottom, 4)
                                }
                                trackRow(track, index: i, playing: track.id == playingID, showArtist: variousArtists)
                                Rectangle()
                                    .fill(Theme.line.opacity(0.5))
                                    .frame(height: 0.5)
                                    .padding(.leading, 56)
                            }
                        }

                        Text("\(album.tracks.count) songs, \(durationText(album.duration))")
                            .font(Theme.font(12))
                            .foregroundStyle(Theme.dim)
                            .padding(.vertical, 22)
                    }
                    .frame(maxWidth: .infinity)
                }

                topButtons
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .offset(x: dragX)
        .shadow(color: Color.black.opacity(dragX > 0 ? 0.3 : 0), radius: 14)
        .simultaneousGesture(edgeSwipe)
    }

    // MARK: части

    private var meta: String {
        var parts: [String] = []
        if album.year > 0 { parts.append(String(album.year)) }
        if let genre = album.tracks.first(where: { !$0.genre.isEmpty })?.genre { parts.append(genre) }
        return parts.joined(separator: " · ")
    }

    private var topButtons: some View {
        HStack {
            Button {
                Haptics.tap()
                onBack()
            } label: {
                RoundIcon(systemName: "chevron.left")
            }
            .buttonStyle(PressScaleStyle(scale: 0.9))
            Spacer()
            Menu {
                Button("Edit Album…", systemImage: "pencil") { openSheet(.editAlbum(album)) }
                Button("Add All to Queue", systemImage: "text.append") {
                    for t in album.tracks { player.addToQueue(t) }
                }
            } label: {
                RoundIcon(systemName: "ellipsis")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private func bigButton(_ title: String, icon: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                Text(title)
            }
            .font(Theme.font(17, .semibold))
            .foregroundStyle(filled ? Theme.bg : Theme.accent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(
                filled ? Theme.accent : Theme.card,
                in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
            )
        }
        .buttonStyle(PressScaleStyle())
    }

    private func trackRow(_ track: Track, index: Int, playing: Bool, showArtist: Bool) -> some View {
        Button {
            Haptics.tap()
            player.play(album.tracks, startAt: index, shuffled: false)
        } label: {
            HStack(spacing: 0) {
                ZStack {
                    if playing {
                        Image(systemName: "waveform")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                    } else {
                        Text(track.number > 0 ? String(track.number) : String(index + 1))
                            .font(Theme.font(15))
                            .foregroundStyle(Theme.dim)
                            .monospacedDigit()
                    }
                }
                .frame(width: 36)

                VStack(alignment: .leading, spacing: 1) {
                    Text(track.title)
                        .font(Theme.font(16))
                        .foregroundStyle(playing ? Theme.accent : Theme.fg)
                        .lineLimit(1)
                    if showArtist {
                        Text(track.artist)
                            .font(Theme.font(13))
                            .foregroundStyle(Theme.dim)
                            .lineLimit(1)
                    }
                }
                .padding(.leading, 4)

                Spacer(minLength: 8)

                Text(formatTime(track.duration))
                    .font(Theme.font(13))
                    .foregroundStyle(Theme.dim)
                    .monospacedDigit()
                    .padding(.trailing, 4)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Play Next", systemImage: "text.insert") { player.playNext(track) }
            Button("Add to Queue", systemImage: "text.append") { player.addToQueue(track) }
            Button(taste.isLiked(track.id) ? "Unlike" : "Like", systemImage: taste.isLiked(track.id) ? "heart.slash" : "heart") {
                taste.toggleLike(track.id)
            }
            Button("Edit Info…", systemImage: "pencil") { openSheet(.editTrack(track)) }
        }
    }

    // MARK: свайп назад

    private var edgeSwipe: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { v in
                guard v.startLocation.x < 34, v.translation.width > 0 else { return }
                dragX = v.translation.width
            }
            .onEnded { v in
                guard v.startLocation.x < 34 else { return }
                if v.translation.width > 110 || v.predictedEndTranslation.width > 260 {
                    Haptics.tap()
                    onBack()
                } else {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { dragX = 0 }
                }
            }
    }
}
