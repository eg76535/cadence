import SwiftUI

// MARK: - Мини-плеер

/// Плашка над вкладками. Тап или свайп вверх открывает плеер, свайп влево/вправо листает треки.
@MainActor
struct ModernMini: View {
    @Environment(PlayerEngine.self) private var player
    private let store = ThemeStore.shared

    var onOpen: () -> Void
    @State private var dx: CGFloat = 0

    var body: some View {
        let s = store.spec
        let shape = RoundedRectangle(cornerRadius: Theme.cardRadius + 4, style: .continuous)
        HStack(spacing: 12) {
            AlbumArt(
                albumID: player.current?.albumID ?? "",
                title: player.current?.album ?? "",
                size: .thumb,
                radius: 8
            )
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 1) {
                Text(player.current?.title ?? "")
                    .font(Theme.font(15, .semibold))
                    .foregroundStyle(Theme.fg)
                    .lineLimit(1)
                Text(player.current?.artist ?? "")
                    .font(Theme.font(13))
                    .foregroundStyle(Theme.dim)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)

            Button {
                Haptics.tap()
                player.toggle()
            } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 22))
                    .contentTransition(.symbolEffect(.replace))
                    .foregroundStyle(Theme.fg)
                    .frame(width: 40, height: 44)
            }
            .buttonStyle(.plain)

            Button {
                Haptics.tap()
                player.next()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 19))
                    .foregroundStyle(Theme.fg)
                    .frame(width: 36, height: 44)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background {
            ZStack {
                if s.glass {
                    shape.fill(.regularMaterial)
                } else {
                    shape.fill(Theme.cardStrong)
                }
                // тонкая полоска прогресса снизу
                GeometryReader { geo in
                    VStack {
                        Spacer(minLength: 0)
                        HStack(spacing: 0) {
                            Rectangle()
                                .fill(Theme.accent.opacity(0.9))
                                .frame(width: geo.size.width * player.progress, height: 2)
                            Spacer(minLength: 0)
                        }
                    }
                }
                .clipShape(shape)
            }
        }
        .overlay(shape.strokeBorder(Theme.fg.opacity(0.07), lineWidth: 0.5))
        .contentShape(shape)
        .offset(x: dx)
        .onTapGesture(perform: onOpen)
        .gesture(
            DragGesture(minimumDistance: 14)
                .onChanged { v in
                    if abs(v.translation.width) > abs(v.translation.height) {
                        dx = v.translation.width / 3
                    }
                }
                .onEnded { v in
                    let w = v.translation.width
                    let h = v.translation.height
                    if abs(h) > abs(w), h < -24 {
                        onOpen()
                    } else if w < -60 {
                        Haptics.select()
                        player.next()
                    } else if w > 60 {
                        Haptics.select()
                        player.previous()
                    }
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { dx = 0 }
                }
        )
    }
}

// MARK: - Ползунок

struct ModernScrubber: View {
    let value: Double   // 0...1
    var onSeek: (Double) -> Void
    @State private var dragging: Double?

    var body: some View {
        GeometryReader { geo in
            let w = max(geo.size.width, 1)
            let p = dragging ?? value
            let h: CGFloat = dragging == nil ? 6 : 12
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.fg.opacity(0.22))
                    .frame(height: h)
                Capsule()
                    .fill(Theme.fg.opacity(0.92))
                    .frame(width: max(w * p, h), height: h)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        dragging = min(max(g.location.x / w, 0), 1)
                    }
                    .onEnded { g in
                        onSeek(min(max(g.location.x / w, 0), 1))
                        dragging = nil
                    }
            )
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: dragging == nil)
        }
        .frame(height: 26)
    }
}

// MARK: - Экран плеера

/// Полноэкранный плеер. Закрывается свайпом вниз, обложка листает треки свайпом вбок,
/// обложка «дышит» при паузе, фон подкрашивается под обложку.
@MainActor
struct ModernNowPlaying: View {
    @Environment(Library.self) private var library
    @Environment(PlayerEngine.self) private var player
    @Environment(TasteStore.self) private var taste
    @Environment(\.openSheet) private var openSheet
    private let store = ThemeStore.shared

    var onClose: () -> Void

    @State private var dragY: CGFloat = 0
    @State private var artDX: CGFloat = 0
    @State private var tint: Color?
    @State private var showQueue = false

