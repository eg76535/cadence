import SwiftUI

/// Корень приложения: выбирает привычный (modern) или классический (Rockbox) интерфейс по теме,
/// держит шиты (настройки, редактор тем, правка тегов) и жизненный цикл.
@MainActor
struct RootView: View {
    @Environment(Library.self) private var library
    @Environment(PlayerEngine.self) private var player
    @Environment(TasteStore.self) private var taste
    @Environment(TagStore.self) private var tags
    @Environment(\.scenePhase) private var scenePhase
    private let store = ThemeStore.shared

    @State private var sheet: AppSheet?

    var body: some View {
        let s = store.spec
        Group {
            if s.modern {
                ModernRootView()
            } else {
                ClassicRootView()
            }
        }
        .environment(\.openSheet, { next in present(next) })
        .tint(Theme.accent)
        .preferredColorScheme(s.isLight ? .light : .dark)
        .sheet(item: $sheet) { item in
            sheetContent(item)
        }
        .task { await library.bootstrapIfNeeded() }
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .background {
                taste.saveNow()
                tags.saveNow()
                return
            }
            guard phase == .active else { return }
            player.library = library
            player.taste = taste
            store.reload()
        }
    }

    /// Если уже открыт другой шит, сначала закрываем его: два шита подряд SwiftUI меняет криво.
    private func present(_ next: AppSheet) {
        if sheet == nil {
            sheet = next
            return
        }
        sheet = nil
        Task {
            try? await Task.sleep(nanoseconds: 450_000_000)
            sheet = next
        }
    }

    @ViewBuilder
    private func sheetContent(_ item: AppSheet) -> some View {
        switch item {
        case .settings:
            SettingsView()
                .presentationBackground(Theme.bg)
        case .themeEditor:
            ThemeEditorView()
                .presentationDetents([.fraction(0.5), .large])
                .presentationBackgroundInteraction(.enabled(upThrough: .fraction(0.5)))
                .presentationDragIndicator(.visible)
                .presentationBackground(Theme.bg)
        case .classicThemes:
            ThemesView()
                .presentationBackground(Theme.bg)
        case .editTrack(let track):
            TrackEditSheet(track: track)
                .presentationBackground(Theme.bg)
        case .editAlbum(let album):
            AlbumEditSheet(album: album)
                .presentationBackground(Theme.bg)
        }
    }
}

/// Старый вид: Rockbox / iPod, моноширинный шрифт, вкладки текстом.
struct ClassicRootView: View {
    @Environment(Library.self) private var library
    @Environment(PlayerEngine.self) private var player
    @Environment(\.openSheet) private var openSheet
    private let store = ThemeStore.shared

    enum Screen: String, CaseIterable {
        case flow = "FLOW"
        case albums = "ALBUMS"
        case songs = "SONGS"
        case wave = "WAVE"
    }

    @State private var tab: Screen = .flow
    @State private var detail: Album?
    @State private var showNowPlaying = false
    @State private var flowSelection: String?

    var body: some View {
        let s = store.spec
        GeometryReader { geo in
            let landscape = geo.size.width > geo.size.height
            ZStack {
                WallView(cover: wallCover)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    header(s, landscape: landscape)
                    if s.tabs == .top {
                        tabBar(s)
                    }
                    content(landscape: landscape)
                    footer(s, landscape: landscape)
                }
            }
        }
        .sheet(item: $detail) { album in
            AlbumDetailView(album: album)
                .presentationBackground(s.glass ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(Theme.bg))
        }
        .fullScreenCover(isPresented: $showNowPlaying) {
            NowPlayingView()
        }
    }

    private var wallCover: UIImage? {
        if let id = flowSelection, let img = library.covers[id] { return img }
        return player.cover
    }

    // MARK: header

    private func header(_ s: ThemeSpec, landscape: Bool) -> some View {
        HStack {
            if s.hdr {
                Text("CADENCE")
                    .font(Theme.mono(12, .bold))
                    .foregroundStyle(Theme.dim)
                Spacer()
                Text("\(library.albums.count) ALB · \(library.tracks.count) TRK")
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.dim)
            } else {
                Spacer()
            }
            Button {
                openSheet(.settings)
            } label: {
                Text("SETTINGS")
                    .font(Theme.mono(11, .bold))
                    .foregroundStyle(Theme.accent)
                    .padding(.leading, 14)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
            Button {
                openSheet(.classicThemes)
            } label: {
                Text("THEME")
                    .font(Theme.mono(11, .bold))
                    .foregroundStyle(Theme.accent)
                    .padding(.leading, 14)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, landscape ? 4 : 10)
    }

    // MARK: content

    @ViewBuilder
    private func content(landscape: Bool) -> some View {
        if library.albums.isEmpty {
            EmptyStateView()
        } else {
            switch tab {
            case .flow:
                CoverFlowView(albums: library.albums, selectedID: $flowSelection, landscape: landscape) { detail = $0 }
                    .ignoresSafeArea(.container, edges: .horizontal)
            case .albums:
                AlbumListView(albums: library.albums) { detail = $0 }
            case .songs:
                SongListView()
            case .wave:
                DiscoverView { detail = $0 }
            }
        }
    }

    // MARK: footer (мини-плеер + вкладки)

    @ViewBuilder
    private func footer(_ s: ThemeSpec, landscape: Bool) -> some View {
        let floatingMini = s.mini == .float
        let dock = s.tabs == .dock
        let inset: CGFloat = (floatingMini || dock) ? 14 : 0
        if landscape {
            HStack(spacing: 10) {
                if player.current != nil {
                    MiniPlayerView(floating: floatingMini) { showNowPlaying = true }
                } else {
                    Spacer(minLength: 0)
                }
                if s.tabs != .top {
                    tabBar(s)
                        .frame(width: 300)
                }
            }
            .padding(.horizontal, inset)
            .padding(.bottom, dock ? 4 : 0)
        } else {
            VStack(spacing: (floatingMini || dock) ? 8 : 0) {
                if player.current != nil {
                    MiniPlayerView(floating: floatingMini) { showNowPlaying = true }
                }
                if s.tabs != .top {
                    tabBar(s)
                }
            }
            .padding(.horizontal, inset)
            .padding(.bottom, dock ? 6 : 0)
        }
    }

    private func tabBar(_ s: ThemeSpec) -> some View {
        let floating = s.tabs == .dock
        let plainBar = !floating && !s.glass
        return VStack(spacing: 0) {
            if plainBar && s.tabs == .bar {
                Hairline()
            }
            HStack(spacing: 0) {
                ForEach(Screen.allCases, id: \.self) { t in
                    Button {
                        tab = t
                    } label: {
                        VStack(spacing: 6) {
                            Rectangle()
                                .fill(tab == t ? Theme.accent : Color.clear)
                                .frame(width: 18, height: 2)
                            Text(t.rawValue)
                                .font(Theme.mono(12, .bold))
                                .foregroundStyle(tab == t ? Theme.fg : Theme.dim)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)
                        .padding(.bottom, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            if plainBar && s.tabs == .top {
                Hairline()
            }
        }
        .panelStyle(floating: floating)
    }
}
