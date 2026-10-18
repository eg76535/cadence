import SwiftUI

/// Cover Flow. Все параметры (наклон, отступы, перекрытие, размеры для портрета
/// и альбомной) берутся из активной темы, см. ThemeSpec.
struct CoverFlowView: View {
    @Environment(Library.self) private var library
    @Environment(PlayerEngine.self) private var player
    private let store = ThemeStore.shared

    let albums: [Album]
    @Binding var selectedID: String?
    var landscape: Bool = false
    var onOpen: (Album) -> Void

    private var selectedIndex: Int {
        albums.firstIndex(where: { $0.id == selectedID }) ?? 0
    }

    var body: some View {
        let s = store.spec
        GeometryReader { geo in
            let width: CGFloat = geo.size.width
            let height: CGFloat = geo.size.height
            let infoH: CGFloat = landscape ? 44 : 104
            let landSize: CGFloat = (height - infoH - 20) / 1.4 * CGFloat(s.coverL)
            let size: CGFloat = landscape ? min(max(landSize, 70), 300) : min(width * CGFloat(s.cover), 250)
            let overlap: CGFloat = CGFloat(landscape ? s.overlapL : s.overlap)
            let spread: CGFloat = CGFloat(landscape ? s.spreadL : s.spread)
            let side: CGFloat = (width - size) / 2
            let pitch: CGFloat = max(24, size * (1 - overlap))
            let k: CGFloat = max(1, width / 2 / pitch)
            let angle: Double = s.angle * (s.flip ? -1 : 1)
            let sideScale: CGFloat = CGFloat(s.sideScale)
            let refl: Double = s.refl

            VStack(spacing: 0) {
                if s.align != .top {
                    Spacer(minLength: 0)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: -size * overlap) {
                        ForEach(Array(albums.enumerated()), id: \.element.id) { i, album in
                            CoverTile(
                                image: library.covers[album.id],
                                title: album.title,
                                size: size,
                                reflection: refl
                            )
                            .id(album.id)
                            .zIndex(Double(-abs(i - selectedIndex)))
                            .scrollTransition(.interactive, axis: .horizontal) { content, phase in
                                let c: CGFloat = min(max(CGFloat(phase.value) * k, -1), 1)
                                return content
                                    .rotation3DEffect(
                                        .degrees(Double(-c) * angle),
                                        axis: (x: 0, y: 1, z: 0),
                                        perspective: 0.6
                                    )
                                    .scaleEffect(1 - (1 - sideScale) * abs(c))
                                    .offset(x: c * size * spread)
                            }
                            .onTapGesture {
                                if album.id == selectedID {
                                    onOpen(album)
                                } else {
                                    withAnimation(.snappy) { selectedID = album.id }
                                }
                            }
                        }
                    }
                    .scrollTargetLayout()
                }
                .contentMargins(.horizontal, side, for: .scrollContent)
                .scrollTargetBehavior(.viewAligned)
                .scrollPosition(id: $selectedID, anchor: .center)
                .scrollClipDisabled()
                .frame(height: size * 1.4)

                info
                    .padding(.top, landscape ? 4 : 8)

                if s.align != .low {
                    Spacer(minLength: 0)
                }
            }
        }
        .sensoryFeedback(.selection, trigger: selectedID)
        .onAppear { fixSelection() }
        .onChange(of: albums) { _, _ in fixSelection() }
    }

    @ViewBuilder
    private var info: some View {
        if albums.indices.contains(selectedIndex) {
            let album = albums[selectedIndex]
            let counter = String(format: "%02d / %02d", selectedIndex + 1, albums.count)
            if landscape {
                HStack(spacing: 16) {
                    Text(album.title)
                        .font(Theme.mono(14, .bold))
                        .foregroundStyle(Theme.fg)
                        .lineLimit(1)
                    Text(album.artist)
                        .font(Theme.mono(12))
                        .foregroundStyle(Theme.dim)
                        .lineLimit(1)
                    Text(counter)
                        .font(Theme.mono(11))
                        .foregroundStyle(Theme.dim)
                    playButton(album)
                }
                .padding(.horizontal, 60)
            } else {
                VStack(spacing: 6) {
                    Text(album.title)
                        .font(Theme.mono(15, .bold))
                        .foregroundStyle(Theme.fg)
                        .lineLimit(1)
                    Text(album.artist)
                        .font(Theme.mono(12))
                        .foregroundStyle(Theme.dim)
                        .lineLimit(1)
                    Text(counter)
                        .font(Theme.mono(11))
                        .foregroundStyle(Theme.dim)
                    playButton(album)
                }
                .padding(.horizontal, 24)
            }
        }
    }

    private func playButton(_ album: Album) -> some View {
        Button {
            player.play(album.tracks, startAt: 0)
        } label: {
            Text("PLAY")
                .font(Theme.mono(12, .bold))
                .foregroundStyle(Theme.accent)
                .padding(.vertical, landscape ? 4 : 8)
                .padding(.horizontal, 18)
        }
        .buttonStyle(.plain)
    }

    private func fixSelection() {
        if selectedID == nil || !albums.contains(where: { $0.id == selectedID }) {
            selectedID = albums.first?.id
        }
    }
}

/// Обложка + зеркальное отражение снизу
struct CoverTile: View {
    let image: UIImage?
    let title: String
    let size: CGFloat
    var reflection: Double = 0.35

    var body: some View {
        VStack(spacing: 2) {
            CoverImage(image: image, title: title, size: size)

            CoverImage(image: image, title: title, size: size)
                .scaleEffect(x: 1, y: -1)
                .frame(height: size * 0.35, alignment: .top)
                .clipped()
                .mask(
                    LinearGradient(
                        colors: [Color.white.opacity(reflection), Color.clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        }
        .frame(width: size)
    }
}
