import SwiftUI

// Блоки вкладки WAVE, которым нужна ИИ на домашнем сервере.

// MARK: - Рекомендации (то, чего нет в библиотеке)

@MainActor
struct RecsSection: View {
    @Environment(Library.self) private var library
    @Environment(TasteStore.self) private var taste
    @Environment(TagStore.self) private var tags
    @Environment(ServerAI.self) private var ai
    @AppStorage("ai.url") private var url = ""

    @State private var modeSel: Set<String> = [RecMode.similar.rawValue]
    @State private var hint = ""
    @State private var recs: [Recommendation] = []
    @State private var errorText: String?

    private var mode: RecMode {
        RecMode.allCases.first { modeSel.contains($0.rawValue) } ?? .similar
    }

    private var configured: Bool {
        !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "DISCOVER", note: "AI · что послушать ещё")

            if !configured {
                Text("Укажи адрес сервера в блоке SERVER ниже.")
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.dim)
            } else {
                ChipGrid(items: RecMode.allCases.map { $0.rawValue }, selected: $modeSel, single: true)
                MonoField(placeholder: "пожелание: для вечерней пробежки, что-то японское…", text: $hint)

                HStack(spacing: 10) {
                    Button {
                        fetch()
                    } label: {
                        ActionLabel(text: ai.busy ? "…" : "GET RECS", accent: true)
                    }
                    .buttonStyle(.plain)
                    .disabled(ai.busy)

                    if ai.busy {
                        Text(ai.status)
                            .font(Theme.mono(10))
                            .foregroundStyle(Theme.dim)
                    }
                }

                if let errorText {
                    Text(errorText)
                        .font(Theme.mono(10))
                        .foregroundStyle(Theme.accent)
                }

                ForEach(recs) { rec in
                    recRow(rec)
                }

                if !recs.isEmpty {
                    Text("ИИ может ошибиться с альбомом: сначала проверь через SEARCH.")
                        .font(Theme.mono(9))
                        .foregroundStyle(Theme.dim)
                }
            }

            if !taste.wishlist.isEmpty {
                Text("WISHLIST")
                    .font(Theme.mono(11, .bold))
                    .foregroundStyle(Theme.dim)
                    .padding(.top, 6)
                ForEach(taste.wishlist) { item in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(item.artist) — \(item.album)")
                                .font(Theme.mono(12, .semibold))
                                .foregroundStyle(Theme.fg)
                            if !item.why.isEmpty {
                                Text(item.why)
                                    .font(Theme.mono(10))
                                    .foregroundStyle(Theme.dim)
                            }
                        }
                        Spacer()
                        searchMenu(artist: item.artist, album: item.album)
                        Button {
                            taste.removeWish(item)
                        } label: {
                            Text("✕")
                                .font(Theme.mono(12, .bold))
                                .foregroundStyle(Theme.dim)
                                .padding(.leading, 10)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.horizontal, 20)
    }

    private func recRow(_ rec: Recommendation) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Hairline()
            Text("\(rec.artist) — \(rec.album)" + (rec.year.map { " (\($0))" } ?? ""))
                .font(Theme.mono(12, .semibold))
                .foregroundStyle(Theme.fg)
            if !rec.why.isEmpty {
                Text(rec.why)
                    .font(Theme.mono(10))
                    .foregroundStyle(Theme.dim)
            }
            HStack(spacing: 16) {
                searchMenu(artist: rec.artist, album: rec.album)
                Button {
                    taste.addWish(artist: rec.artist, album: rec.album, why: rec.why)
                } label: {
                    Text("+ WISH")
                        .font(Theme.mono(11, .bold))
                        .foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 2)
        }
    }

    private func searchMenu(artist: String, album: String) -> some View {
        let q = "\(artist) \(album)"
        let enc = q.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
        return Menu {
            if let u = URL(string: "https://music.yandex.ru/search?text=\(enc)") {
                Link("Яндекс Музыка", destination: u)
            }
            if let u = URL(string: "https://music.youtube.com/search?q=\(enc)") {
                Link("YouTube Music", destination: u)
            }
            if let u = URL(string: "https://music.apple.com/search?term=\(enc)") {
                Link("Apple Music", destination: u)
            }
        } label: {
            Text("SEARCH")
                .font(Theme.mono(11, .bold))
                .foregroundStyle(Theme.fg)
        }
    }

    private func fetch() {
        errorText = nil
        let m = mode
        let h = hint
        Task {
            do {
                recs = try await ai.recommend(mode: m, hint: h, library: library, taste: taste, tags: tags)
                if recs.isEmpty { errorText = "Пусто: всё, что предложила ИИ, у тебя уже есть." }
            } catch {
                self.errorText = error.localizedDescription
            }
        }
    }
}

