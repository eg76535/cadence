import SwiftUI

// Вкладка WAVE: моя волна, рандом, подборки из истории, статистика.
// Блоки с ИИ-сервером (рекомендации, разметка, настройки) лежат в AISections.swift.

// MARK: - Мелкие общие вьюхи

struct SectionTitle: View {
    let title: String
    var note: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Hairline()
            HStack {
                Text(title)
                    .font(Theme.mono(12, .bold))
                    .foregroundStyle(Theme.fg)
                Spacer()
                if let note {
                    Text(note)
                        .font(Theme.mono(10))
                        .foregroundStyle(Theme.dim)
                        .lineLimit(1)
                }
            }
        }
    }
}

struct ActionLabel: View {
    let text: String
    var accent = false

    var body: some View {
        Text(text)
            .font(Theme.mono(12, .bold))
            .foregroundStyle(accent ? Theme.accent : Theme.fg)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .overlay(Rectangle().stroke(accent ? Theme.accent : Theme.line, lineWidth: 1))
    }
}

struct ChipGrid: View {
    let items: [String]
    @Binding var selected: Set<String>
    var single = false

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(items, id: \.self) { item in
                let on = selected.contains(item)
                Button {
                    if single {
                        selected = [item]
                    } else if on {
                        selected.remove(item)
                    } else {
                        selected.insert(item)
                    }
                } label: {
                    Text(item.uppercased())
                        .font(Theme.mono(11, .bold))
                        .foregroundStyle(on ? Theme.accent : Theme.dim)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .overlay(Rectangle().stroke(on ? Theme.accent : Theme.line, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct MonoField: View {
    let placeholder: String
    @Binding var text: String
    var secure = false

    var body: some View {
        Group {
            if secure {
                SecureField("", text: $text, prompt: Text(placeholder).foregroundStyle(Theme.dim))
            } else {
                TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(Theme.dim))
            }
        }
        .font(Theme.mono(13))
        .foregroundStyle(Theme.fg)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) { Hairline() }
    }
}

// MARK: - Экран

@MainActor
struct DiscoverView: View {
    @Environment(Library.self) private var library
    @Environment(PlayerEngine.self) private var player
    @Environment(TasteStore.self) private var taste
    @Environment(TagStore.self) private var tags
    @Environment(ServerAI.self) private var ai

    var onOpen: (Album) -> Void

    @State private var chips: Set<String> = []
    @State private var waveText = ""
    @State private var waveNote = ""
    @State private var waveBusy = false
    @State private var randomMode: RandomMode = .any
    @State private var rolled = ""
    @State private var forYou = ForYouLists()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                waveSection
                randomSection
                forYouSection
                RecsSection()
                statsSection
                TagsSection()
                ServerSection()
            }
            .padding(.vertical, 14)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .task { refreshForYou() }
    }

    // MARK: - Моя волна

    private var waveSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "MY WAVE", note: player.waveTitle.map { "NOW: \($0)" })

            HStack(spacing: 10) {
                Button {
                    WaveRunner.start(WaveRequest(), library: library, player: player, taste: taste, tags: tags)
                } label: {
                    ActionLabel(text: "▶ START", accent: true)
                }
                .buttonStyle(.plain)

                if player.waveTitle != nil {
                    Button {
                        player.stopWave()
                    } label: {
                        ActionLabel(text: "■ END WAVE")
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }

            Text("настроение (можно несколько)")
                .font(Theme.mono(10))
                .foregroundStyle(Theme.dim)
            ChipGrid(items: Mood.all, selected: $chips)

            MonoField(placeholder: "или текстом: грустно под дождь, для кода…", text: $waveText)

            HStack(spacing: 10) {
                Button {
                    goWave()
                } label: {
                    ActionLabel(text: waveBusy ? "…" : "GO", accent: true)
                }
                .buttonStyle(.plain)
                .disabled(waveBusy || (chips.isEmpty && waveText.trimmingCharacters(in: .whitespaces).isEmpty))

                if !waveNote.isEmpty {
                    Text(waveNote)
                        .font(Theme.mono(10))
                        .foregroundStyle(Theme.dim)
                }
            }
        }
        .padding(.horizontal, 20)
    }

