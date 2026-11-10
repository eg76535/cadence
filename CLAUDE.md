# Cadence: инструкции для Claude Code

Минималистичный музыкальный плеер для iPhone в стиле Rockbox/iPod с Cover Flow. Разработчик на Windows, мака нет и не будет. Локально Swift не компилируется, проверка только через CI.

## Рабочий цикл

1. Правишь код, коммитишь, `git push` в `main`.
2. GitHub Actions (`.github/workflows/build.yml`) собирает unsigned `.ipa` на macOS-раннере.
3. Следишь за сборкой: `gh run watch` (или `gh run list --limit 3`).
4. Если упала: `gh run view --log-failed`, смотри блок `=== ERRORS ===`, чини, пушь снова.
5. Готовый IPA: `gh run download -n Cadence-ipa`. Пользователь ставит его через Sideloadly.

Не говори, что работает, пока сборка не зелёная. Поведение на устройстве (Cover Flow, звук) ты проверить не можешь, честно говори об этом и проси пользователя глянуть.

## Стек и ограничения

- Swift 5 mode, SwiftUI, iOS 17+, `@Observable` (Observation), без сторонних зависимостей.
- Проект генерируется XcodeGen из `project.yml`. `.xcodeproj` в git не коммитим. Новые файлы в `Cadence/` подхватываются автоматически.
- Info.plist тоже из `project.yml` (`UIFileSharingEnabled`, фоновое аудио и т.д.).
- Бесплатный Apple ID: нельзя Push, iCloud, App Groups и прочие capabilities. Не добавляй их.
- Воспроизведение через AVPlayer. Форматы вне AVFoundation (OGG, Opus, APE, WavPack, MKV) только через MobileVLCKit, это отдельный этап.

## Эстетика

Тем два вида интерфейса, переключаются полем `ui` в теме (`ThemeSpec.ui`):

- **modern** (по умолчанию, тема `builtin:music`): привычный вид в духе Apple Music. SF-шрифт, вкладки с иконками SF Symbols, сетка альбомов, мини-плеер над вкладками, плеер выезжает снизу и закрывается свайпом вниз. Код в `Cadence/Modern/`.
- **classic** (Rockbox/iPod): чёрный фон, моноширинный шрифт, без скруглений и теней, вкладки текстом. Код в `Views/` (`ClassicRootView` в `RootView.swift`). В этом режиме держать старую строгость: один акцент, `Hairline` как разделитель, ничего лишнего.

Общие правила для обоих:

- Цвета только через `Theme.*` (читают активную тему), никаких литералов `Color.black` во view. Исключение: тени и затемнение поверх обложек.
- Шрифт только через `Theme.font(...)` (старое имя `Theme.mono(...)` делает то же самое). Он сам берёт SF/rounded/serif или моноширинный по теме.
- Обложки показывать через `AlbumArt` (async, из дискового кеша). Не читать `library.covers[id]` (полный размер, синхронно) в списках и сетках: это тормоза и память.
- Настройки и редактор темы: `Modern/SettingsView.swift`, `Modern/ThemeEditor.swift` (живой предпросмотр через `ThemeStore.preview`).

## Структура

- `Library.swift`: кеш библиотеки (`library.json` в Application Support), скан Documents только по кнопке (`rescan(full:)`), группировка по альбомам, правки пользователя (`edits.json`), догадки по папкам и имени файла
- `Tags.swift`: чтение тегов. `FlacReader` (свой разбор FLAC: STREAMINFO, VORBIS_COMMENT, PICTURE, потому что AVFoundation на iOS не отдаёт теги/обложки FLAC), `AVTagReader` для MP3/M4A/WAV/AIFF
- `Covers.swift`: `CoverDisk` (JPEG до 800 px в `Application Support/Cadence/covers`, ключ = sha1), `CoverStore` (NSCache трёх размеров, async-загрузка)
- `Models.swift`: `Track` (id = путь от Documents, url собирается на лету), `Album`, `TrackEdit`
- `Modern/`: привычный интерфейс (`ModernRoot`, `AlbumsScreen`, `SongsScreen`, `AlbumPage`, `ModernPlayer`), `SettingsView`, `ThemeEditor`, `MetadataEditor`, общие мелочи в `ModernKit`
- `PlayerEngine.swift`: AVPlayer, очередь, шафл/репит, Now Playing, команды с экрана блокировки
- `Views/CoverFlowView.swift`: Cover Flow, параметры из активной темы, портрет и альбомная (плитки грузят обложки async)
- `ThemeSpec.swift`: модель темы и разбор JSON (формат общий с дизайн-стендом); `ThemeStore.swift`: список тем, `Documents/theme.json`, `Documents/Themes/`, вставка из буфера
- `Views/ThemeViews.swift`: `WallView` (фон, волны), `PanelStyle` (стекло/плавающая плашка), `ThemesView`
- `Views/RootView.swift`: `RootView` (выбор modern/classic по теме, шиты через `AppSheet`, жизненный цикл) и `ClassicRootView` (старые вкладки FLOW / ALBUMS / SONGS / WAVE)

- `Taste/TasteStore.swift`: история прослушиваний, лайки, вишлист (JSON в Application Support). Пишет в него `PlayerEngine`
- `Taste/AlbumTags.swift`: настроение альбомов (теги от ИИ + эвристика по жанру)
- `Taste/WaveEngine.swift`: `WaveRequest` (фильтр), `WaveEngine.pick` (скоринг + взвешенная выборка), `WaveRunner` (запуск в плеере)
- `Taste/Discover.swift`: рандом, подборки «для тебя», статистика, портрет вкуса для промптов
- `AI/ServerAI.swift`: клиент к OpenAI-совместимой ИИ на домашнем сервере (разметка альбомов, текст -> волна, рекомендации)
- `Views/DiscoverView.swift`, `Views/AISections.swift`: вкладка WAVE

Правила для ИИ-части: сервер на CPU, поэтому запросы редкие, ответы маленькие (JSON), результаты кешируются. Любая фича обязана работать без сервера. Ключ и адрес лежат в UserDefaults (`ai.url`, `ai.model`, `ai.key`), в git ничего секретного не коммитим.

## Дальше (по приоритету)

1. Починить сборку, если упадёт (v0.4: библиотека с кешем, FLAC-парсер, modern-интерфейс, настройки и редактор тем написаны без компилятора), и подогнать вид по ощущениям пользователя.
   - Тема: вшить шрифты JetBrains/Plex/Space Mono, подключить iOS 26 `glassEffect` через `#if compiler(>=6.2)`.
2. Кнопка импорта файлов внутри приложения (`fileImporter`, копирование в Documents).
3. Вкладка/страница артистов, плейлисты.
4. Сохранение позиции и очереди между запусками.
5. MobileVLCKit для OGG/Opus/APE.
6. Эквалайзер, gapless.
