import SwiftUI
import UIKit

struct SavedTheme: Identifiable, Equatable {
    let id: String      // "builtin:…", "theme.json" или "Themes/имя.json"
    let spec: ThemeSpec
    let builtin: Bool
}

/// Хранит активную тему и список доступных.
/// Источники: встроенные, Documents/theme.json (кинул файл, он применился сам),
/// Documents/Themes/*.json и вставка JSON из буфера обмена.
@Observable
final class ThemeStore {
    static let shared = ThemeStore()

    private(set) var spec = ThemeSpec()
    private(set) var themes: [SavedTheme] = []
    private(set) var activeID = BuiltinThemes.defaultID
    /// Идёт ли живой предпросмотр из редактора (тогда `spec` не равен сохранённой теме).
    private(set) var previewing = false
    var notice: String?

    private let defaults = UserDefaults.standard
    private let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    private var themesDir: URL { docs.appendingPathComponent("Themes", isDirectory: true) }

    private init() {
        activeID = defaults.string(forKey: "cadence.themeID") ?? BuiltinThemes.defaultID
        // один раз после обновления переключаем на новый привычный вид; старый Rockbox остаётся в списке
        if !defaults.bool(forKey: "cadence.modernMigrated") {
            defaults.set(true, forKey: "cadence.modernMigrated")
            if activeID == "builtin:rockbox" {
                activeID = BuiltinThemes.defaultID
                defaults.set(activeID, forKey: "cadence.themeID")
            }
        }
        reload()
    }

    // MARK: loading

    func reload() {
        try? FileManager.default.createDirectory(at: themesDir, withIntermediateDirectories: true)

        var list: [SavedTheme] = []
        for item in BuiltinThemes.all {
            if let parsed = ThemeSpec.parse(Data(item.json.utf8)) {
                list.append(SavedTheme(id: item.id, spec: parsed, builtin: true))
            }
        }

        let single = docs.appendingPathComponent("theme.json")
        if let t = loadFile(single, id: "theme.json") {
            list.append(t)
            // новый или изменённый theme.json применяем сразу
            let stamp = modified(single)
            if stamp > defaults.double(forKey: "cadence.themeJSONStamp") {
                defaults.set(stamp, forKey: "cadence.themeJSONStamp")
                activeID = "theme.json"
                defaults.set(activeID, forKey: "cadence.themeID")
            }
        }

        let files = (try? FileManager.default.contentsOfDirectory(at: themesDir, includingPropertiesForKeys: nil)) ?? []
        for url in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
        where url.pathExtension.lowercased() == "json" {
            if let t = loadFile(url, id: "Themes/" + url.lastPathComponent) { list.append(t) }
        }

        themes = list
        let chosen = list.first(where: { $0.id == activeID }) ?? list[0]
        activeID = chosen.id
        if !previewing && spec != chosen.spec { spec = chosen.spec }
    }

    private func loadFile(_ url: URL, id: String) -> SavedTheme? {
        guard let data = try? Data(contentsOf: url), let parsed = ThemeSpec.parse(data) else { return nil }
        return SavedTheme(id: id, spec: parsed, builtin: false)
    }

    private func modified(_ url: URL) -> Double {
        let date = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        return date?.timeIntervalSince1970 ?? 0
    }

    // MARK: actions

    func activate(_ id: String) {
        guard let t = themes.first(where: { $0.id == id }) else { return }
        previewing = false
        activeID = id
        defaults.set(id, forKey: "cadence.themeID")
        spec = t.spec
    }

    var activeTheme: SavedTheme? { themes.first(where: { $0.id == activeID }) }

    // MARK: editor

    /// Живой предпросмотр: экран перерисовывается сразу, на диск ничего не пишется.
    func preview(_ s: ThemeSpec) {
        previewing = true
        spec = s
    }

    /// Отмена правок: возвращаем сохранённую активную тему.
    func endPreview() {
        previewing = false
        if let t = activeTheme { spec = t.spec }
    }

    /// Сохраняет тему в Documents/Themes и делает её активной.
    /// `replacing`: id пользовательской темы, которую правим (файл перезапишется).
    @discardableResult
    func save(_ s: ThemeSpec, replacing: String?) -> Bool {
        try? FileManager.default.createDirectory(at: themesDir, withIntermediateDirectories: true)
        let file = Self.slug(s.name) + ".json"
        let data = Data(s.jsonString().utf8)
        do {
            try data.write(to: themesDir.appendingPathComponent(file), options: .atomic)
        } catch {
            notice = "Не удалось сохранить тему."
            return false
        }
        // переименовали свою тему: старый файл убираем, чтобы не плодить копии
        if let old = replacing, old.hasPrefix("Themes/"), old != "Themes/" + file {
            try? FileManager.default.removeItem(at: docs.appendingPathComponent(old))
        }
        previewing = false
        reload()
        activate("Themes/" + file)
        notice = "Тема «\(s.name)» сохранена."
        return true
    }

    @discardableResult
    func importJSON(_ text: String) -> Bool {
        guard let data = text.data(using: .utf8), let parsed = ThemeSpec.parse(data) else {
            notice = "В буфере не тема. Нужен JSON из дизайн-стенда."
            return false
        }
        try? FileManager.default.createDirectory(at: themesDir, withIntermediateDirectories: true)
        let file = Self.slug(parsed.name) + ".json"
        do {
            try data.write(to: themesDir.appendingPathComponent(file), options: .atomic)
        } catch {
            notice = "Не удалось сохранить тему."
            return false
        }
        reload()
        activate("Themes/" + file)
        notice = "Тема «\(parsed.name)» добавлена."
        return true
    }

    func importFromClipboard() {
        guard let text = UIPasteboard.general.string, !text.isEmpty else {
            notice = "Буфер пуст. Скопируй JSON темы в дизайн-стенде."
            return
        }
        importJSON(text)
    }

    func delete(_ id: String) {
        guard let t = themes.first(where: { $0.id == id }), !t.builtin else { return }
        let url = id == "theme.json" ? docs.appendingPathComponent("theme.json") : docs.appendingPathComponent(id)
        try? FileManager.default.removeItem(at: url)
        if activeID == id {
            activeID = BuiltinThemes.defaultID
            defaults.set(activeID, forKey: "cadence.themeID")
        }
        reload()
    }

    static func slug(_ s: String) -> String {
        let mapped = s.lowercased().map { ($0.isLetter || $0.isNumber) ? String($0) : "-" }.joined()
        let joined = mapped.split(separator: "-").joined(separator: "-")
        return joined.isEmpty ? "theme" : joined
    }
}
