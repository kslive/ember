<div align="center">

<a href="README.md">English</a> · <b>Русский</b> · <a href="README.zh.md">简体中文</a>

<img src="assets/logo.png" width="96" alt="Ember"/>

# Ember

**Локальная запись, расшифровка и саммари встреч для macOS.**

Записывает микрофон и собеседника, ведёт живой транскрипт и делает короткое
саммари — целиком на вашем Mac. Ничего не выгружается в сеть.

![macOS](https://img.shields.io/badge/macOS-14.4%2B-000?style=flat-square&logo=apple)
![Apple Silicon](https://img.shields.io/badge/Apple%20Silicon-arm64-000?style=flat-square)
![version](https://img.shields.io/badge/version-1.4.3-f97316?style=flat-square)
![local](https://img.shields.io/badge/100%25-локально-22c55e?style=flat-square)

<img src="assets/hero.ru.png" width="900" alt="Ember"/>

</div>

---

## Что это

Ember записывает встречу (микрофон + системный звук), расшифровывает её на устройстве
через Whisper и формирует структурное саммари — обзор, решения, задачи — локальной
языковой моделью. Работает офлайн, без аккаунта и без облака.

## Возможности

- **Живой транскрипт** во время записи, с метками источника: `[mic]` (вы) и `[mac]` (собеседник).
- **Автодетект звонка** — запись стартует с началом звонка и останавливается по его окончании, в том числе когда окно свёрнуто.
- **Локальное саммари** через Apple MLX (Qwen3), на языке транскрипта.
- **Поиск** по всем встречам, переименование и экспорт в Markdown / Obsidian.
- **Управление из меню-бара** и **⌘R** для старта/стопа.
- Светлая / тёмная / авто тема; русский, английский и китайский.
- Встроенные обновления из GitHub Releases.

## Экспорт в Obsidian

Каждое саммари можно сохранить в Markdown-файл (YAML-фронтматтер, задачи, тайм-коды) в
выбранную папку — например, в волт Obsidian.

<div align="center"><img src="assets/obsidian.ru.png" width="860" alt="Экспорт в Markdown / Obsidian"/></div>

## Установка

Нужна **macOS 14.4+** на **Apple Silicon**.

1. Скачайте `Ember_1.4.3_aarch64.dmg` со страницы [Releases](../../releases/latest).
2. Перетащите **Ember.app** в **Программы**.
3. Приложение подписано ad-hoc (без нотаризации), поэтому первый запуск блокируется.
   Либо правый клик по **Ember.app → Открыть → Открыть**, либо в Терминале:
   ```bash
   xattr -dr com.apple.quarantine /Applications/Ember.app
   ```
4. При первом запуске выберите языки, затем скачайте модель Whisper и модель для саммари.

## Сборка из исходников

Нужны свежий Xcode и [Tuist](https://tuist.dev).

```bash
cd native
tuist install
tuist generate
open Ember.xcworkspace          # или: xcodebuild -scheme Ember -configuration Release build
```

Модели подтягиваются с Hugging Face при первом запуске. Подпись только ad-hoc — аккаунт
Apple Developer не нужен.

## Приватность

- Запись, расшифровка и саммари выполняются локально.
- Аудио пишется во временную папку и удаляется сразу после расшифровки; сохраняется только
  текст (транскрипт + саммари) в локальной базе SQLite на вашем Mac.
- Единственный выход в сеть — загрузка моделей (Hugging Face) и проверка обновлений
  (GitHub). Без телеметрии и аккаунтов.

## На чём сделано

SwiftUI · WhisperKit (CoreML/ANE) · Apple MLX (Qwen3) · GRDB (SQLite) · CoreAudio.
