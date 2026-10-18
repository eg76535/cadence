import SwiftUI

struct MiniPlayerView: View {
    @Environment(PlayerEngine.self) private var player
    var floating: Bool = false
    var onTap: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // тонкая линия прогресса
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Theme.line)
                    Rectangle().fill(Theme.accent).frame(width: geo.size.width * player.progress)
                }
            }
            .frame(height: 1)

            HStack(spacing: 12) {
                CoverImage(image: player.cover, title: player.current?.album ?? "", size: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text(player.current?.title ?? "")
                        .font(Theme.mono(13, .semibold))
                        .foregroundStyle(Theme.fg)
                        .lineLimit(1)
                    Text(player.current?.artist ?? "")
                        .font(Theme.mono(11))
                        .foregroundStyle(Theme.dim)
                        .lineLimit(1)
                }
                Spacer()
                Button {
                    player.toggle()
                } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(Theme.fg)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                Button {
                    player.next()
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Theme.fg)
                        .frame(width: 40, height: 44)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, floating ? 14 : 20)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)
        }
        .panelStyle(floating: floating)
    }
}

struct NowPlayingView: View {
    @Environment(PlayerEngine.self) private var player
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        GeometryReader { geo in
            let landscape = geo.size.width > geo.size.height
            ZStack {
                WallView(cover: player.cover)
                    .ignoresSafeArea()

                if landscape {
                    landscapeLayout(geo.size)
                } else {
                    portraitLayout(geo.size)
                }
            }
        }
        .tint(Theme.accent)
    }

    // MARK: layouts

    private func portraitLayout(_ size: CGSize) -> some View {
        let side = min(size.width - 64, size.height * 0.42)
        return VStack(spacing: 0) {
            topBar
                .padding(.horizontal, 24)

            Spacer(minLength: 8)

            CoverImage(image: player.cover, title: player.current?.album ?? "", size: side)

            Spacer(minLength: 20)

            titleBlock
                .padding(.horizontal, 32)

            Spacer(minLength: 20)

            scrubBlock
                .padding(.horizontal, 32)

            Spacer(minLength: 18)

            transport

            Spacer(minLength: 18)

            secondary

            Spacer(minLength: 16)
        }
    }

    private func landscapeLayout(_ size: CGSize) -> some View {
        let side = min(size.height - 90, 280)
        return VStack(spacing: 0) {
            topBar
                .padding(.horizontal, 24)

            HStack(spacing: 36) {
                CoverImage(image: player.cover, title: player.current?.album ?? "", size: max(side, 120))

                VStack(spacing: 12) {
                    titleBlock
                    scrubBlock
                    transport
                    secondary
                }
                .frame(maxWidth: 420)
            }
            .padding(.horizontal, 24)
            .frame(maxHeight: .infinity)
        }
    }

    // MARK: pieces

    private var topBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.fg)
                    .frame(width: 44, height: 44, alignment: .leading)
            }
            Spacer()
            Text("NOW PLAYING")
                .font(Theme.mono(11, .bold))
                .foregroundStyle(Theme.dim)
            Spacer()
            Color.clear.frame(width: 44, height: 44)
        }
    }

    private var titleBlock: some View {
        VStack(spacing: 6) {
            Text(player.current?.title ?? "—")
                .font(Theme.mono(19, .bold))
                .foregroundStyle(Theme.fg)
                .multilineTextAlignment(.center)
                .lineLimit(2)
            Text(player.current?.artist ?? "")
                .font(Theme.mono(13))
                .foregroundStyle(Theme.dim)
                .lineLimit(1)
            Text(player.current?.album ?? "")
                .font(Theme.mono(11))
                .foregroundStyle(Theme.dim)
                .lineLimit(1)
        }
    }

    private var scrubBlock: some View {
        VStack(spacing: 4) {
            Scrubber(value: player.progress) { f in
                player.seek(to: f * player.duration)
            }
            HStack {
                Text(formatTime(player.currentTime))
                Spacer()
                Text("-" + formatTime(max(player.duration - player.currentTime, 0)))
            }
            .font(Theme.mono(11))
            .foregroundStyle(Theme.dim)
        }
    }

    private var transport: some View {
        HStack(spacing: 46) {
            Button { player.previous() } label: {
                Image(systemName: "backward.fill").font(.system(size: 26))
            }
            Button { player.toggle() } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 40))
                    .frame(width: 48)
            }
            Button { player.next() } label: {
                Image(systemName: "forward.fill").font(.system(size: 26))
            }
        }
        .foregroundStyle(Theme.fg)
        .buttonStyle(.plain)
    }

    private var secondary: some View {
        HStack(spacing: 60) {
            Button { player.shuffle.toggle() } label: {
                Image(systemName: "shuffle")
                    .foregroundStyle(player.shuffle ? Theme.accent : Theme.dim)
            }
            Button { player.cycleRepeat() } label: {
                Image(systemName: player.repeatMode == .one ? "repeat.1" : "repeat")
                    .foregroundStyle(player.repeatMode == .off ? Theme.dim : Theme.accent)
            }
        }
        .font(.system(size: 18))
        .buttonStyle(.plain)
    }
}