    private func goWave() {
        let picked = Mood.all.filter { chips.contains($0) }
        let text = waveText.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            waveBusy = true
            defer { waveBusy = false }

            var req = WaveRequest()
            if text.isEmpty {
                req.title = String(picked.joined(separator: "+").uppercased().prefix(24))
                waveNote = ""
            } else if ai.isConfigured {
                waveNote = "ASKING SERVER…"
                do {
                    req = try await ai.waveRequest(from: text, libraryGenres: Discover.topGenres(library, limit: 40))
                    waveNote = "PARSED BY SERVER"
                } catch {
                    req = WaveRequest.fromText(text)
                    waveNote = "SERVER OFFLINE → LOCAL PARSER"
                }
            } else {
                req = WaveRequest.fromText(text)
                waveNote = "LOCAL PARSER"
            }
            for m in picked where !req.moods.contains(m) {
                req.moods.append(m)
            }
            WaveRunner.start(req, library: library, player: player, taste: taste, tags: tags)
        }
    }

    // MARK: - Рандом

    private var randomSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "RANDOM", note: "ANY = чистый рандом · TASTE = по вкусу · NEW = ещё не слушал")

            HStack(spacing: 8) {
                ForEach(RandomMode.allCases, id: \.self) { mode in
                    Button {
                        randomMode = mode
                    } label: {
                        Text(mode.rawValue)
                            .font(Theme.mono(11, .bold))
                            .foregroundStyle(randomMode == mode ? Theme.accent : Theme.dim)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .overlay(Rectangle().stroke(randomMode == mode ? Theme.accent : Theme.line, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }

            HStack(spacing: 10) {
                Button { rollTrack() } label: { ActionLabel(text: "? TRACK") }
                    .buttonStyle(.plain)
                Button { rollAlbum() } label: { ActionLabel(text: "? ALBUM") }
                    .buttonStyle(.plain)
                Button { rollArtist() } label: { ActionLabel(text: "? ARTIST") }
                    .buttonStyle(.plain)
            }

            if !rolled.isEmpty {
                Text(rolled)
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.dim)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 20)
    }

    private func rollTrack() {
        guard let t = Discover.randomTrack(library, taste, randomMode) else {
            rolled = "NOTHING TO ROLL"
            return
        }
        rolled = "TRACK · \(t.artist) — \(t.title)"
        // после случайного трека дальше играет волна по вкусу
        WaveRunner.start(WaveRequest(), library: library, player: player, taste: taste, tags: tags, seed: [t])
    }

    private func rollAlbum() {
        guard let a = Discover.randomAlbum(library, taste, randomMode) else {
            rolled = "NOTHING TO ROLL"
            return
        }
        rolled = "ALBUM · \(a.artist) — \(a.title)"
        player.play(a.tracks, startAt: 0, shuffled: false)
    }

    private func rollArtist() {
        guard let r = Discover.randomArtist(library, taste, randomMode) else {
            rolled = "NOTHING TO ROLL"
            return
        }
        rolled = "ARTIST · \(r.name) (\(r.tracks.count) TRK)"
        player.play(r.tracks, shuffled: true)
    }

    // MARK: - Для тебя

    private var forYouSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(title: "FOR YOU", note: "из твоей истории")
                .padding(.horizontal, 20)

            albumRow("ЗАБЫТОЕ — раньше крутил", forYou.forgotten)
            albumRow("НИ РАЗУ НЕ СЛУШАЛ", forYou.unheard)
            albumRow("СЕЙЧАС В РОТАЦИИ", forYou.rotation)

            if forYou.forgotten.isEmpty && forYou.unheard.isEmpty && forYou.rotation.isEmpty {
                Text("Послушай пару дней, тут появятся подборки.")
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.dim)
                    .padding(.horizontal, 20)
            }

            Button {
                refreshForYou()
            } label: {
                ActionLabel(text: "↻ REFRESH")
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
        }
    }

    @ViewBuilder
    private func albumRow(_ title: String, _ albums: [Album]) -> some View {
        if !albums.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(Theme.mono(11, .bold))
                    .foregroundStyle(Theme.dim)
                    .padding(.horizontal, 20)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 12) {
                        ForEach(albums) { a in
                            Button {
                                onOpen(a)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    CoverImage(image: library.covers[a.id], title: a.title, size: 96)
                                    Text(a.title)
                                        .font(Theme.mono(10, .semibold))
                                        .foregroundStyle(Theme.fg)
                                        .lineLimit(1)
                                    Text(a.artist)
                                        .font(Theme.mono(9))
                                        .foregroundStyle(Theme.dim)
                                        .lineLimit(1)
                                }
                                .frame(width: 96, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
        }
    }

    private func refreshForYou() {
        forYou = Discover.forYou(library, taste)
    }

    // MARK: - Статистика

    private var statsSection: some View {
        let s = Discover.summary(library, taste)
        return VStack(alignment: .leading, spacing: 8) {
            SectionTitle(title: "STATS")
            Text("\(s.plays) PLAYS · \(String(format: "%.1f", s.hours)) H · \(s.liked) LIKED")
                .font(Theme.mono(12, .bold))
                .foregroundStyle(Theme.fg)
            ForEach(Array(s.topArtists.enumerated()), id: \.offset) { i, a in
                HStack {
                    Text("\(i + 1). \(a.name)")
                        .font(Theme.mono(11))
                        .foregroundStyle(Theme.fg)
                        .lineLimit(1)
                    Spacer()
                    Text("\(a.plays)")
                        .font(Theme.mono(11))
                        .foregroundStyle(Theme.dim)
                }
            }
            if s.plays == 0 {
                Text("Пока пусто. Трек засчитывается после минуты прослушивания.")
                    .font(Theme.mono(10))
                    .foregroundStyle(Theme.dim)
            }
        }
        .padding(.horizontal, 20)
    }
}
