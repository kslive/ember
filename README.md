<div align="center">

<b>English</b> · <a href="README.ru.md">Русский</a> · <a href="README.zh.md">简体中文</a>

<img src="assets/logo.png" width="96" alt="Ember"/>

# Ember

**Local meeting recorder, transcriber and summarizer for macOS.**

Ember records your mic and the other side of a call, writes a live transcript, and turns it
into a detailed, readable summary — entirely on your Mac. It starts and stops on its own, and
by default nothing ever leaves the device.

![macOS](https://img.shields.io/badge/macOS-14.4%2B-000?style=flat-square&logo=apple)
![Apple Silicon](https://img.shields.io/badge/Apple%20Silicon-arm64-000?style=flat-square)
![version](https://img.shields.io/badge/version-1.6.0-f97316?style=flat-square)
![local](https://img.shields.io/badge/100%25-on--device-22c55e?style=flat-square)

<img src="assets/hero.en.png" width="900" alt="Ember"/>

</div>

---

## What it does

Ember records a meeting (microphone + system audio), transcribes it on-device, and writes a
narrative summary you can read instead of attending — topic sections with the details, names
and decisions woven in, plus next steps. It works offline, with no account. The only optional
cloud piece is DeepSeek summaries, and that stays off until you add a key.

## ✨ Features

### 🎙 Recording & capture
- **Both sides of the call** — your microphone and the system audio (the people you're talking
  to) captured together, including over **AirPods / headphones**.
- **Automatic call detection** — recording begins a few seconds into a call (Zoom, Google Meet,
  browser calls, …) and stops when it ends, even while Ember is in the background.
- **Menu-bar control**, **⌘R** to start/stop, and clear processing stages after a call.

### ⌨️ Live transcript
- **Real-time transcript** that types itself out as people speak.
- **Speaker labels** — `[Me]` for you and `[S]` for the other side; the AI works out the
  distinct participants from the conversation itself.
- **Two speech engines** — Whisper (Small / Medium / **Large V3 Turbo**, multilingual) and
  **GigaAM v3**, 2–3× more accurate for Russian.

### 🧠 Summaries
- A **narrative summary in the transcript's language** — read it instead of attending.
- **Local by default** via Apple **MLX (Qwen3 1.7B / 4B / 8B)**, or add an optional
  **DeepSeek API key** for near-instant cloud summaries with **automatic fallback** to the
  local model.
- **Fact-grounded** — names, numbers and decisions are pulled from what was actually said,
  so there's less to make up.
- **Edit inline** — fix the summary right as you read it; changes sync to the exported file.

### 🗂 Summary templates
- **Choose how each summary is written** — set a default, or pick one per meeting.
- **Built-in library**: Standard, **Daily, Interview, 1×1, Final Interview, TODO, Demo,
  Grooming**.
- Templates are plain **Markdown files** in a folder — edit them by hand or drop in your own,
  and changes are picked up automatically. Every meeting remembers the template it was made with.

### 📅 Organize & export
- **Calendar-aware titles** — a meeting is named from the Apple Calendar event running when you
  start recording.
- **Search** across every meeting, and rename freely.
- **Markdown export** into date folders (YAML front-matter, tasks, timestamps).
- **One-click Obsidian** — or **Sage**, which takes over the button when installed.

### ⚙️ Control & polish
- **Deferred processing** (optional) — if another call starts right after, transcription and
  summary wait in a queue and run once all calls are done, so your Mac stays quiet mid-call.
- **Model management** — download / select / delete, live progress, RAM hints, grouped and
  sorted; models unload right after use to free memory.
- **Launch at login**, light / dark / auto theme, **six accent colors**, and **English /
  Russian / Chinese** with instant switching.
- **Built-in updates** from GitHub Releases, with an update banner and a "What's New" window.

## Export to Obsidian

Each summary can be written to a Markdown file (YAML front-matter, tasks, timestamps) in a
folder you pick, and opened in **Obsidian** with one click. If **[Sage](https://github.com/kslive/sage)**
is installed, it takes priority: the button turns into a glowing **Open in Sage** and the note
opens right in Sage (switching its space to the note's folder when needed). Remove Sage — and
the Obsidian button is back.

<div align="center"><img src="assets/obsidian.en.png" width="860" alt="Markdown / Obsidian export"/></div>

## Install

Requires **macOS 14.4+** on **Apple Silicon**.

1. Download `Ember_1.6.0_aarch64.dmg` from the [Releases](../../releases/latest) page.
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
GRDB (SQLite) · CoreAudio.