// MARK: - Разметка альбомов настроением

@MainActor
struct TagsSection: View {
    @Environment(Library.self) private var library
    @Environment(TasteStore.self) private var taste
    @Environment(TagStore.self) private var tags
    @Environment(ServerAI.self) private var ai
    @AppStorage("ai.url") private var url = ""

    var body: some View {
        let total = library.albums.count
        let done = library.albums.filter { tags.ai[$0.id] != nil }.count
        let configured = !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: "MOOD TAGS", note: "\(done)/\(total) ALBUMS")

            Text("ИИ один раз размечает альбомы по настроению (энергия, светлый/мрачный, жанры). Дальше волна работает сама и офлайн. Пока не размечено, настроение берётся из жанрового тега файла.")
                .font(Theme.mono(10))
                .foregroundStyle(Theme.dim)
                .lineSpacing(3)

            HStack(spacing: 10) {
                if ai.tagging {
                    Button {
                        ai.stopTagging()
                    } label: {
                        ActionLabel(text: "■ STOP")
                    }
                    .buttonStyle(.plain)
                    Text("TAGGING \(ai.tagDone)/\(ai.tagTotal)")
                        .font(Theme.mono(11, .bold))
                        .foregroundStyle(Theme.accent)
                } else {
                    Button {
                        ai.startTagging(library: library, tags: tags, taste: taste)
                    } label: {
                        ActionLabel(text: done == 0 ? "TUNE MY WAVE" : "CONTINUE TAGGING", accent: true)
                    }
                    .buttonStyle(.plain)
                    .disabled(!configured || done >= total)
                }
            }

            if ai.tagging {
                Text("Экран не гаснет, пока идёт разметка. Приложение держи открытым: в фоне iOS её остановит. Можно прервать и продолжить позже, сделанное сохраняется.")
                    .font(Theme.mono(9))
                    .foregroundStyle(Theme.dim)
                    .lineSpacing(3)
            }
            if let e = ai.lastError {
                Text(e)
                    .font(Theme.mono(10))
                    .foregroundStyle(Theme.accent)
            }
        }
        .padding(.horizontal, 20)
    }
}

// MARK: - Настройки сервера

@MainActor
struct ServerSection: View {
    @Environment(ServerAI.self) private var ai
    @AppStorage("ai.url") private var url = ""
    @AppStorage("ai.model") private var model = ""
    @AppStorage("ai.key") private var key = ""

    @State private var testResult = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: "SERVER", note: "OpenAI-совместимый API")

            MonoField(placeholder: "http://192.168.1.50:8080", text: $url)
                .keyboardType(.URL)
            MonoField(placeholder: "модель (можно пусто для llama.cpp)", text: $model)
            MonoField(placeholder: "API key (если включён)", text: $key, secure: true)

            HStack(spacing: 10) {
                Button {
                    test()
                } label: {
                    ActionLabel(text: ai.busy ? "…" : "TEST")
                }
                .buttonStyle(.plain)
                .disabled(ai.busy || url.trimmingCharacters(in: .whitespaces).isEmpty)

                if !testResult.isEmpty {
                    Text(testResult)
                        .font(Theme.mono(10))
                        .foregroundStyle(Theme.dim)
                        .lineLimit(2)
                }
            }

            Text("Вне дома используй VPN/Tailscale или HTTPS с ключом. Голый порт llama.cpp в интернет не выставляй.")
                .font(Theme.mono(9))
                .foregroundStyle(Theme.dim)
                .lineSpacing(3)
        }
        .padding(.horizontal, 20)
    }

    private func test() {
        testResult = "…"
        Task {
            do {
                let reply = try await ai.ping()
                testResult = "OK · " + String(reply.prefix(30))
            } catch {
                self.testResult = "FAIL · " + error.localizedDescription
            }
        }
    }
}
