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
                ZStack {
                    Rectangle().fill(Color(white: 0.09))
                    Text(String(title.prefix(1)).uppercased())
                        .font(Theme.mono(size * 0.3, .bold))
                        .foregroundStyle(Theme.dim)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: Theme.coverRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.coverRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
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
    let isScanning: Bool

    var body: some View {
        VStack(spacing: 14) {
            Spacer()
            Text(isScanning ? "SCANNING…" : "NO MUSIC")
                .font(Theme.mono(15, .bold))
                .foregroundStyle(Theme.fg)
            if !isScanning {
                Text("Files → На iPhone → Cadence\nкинь туда папки с альбомами.\nПотом вернись сюда.")
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.dim)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