    var body: some View {
        let s = store.spec
        GeometryReader { geo in
            let insets = geo.safeAreaInsets
            let window = SafeInsets.window
            let top = max(insets.top, window.top)
            let bottom = max(insets.bottom, window.bottom)
            let left = max(insets.leading, window.left)
            let right = max(insets.trailing, window.right)
            let landscape = geo.size.width > geo.size.height

            ZStack {
                backdrop(s)

                Group {
                    if landscape {
                        landscapeLayout(geo.size)
                    } else {
                        portraitLayout(geo.size)
                    }
                }
                .padding(.top, top)
                .padding(.bottom, max(bottom, 12))
                .padding(.leading, left)
                .padding(.trailing, right)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipShape(RoundedRectangle(cornerRadius: dragY > 2 ? 30 : 0, style: .continuous))
            .scaleEffect(1 - min(dragY / 1800, 0.07), anchor: .top)
            .offset(y: dragY)
            .gesture(dragGesture(height: geo.size.height))
        }
        .ignoresSafeArea()
        .task(id: player.current?.albumID ?? "") { await updateTint() }
        .sheet(isPresented: $showQueue) {
            QueueSheet()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(Theme.bg)
        }
    }

    // MARK: фон

    private func backdrop(_ s: ThemeSpec) -> some View {
        ZStack {
            WallView(cover: s.wall == .cover ? player.cover : nil)
            LinearGradient(
                colors: [(tint ?? Theme.accent).opacity(s.isLight ? 0.45 : 0.6), Color.clear],
                startPoint: .top,
                endPoint: UnitPoint(x: 0.5, y: 0.85)
            )
            .animation(.easeInOut(duration: 0.7), value: tint)
        }
        .ignoresSafeArea()
    }

    private func updateTint() async {
        guard let id = player.current?.albumID else {
            tint = nil
            return
        }
        if let img = await library.covers.load(id, .thumb), let ui = img.averageColor {
            tint = Color(uiColor: ui)
        } else {
            tint = nil
        }
    }

    // MARK: раскладки

    private func portraitLayout(_ size: CGSize) -> some View {
        let side = max(min(size.width - 56, size.height * 0.44), 120)
        return VStack(spacing: 0) {
            topBar
                .padding(.horizontal, 20)

            Spacer(minLength: 10)

            artwork(side)

            Spacer(minLength: 18)

            titleRow
                .padding(.horizontal, 30)

            scrubBlock
                .padding(.horizontal, 30)
                .padding(.top, 14)

            transport
                .padding(.top, 10)

            Spacer(minLength: 10)

            bottomRow
                .padding(.horizontal, 36)
                .padding(.bottom, 6)
        }
    }

    private func landscapeLayout(_ size: CGSize) -> some View {
        let side = max(min(size.height - 70, 300), 110)
        return VStack(spacing: 0) {
            topBar
                .padding(.horizontal, 24)
            HStack(spacing: 34) {
                artwork(side)
                VStack(spacing: 8) {
                    titleRow
                    scrubBlock
                    transport
                    bottomRow
                }
                .frame(maxWidth: 430)
            }
            .padding(.horizontal, 24)
            .frame(maxHeight: .infinity)
        }
    }

    // MARK: части

    private var topBar: some View {
        VStack(spacing: 6) {
            Capsule()
                .fill(Theme.fg.opacity(0.35))
                .frame(width: 38, height: 5)
                .padding(.top, 6)
            HStack {
                Button {
                    Haptics.tap()
                    onClose()
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.fg)
                        .frame(width: 44, height: 36, alignment: .leading)
                }
                .buttonStyle(.plain)
                Spacer()
                Text(player.waveTitle.map { "Wave · \($0)" } ?? "Now Playing")
                    .font(Theme.font(13, .semibold))
                    .foregroundStyle(player.waveTitle == nil ? Theme.dim : Theme.accent)
                    .lineLimit(1)
                Spacer()
                Color.clear.frame(width: 44, height: 36)
            }
        }
    }

    private func artwork(_ side: CGFloat) -> some View {
        AlbumArt(
            albumID: player.current?.albumID ?? "",
            title: player.current?.album ?? "",
            size: .full,
            radius: max(Theme.coverRadius, 10)
        )
        .frame(width: side, height: side)
        .shadow(color: Color.black.opacity(player.isPlaying ? 0.5 : 0.25), radius: player.isPlaying ? 26 : 12, y: player.isPlaying ? 16 : 6)
        .scaleEffect(player.isPlaying ? 1 : 0.84)
        .offset(x: artDX)
        .animation(.spring(response: 0.5, dampingFraction: 0.72), value: player.isPlaying)
    }

    private var titleRow: some View {
        let liked = player.current.map { taste.isLiked($0.id) } ?? false
        return HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(player.current?.title ?? "—")
                    .font(Theme.font(22, .bold))
                    .foregroundStyle(Theme.fg)
                    .lineLimit(2)
                Text(player.current?.artist ?? "")
                    .font(Theme.font(18))
                    .foregroundStyle(Theme.fg.opacity(0.7))
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Button {
                if let id = player.current?.id {
                    Haptics.tap()
                    taste.toggleLike(id)
                }
            } label: {
                Image(systemName: liked ? "heart.fill" : "heart")
                    .font(.system(size: 22))
                    .foregroundStyle(liked ? Theme.accent : Theme.fg)
                    .frame(width: 40, height: 40)
                    .background(Theme.fg.opacity(0.12), in: Circle())
                    .scaleEffect(liked ? 1.06 : 1)
                    .animation(.spring(response: 0.3, dampingFraction: 0.5), value: liked)
            }
            .buttonStyle(.plain)

            Menu {
                if let t = player.current {
                    Button("Edit Info…", systemImage: "pencil") { openSheet(.editTrack(t)) }
                    Button("Play Next", systemImage: "text.insert") { player.playNext(t) }
                }
                Menu("Sleep Timer", systemImage: "moon.zzz") {
                    Button("15 min") { player.setSleep(minutes: 15) }
                    Button("30 min") { player.setSleep(minutes: 30) }
                    Button("60 min") { player.setSleep(minutes: 60) }
                    if player.sleepDeadline != nil {
                        Button("Off", role: .destructive) { player.setSleep(minutes: nil) }
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.fg)
                    .frame(width: 40, height: 40)
                    .background(Theme.fg.opacity(0.12), in: Circle())
            }
        }
    }

