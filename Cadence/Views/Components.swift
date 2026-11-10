import SwiftUI

struct CoverImage: View {
    let image: UIImage?
    let title: String
    let size: CGFloat

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                CoverPlaceholder(title: title, side: size)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: Theme.coverRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.coverRadius, style: .continuous)
                .strokeBorder(Theme.fg.opacity(0.08), lineWidth: 1)
        )
    }
}

/// Заглушка, когда у альбома нет обложки: нота (modern) или первая буква (classic).
struct CoverPlaceholder: View {
    let title: String
    let side: CGFloat

    var body: some View {
        ZStack {
            if Theme.modern {
                LinearGradient(
                    colors: [Theme.cardStrong, Theme.card],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Image(systemName: "music.note")
                    .font(.system(size: side * 0.34, weight: .semibold))
                    .foregroundStyle(Theme.dim.opacity(0.7))
            } else {
                Rectangle().fill(Theme.card)
                Text(String(title.prefix(1)).uppercased())
                    .font(Theme.mono(side * 0.3, .bold))
                    .foregroundStyle(Theme.dim)
            }
        }
        .frame(width: side, height: side)
    }
}

/// Обложка альбома для сеток и списков: сама подстраивается под размер, который дали,
/// и читает файл с диска не на главном потоке, поэтому прокрутка не дёргается.
struct AlbumArt: View {
    @Environment(Library.self) private var library
    let albumID: String
    let title: String
    var size: CoverSize = .mid
    var radius: CGFloat?

    private struct Loaded {
        let key: String
        let image: UIImage
    }

    @State private var loaded: Loaded?

    var body: some View {
        let covers = library.covers
        let fileKey: String? = covers.key(albumID)
        let fromCache: UIImage? = covers.cached(albumID, size)
        let image: UIImage? = fromCache ?? ((loaded?.key == fileKey) ? loaded?.image : nil)
        let r: CGFloat = radius ?? Theme.coverRadius
        let shape = RoundedRectangle(cornerRadius: r, style: .continuous)

        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                GeometryReader { geo in
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: geo.size.width, height: geo.size.height)
                            .clipped()
                    } else {
                        CoverPlaceholder(title: title, side: max(geo.size.width, 1))
                    }
                }
            }
            .clipShape(shape)
            .overlay(shape.strokeBorder(Theme.fg.opacity(0.08), lineWidth: 0.5))
            .task(id: (fileKey ?? "") + "|" + String(size.pixels)) {
                guard let fileKey else {
                    loaded = nil
                    return
                }
                if covers.cached(albumID, size) != nil { return }
                if let img = await covers.load(albumID, size) {
                    loaded = Loaded(key: fileKey, image: img)
                }
            }
    }
}

struct Hairline: View {
    var body: some View {
        Rectangle().fill(Theme.line).frame(height: 1)
    }
}

struct Scrubber: View {
    let value: Double   // 0...1
    var onSeek: (Double) -> Void
    @State private var dragging: Double?

    var body: some View {
        GeometryReader { geo in
            let w = max(geo.size.width, 1)
            let p = dragging ?? value
            ZStack(alignment: .leading) {
                Rectangle().fill(Theme.line).frame(height: 2)
                Rectangle().fill(Theme.accent).frame(width: w * p, height: 2)
                Circle().fill(Theme.fg).frame(width: 10, height: 10)
                    .offset(x: w * p - 5)
            }
            .frame(height: 24)
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
        }
        .frame(height: 24)
    }
}

struct EmptyStateView: View {
    @Environment(Library.self) private var library

    var body: some View {
        VStack(spacing: 14) {
            Spacer()
            if Theme.modern {
                Image(systemName: library.isScanning ? "arrow.triangle.2.circlepath" : "music.note.house")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(Theme.dim)
            }
            Text(library.isScanning ? "SCANNING…" : "NO MUSIC")
                .font(Theme.mono(15, .bold))
                .foregroundStyle(Theme.fg)
            if library.isScanning {
                Text(library.scanTotal > 0 ? "\(library.scanDone) / \(library.scanTotal)" : library.scanNote)
                    .font(Theme.mono(12))
                    .foregroundStyle(Theme.dim)
            } else {
                Text("Files → На iPhone → Cadence\nкинь туда папки с альбомами.\nПотом нажми кнопку ниже.")
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.dim)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                Button {
                    Task { await library.rescan() }
                } label: {
                    Text("SCAN LIBRARY")
                        .font(Theme.mono(12, .bold))
                        .foregroundStyle(Theme.accent)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 20)
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
