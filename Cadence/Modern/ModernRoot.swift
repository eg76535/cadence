import SwiftUI

enum ModernTab: String, CaseIterable, Identifiable {
    case albums, songs, wave, flow

    var id: String { rawValue }

    var title: String {
        switch self {
        case .albums: return "Albums"
        case .songs: return "Songs"
        case .wave: return "Wave"
        case .flow: return "Flow"
        }
    }

    var icon: String {
        switch self {
        case .albums: return "square.grid.2x2"
        case .songs: return "music.note.list"
        case .wave: return "sparkles"
        case .flow: return "rectangle.stack"
        }
    }
}

/// Привычный интерфейс: вкладки с иконками, сетка альбомов, мини-плеер над вкладками,
/// экран плеера выезжает снизу и закрывается свайпом вниз.
@MainActor
struct ModernRootView: View {
    @Environment(Library.self) private var library
    @Environment(PlayerEngine.self) private var player
    private let store = ThemeStore.shared

    @State private var tab: ModernTab = .albums
    @State private var pushedID: String?
    @State private var showPlayer = false
    @State private var flowSelection: String?

    private var pushed: Album? {
        guard let id = pushedID else { return nil }
        return library.albums.first(where: { $0.id == id })
    }

    var body: some View {
        let s = store.spec
        GeometryReader { geo in
            let landscape = geo.size.width > geo.size.height
            ZStack {
                WallView(cover: wallCover(s))
                    .ignoresSafeArea()

                screens(landscape: landscape)
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        bottomBar(s, landscape: landscape)
                    }

                if showPlayer {
                    ModernNowPlaying(onClose: closePlayer)
                        .transition(.move(edge: .bottom))
                        .zIndex(10)
                }
            }
        }
        .environment(\.openAlbum, { album in openAlbum(album) })
    }

    // MARK: экраны

    @ViewBuilder
    private func screens(landscape: Bool) -> some View {
        ZStack {
            if library.albums.isEmpty {
                VStack(spacing: 0) {
                    ScreenHeader(title: "Cadence")
                    EmptyStateView()
                }
            } else {
                Group {
                    switch tab {
                    case .albums:
                        AlbumsScreen()
                    case .songs:
                        SongsScreen()
                    case .wave:
                        VStack(spacing: 0) {
                            ScreenHeader(title: "Wave", subtitle: "Music for your mood")
                            DiscoverView { album in openAlbum(album) }
                        }
                    case .flow:
                        VStack(spacing: 0) {
                            ScreenHeader(title: "Flow")
                            CoverFlowView(
                                albums: library.albums,
                                selectedID: $flowSelection,
                                landscape: landscape
                            ) { album in openAlbum(album) }
                        }
                    }
                }
                .transition(.opacity)

                if let album = pushed {
                    AlbumPage(album: album, onBack: popAlbum)
                        .transition(.move(edge: .trailing))
                        .zIndex(1)
                }
            }
        }
    }

    private func wallCover(_ s: ThemeSpec) -> UIImage? {
        guard s.wall == .cover else { return nil }
        if tab == .flow, let id = flowSelection, let img = library.covers.cached(id, .mid) { return img }
        return player.cover
    }

    // MARK: низ: мини-плеер + вкладки

    @ViewBuilder
    private func bottomBar(_ s: ThemeSpec, landscape: Bool) -> some View {
        Group {
            if landscape {
                HStack(spacing: 10) {
                    if player.current != nil {
                        ModernMini(onOpen: openPlayer)
                    } else {
                        Spacer(minLength: 0)
                    }
                    tabRow
                        .frame(width: 320)
                }
                .padding(.horizontal, 12)
            } else {
                VStack(spacing: 4) {
                    if player.current != nil {
                        ModernMini(onOpen: openPlayer)
                            .padding(.horizontal, 12)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    tabRow
                }
            }
        }
        .padding(.top, 8)
        .background {
            barBackground(s)
                .ignoresSafeArea(edges: .bottom)
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: player.current == nil)
    }

    @ViewBuilder
    private func barBackground(_ s: ThemeSpec) -> some View {
        ZStack(alignment: .top) {
            if s.glass {
                Rectangle().fill(.ultraThinMaterial)
            } else {
                Rectangle().fill(Theme.bg.opacity(0.96))
            }
            Rectangle()
                .fill(Theme.line.opacity(0.5))
                .frame(height: 0.5)
        }
    }

    private var tabRow: some View {
        HStack(spacing: 0) {
            ForEach(ModernTab.allCases) { t in
                Button {
                    if tab == t && pushedID == nil { return }
                    Haptics.select()
                    withAnimation(.snappy(duration: 0.28)) {
                        pushedID = nil
                        tab = t
                    }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: t.icon)
                            .font(.system(size: 21, weight: .medium))
                            .symbolVariant(tab == t ? .fill : .none)
                            .scaleEffect(tab == t ? 1.06 : 1)
                        Text(t.title)
                            .font(Theme.font(10, .medium))
                    }
                    .foregroundStyle(tab == t ? Theme.accent : Theme.dim)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
    }

    // MARK: действия

    private func openAlbum(_ album: Album) {
        Haptics.tap()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.88)) { pushedID = album.id }
    }

    private func popAlbum() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) { pushedID = nil }
    }

    private func openPlayer() {
        Haptics.soft()
        withAnimation(.spring(response: 0.45, dampingFraction: 0.88)) { showPlayer = true }
    }

    private func closePlayer() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) { showPlayer = false }
    }
}