    private var scrubBlock: some View {
        VStack(spacing: 2) {
            ModernScrubber(value: player.progress) { f in
                player.seek(to: f * player.duration)
            }
            HStack {
                Text(formatTime(player.currentTime))
                Spacer()
                Text("-" + formatTime(max(player.duration - player.currentTime, 0)))
            }
            .font(Theme.font(12))
            .monospacedDigit()
            .foregroundStyle(Theme.fg.opacity(0.6))
        }
    }

    private var transport: some View {
        HStack(spacing: 50) {
            Button {
                Haptics.tap()
                player.previous()
            } label: {
                Image(systemName: "backward.fill").font(.system(size: 32))
            }
            Button {
                Haptics.soft()
                player.toggle()
            } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 46))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 60)
            }
            Button {
                Haptics.tap()
                player.next()
            } label: {
                Image(systemName: "forward.fill").font(.system(size: 32))
            }
        }
        .foregroundStyle(Theme.fg)
        .buttonStyle(PressScaleStyle(scale: 0.88))
        .frame(height: 70)
    }

    private var bottomRow: some View {
        HStack {
            toggleButton(icon: "shuffle", on: player.shuffle) {
                player.shuffle.toggle()
            }
            Spacer()
            toggleButton(icon: player.repeatMode == .one ? "repeat.1" : "repeat", on: player.repeatMode != .off) {
                player.cycleRepeat()
            }
            Spacer()
            toggleButton(icon: "moon.zzz", on: player.sleepDeadline != nil) {
                if player.sleepDeadline != nil {
                    player.setSleep(minutes: nil)
                } else {
                    player.setSleep(minutes: 30)
                }
            }
            Spacer()
            toggleButton(icon: "list.bullet", on: false) {
                showQueue = true
            }
        }
    }

    private func toggleButton(icon: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(on ? Theme.accent : Theme.fg.opacity(0.7))
                .frame(width: 46, height: 40)
                .background(on ? Theme.accent.opacity(0.16) : Color.clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(PressScaleStyle(scale: 0.9))
    }

    // MARK: жесты

    private func dragGesture(height: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 14)
            .onChanged { v in
                let w = v.translation.width
                let h = v.translation.height
                if abs(h) >= abs(w) {
                    if h > 0 { dragY = h }
                } else if v.startLocation.y < height * 0.6 {
                    artDX = w / 2.5
                }
            }
            .onEnded { v in
                let w = v.translation.width
                let h = v.translation.height
                if abs(h) >= abs(w) {
                    if h > 130 || v.predictedEndTranslation.height > 380 {
                        onClose()
                        return
                    }
                } else if v.startLocation.y < height * 0.6 {
                    if w < -80 {
                        Haptics.select()
                        player.next()
                    } else if w > 80 {
                        Haptics.select()
                        player.previous()
                    }
                }
                withAnimation(.spring(response: 0.38, dampingFraction: 0.8)) {
                    dragY = 0
                    artDX = 0
                }
            }
    }
}

// MARK: - Очередь

@MainActor
struct QueueSheet: View {
    @Environment(PlayerEngine.self) private var player
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let upcoming = Array(player.queue.enumerated()).filter { $0.offset >= player.index }
        VStack(spacing: 0) {
            HStack {
                Text("Up Next")
                    .font(Theme.font(20, .bold))
                    .foregroundStyle(Theme.fg)
                Spacer()
                Button("Done") { dismiss() }
                    .font(Theme.font(16, .semibold))
                    .foregroundStyle(Theme.accent)
            }
            .padding(.horizontal, 20)
            .padding(.top, 22)
            .padding(.bottom, 10)

            List {
                ForEach(upcoming, id: \.element.id) { item in
                    Button {
                        Haptics.tap()
                        player.jump(to: item.offset)
                    } label: {
                        HStack(spacing: 12) {
                            AlbumArt(albumID: item.element.albumID, title: item.element.album, size: .thumb, radius: 6)
                                .frame(width: 40, height: 40)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.element.title)
                                    .font(Theme.font(15, item.offset == player.index ? .semibold : .regular))
                                    .foregroundStyle(item.offset == player.index ? Theme.accent : Theme.fg)
                                    .lineLimit(1)
                                Text(item.element.artist)
                                    .font(Theme.font(13))
                                    .foregroundStyle(Theme.dim)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Text(formatTime(item.element.duration))
                                .font(Theme.font(12))
                                .foregroundStyle(Theme.dim)
                                .monospacedDigit()
                        }
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.clear)
                    .listRowSeparatorTint(Theme.line.opacity(0.5))
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .background(Theme.bg)
    }
}
