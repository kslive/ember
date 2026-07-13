<div align="center">

<b>English</b> · <a href="README.ru.md">Русский</a> · <a href="README.zh.md">简体中文</a>

<img src="assets/logo.png" width="96" alt="Ember"/>

# Ember

**Local meeting recorder, transcriber and summarizer for macOS.**

Records your microphone and the other side of a call, writes a live transcript
with speaker labels, and produces a detailed summary — on your Mac. By default
nothing is uploaded.

![macOS](https://img.shields.io/badge/macOS-14.4%2B-000?style=flat-square&logo=apple)
![Apple Silicon](https://img.shields.io/badge/Apple%20Silicon-arm64-000?style=flat-square)
![version](https://img.shields.io/badge/version-1.5.2-f97316?style=flat-square)
![local](https://img.shields.io/badge/100%25-on--device-22c55e?style=flat-square)

<img src="assets/hero.en.png" width="900" alt="Ember"/>

</div>

---

## What it does

Ember records a meeting (microphone + system audio), transcribes it on-device and
writes a narrative summary you can read instead of attending: topic sections with the
details, names and decisions woven in, plus next steps. It works offline by default;
there is no account. The only optional cloud piece is DeepSeek summaries — off until
you add a key.

## Features

- **Live transcript** while recording, with speaker labels: you vs the other side — and
  the other side's voices are told apart and numbered (Speaker 1 / Speaker 2).
- **Automatic call detection** — recording starts a few seconds into a call (Zoom, browser
  meetings, …) and stops when it ends, also while the window is in the background.
- **Summaries in the language of the transcript**: local Apple MLX (Qwen3) by default, or
  add an optional **DeepSeek API key** — near-instant cloud summaries with automatic
  fallback to the local model.
- **Two speech engines**: Whisper (multilingual) and **GigaAM v3** — 2–3× more accurate
  for Russian.
- **Search** across all meetings, rename, and Markdown / Obsidian export.
- **Menu-bar control**, **⌘R** to start/stop, and visible processing stages after a call.
- Light / dark / auto theme, six accent colors; English, Russian and Chinese.
- Built-in updates from GitHub Releases, with an update banner and a "What's New" window.

## Export to Obsidian

Each summary can be written to a Markdown file (YAML front-matter, tasks, timestamps) in a
folder you pick, and opened in **Obsidian** with one click. If **[Sage](https://github.com/kslive/sage)**
is installed, it takes priority: the button turns into a glowing **Open in Sage** and the note
opens right in Sage (switching its space to the note's folder when needed). Remove Sage — and
the Obsidian button is back.

<div align="center"><img src="assets/obsidian.en.png" width="860" alt="Markdown / Obsidian export"/></div>

## Install

Requires **macOS 14.4+** on **Apple Silicon**.

1. Download `Ember_1.5.2_aarch64.dmg` from the [Releases](../../releases/latest) page.
2. Drag **Ember.app** into **Applications**.
3. The app is ad-hoc signed (not notarized), so the first launch is blocked. Either
   right-click **Ember.app → Open → Open**, or run:
   ```bash
   xattr -dr com.apple.quarantine /Applications/Ember.app
   ```
4. On first run, choose the languages, then download a Whisper model and a summary model.

## Build from source

Requires a recent Xcode and [Tuist](https://tuist.dev).

```bash
cd native
tuist install
tuist generate
open Ember.xcworkspace          # or: xcodebuild -scheme Ember -configuration Release build
```

Models are fetched from Hugging Face on first run. Signing is ad-hoc only — no Apple
Developer account is needed.

## Privacy

- Recording, transcription and summarization run locally.
- Audio is written to a temporary folder and deleted right after transcription; only the
  text (transcript + summary) is kept, in a local SQLite database on your Mac.
- Summaries are local by default. If you add a DeepSeek API key (optional), transcripts
  are sent to DeepSeek for summarization; delete the key to go fully local again. The key
  is stored encrypted on your Mac.
- Beyond that, the only network access is downloading the models (Hugging Face) and
  checking for updates (GitHub). No telemetry, no accounts.

## Built with

SwiftUI · WhisperKit (CoreML/ANE) · GigaAM v3 (sherpa-onnx) · Apple MLX (Qwen3) ·
FluidAudio (diarization) · GRDB (SQLite) · CoreAudio.
