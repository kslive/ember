<div align="center">

<a href="README.md">English</a> · <a href="README.ru.md">Русский</a> · <b>简体中文</b>

<img src="assets/logo.png" width="96" alt="Ember"/>

# Ember

**本地完成会议的录制、转写与摘要。**

直接在 Mac 上录制、转写并整理会议记录。
无需云端、无需订阅——音频与文字都不会离开你的设备。

![macOS](https://img.shields.io/badge/macOS-14%2B-000?style=flat-square&logo=apple)
![Apple Silicon](https://img.shields.io/badge/Apple%20Silicon-arm64-000?style=flat-square)
![version](https://img.shields.io/badge/version-1.1.0-f97316?style=flat-square)
![local](https://img.shields.io/badge/100%25-on--device-22c55e?style=flat-square)

<img src="assets/hero.zh.png" width="900" alt="Ember — 概览"/>

</div>

---

## 这是什么

**Ember** 是一款 Mac 桌面应用：在会议过程中采集麦克风与系统声音，实时转换为文字记录，
随后生成结构化摘要（要点、决策、待办事项）。

一切都在**本地设备**上完成：语音识别使用本地 Whisper 模型，会议记录由本地 AI 模型生成。
任何内容都不会上传到云端。

---

## 功能

- **🎙️ 录制与实时转写。** 麦克风与系统声音由专业混音器合成（RMS 闪避、削波保护），
  语音在本地识别并实时显示在屏幕上——带有动态均衡器与计时器。
- **🏠 一键开始。** 点击录制按钮或使用快捷键 **⌘R**。
- **📞 自动检测通话。** Ember 会监测哪些应用在使用麦克风（Zoom、Google Meet、Teams、
  FaceTime、Telegram 等）：**通话开始——自动开始录制；通话结束——自动停止录制**并进入
  处理。即使 Ember 窗口最小化也在后台运行——不漏掉任何一场会议。
- **✦ 一键摘要。** 结束的会议由本地 AI 模型整理成记录：要点、关键决策，以及带负责人的
  待办事项。支持内置模型（Gemma 3、Qwen 2.5）和外部提供商（Ollama、Claude、OpenAI、
  OpenRouter）。
- **🔎 搜索** 所有会议的转写与摘要，并高亮匹配项。
- **🎨 主题** —— 浅色 / 深色 / 自动（跟随系统）。
- **🧭 菜单栏图标** —— 开始/停止与快速访问，即使窗口隐藏也可用。
- **⚡ GPU 加速**（Metal + CoreML）实现快速转写。
- **💾 保存会议音频** 为 MP4（可选）。

---

## 📝 导出到 Obsidian

每场会议都会保存为干净的 `.md` 文件，包含 YAML frontmatter、任务与时间戳。
指定你的库（vault）文件夹，记录便会自动出现在你的知识图谱中。

<div align="center"><img src="assets/obsidian.zh.png" width="860" alt="将摘要导出为 Markdown → Obsidian"/></div>

---

## 安装

> 需要运行于 **Apple Silicon**（M1/M2/M3…）的 **macOS 14+**。

1. 从 [**Releases**](../../releases/latest) 页面下载 `Ember_1.1.0_aarch64.dmg`。
2. 打开 `.dmg`，将 **Ember.app** 拖入 **应用程序** 文件夹。
3. 该应用为 ad-hoc 签名（未经 Apple 公证），因此首次启动时 macOS 会拦截它。
   请用以下任一方式解除隔离：
   - **右键点击** `Ember.app` → **打开** → 在对话框中再次点击 **打开**；**或**
   - 在终端中执行：
     ```bash
     xattr -dr com.apple.quarantine /Applications/Ember.app
     ```
4. 首次启动时完成引导：授予 **麦克风** 与 **系统声音采集** 权限（通过权限界面上的按钮），
   并下载语音识别模型（Whisper）和用于摘要的 AI 模型。

---

## 隐私

Ember 以 **隐私优先** 为设计理念：

- 录制、转写与摘要均在 **本地** 完成。
- 音频与文字仅存储在你的 Mac 上。
- 没有账户、没有会议遥测、没有云端（除非你自行选择外部 AI 提供商来生成摘要）。

---

## 技术栈

| 层 | 技术 |
|------|------|
| 外壳 | Tauri 2 (Rust) |
| 界面 | Next.js 14 · React 18 · TypeScript · Tailwind |
| 音频 | Rust (cpal、Core Audio tap)，专业混音器 + VAD |
| 识别 | whisper.cpp (Metal / CoreML) |
| 摘要 | 本地 LLM (llama.cpp：Gemma 3 / Qwen 2.5) · Ollama · Claude · OpenAI |
| 存储 | SQLite |

---

<div align="center">
<sub>Ember · 面向 macOS 的隐私优先 AI 会议助手</sub>
</div>
