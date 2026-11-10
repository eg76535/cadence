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

## Эстетика (держать строго)

- По умолчанию тема Rockbox: чёрный фон, белый текст, серый `Theme.dim`, один акцент `Theme.accent`, без скруглений, теней и градиентов. Остальное (стекло, фон, плавающие панели) включается только темой.
- Весь текст моноширинный через `Theme.mono(...)`.
- Цвета брать только через `Theme.*` (они читают активную тему), никаких литералов `Color.black` и т.п. во view.
- Разделители в плоском режиме только `Hairline`.

## Структура

- `Library.swift`: скан Documents, теги, обложки, группировка по альбомам, кеш по mtime
- `PlayerEngine.swift`: AVPlayer, очередь, шафл/репит, Now Playing, команды с экрана блокировки
- `Views/CoverFlowView.swift`: Cover Flow, параметры из активной темы, портрет и альбомная
- `ThemeSpec.swift`: модель темы и разбор JSON (формат общий с дизайн-стендом); `ThemeStore.swift`: список тем, `Documents/theme.json`, `Documents/Themes/`, вставка из буфера
- `Views/ThemeViews.swift`: `WallView` (фон, волны), `PanelStyle` (стекло/плавающая плашка), `ThemesView`
- `Views/RootView.swift`: вкладки FLOW / ALBUMS / SONGS, мини-плеер, шиты

- `Taste/TasteStore.swift`: история прослушиваний, лайки, вишлист (JSON в Application Support). Пишет в него `PlayerEngine`
- `Taste/AlbumTags.swift`: настроение альбомов (теги от ИИ + эвристика по жанру)
- `Taste/WaveEngine.swift`: `WaveRequest` (фильтр), `WaveEngine.pick` (скоринг + взвешенная выборка), `WaveRunner` (запуск в плеере)
- `Taste/Discover.swift`: рандом, подборки «для тебя», статистика, портрет вкуса для промптов
- `AI/ServerAI.swift`: клиент к OpenAI-совместимой ИИ на домашнем сервере (разметка альбомов, текст -> волна, рекомендации)
- `Views/DiscoverView.swift`, `Views/AISections.swift`: вкладка WAVE

Правила для ИИ-части: сервер на CPU, поэтому запросы редкие, ответы маленькие (JSON), результаты кешируются. Любая фича обязана работать без сервера. Ключ и адрес лежат в UserDefaults (`ai.url`, `ai.model`, `ai.key`), в git ничего секретного не коммитим.

## Дальше (по приоритету)

1. Починить первую сборку, если упадёт (v0.2 с темами и альбомной тоже ни разу не компилировалась), и подогнать вид по ощущениям пользователя.
   - Тема: вшить шрифты JetBrains/Plex/Space Mono, подключить iOS 26 `glassEffect` через `#if compiler(>=6.2)`.
2. Кнопка импорта файлов внутри приложения (`fileImporter`, копирование в Documents).
3. Поиск, сортировка, вкладка артистов.
4. Плейлисты и «очередь» (play next).
5. Сохранение позиции и очереди между запусками.
6. MobileVLCKit для OGG/Opus/APE.
7. Эквалайзер, gapless.
