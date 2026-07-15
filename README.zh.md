<div align="center">

<a href="README.md">English</a> · <a href="README.ru.md">Русский</a> · <b>简体中文</b>

<img src="assets/logo.png" width="96" alt="Ember"/>

# Ember

**macOS 上的本地会议录制、转写与摘要工具。**

Ember 录制你的麦克风和通话对方的声音，实时生成转写，并把它变成详尽、易读的摘要 ——
全部在你的 Mac 上完成。它会自动开始和停止，默认不会有任何内容离开设备。

![macOS](https://img.shields.io/badge/macOS-14.4%2B-000?style=flat-square&logo=apple)
![Apple Silicon](https://img.shields.io/badge/Apple%20Silicon-arm64-000?style=flat-square)
![version](https://img.shields.io/badge/version-1.6.0-f97316?style=flat-square)
![local](https://img.shields.io/badge/100%25-本地-22c55e?style=flat-square)

<img src="assets/hero.zh.png" width="900" alt="Ember"/>

</div>

---

## 这是什么

Ember 录制会议（麦克风 + 系统音频），在本机转写，并写出可以代替亲临会议阅读的叙事式
摘要：按主题分节，细节、人名与决定融入正文，外加后续步骤。默认离线工作，无需账号；
唯一可选的云端功能是 DeepSeek 摘要 —— 在你添加密钥之前始终关闭。

## ✨ 功能

### 🎙 录制与采集
- **通话双方** —— 你的麦克风与系统音频（正在与你通话的人）一起录制，使用 **AirPods /
  耳机**时同样有效。
- **自动通话检测** —— 通话开始几秒后自动录制（Zoom、Google Meet、浏览器会议等），结束
  即停止，Ember 在后台时也有效。
- **菜单栏控制**、**⌘R** 开始/停止，通话结束后有清晰的处理阶段。

### ⌨️ 实时转写
- **实时转写**，随着说话逐字显示。
- **说话人标签** —— `[我]` 代表你，`[对]` 代表对方；具体是哪些参会者，由 AI 从对话内容
  中自行判断。
- **两种语音引擎** —— Whisper（Small / Medium / **Large V3 Turbo**，多语言）与
  **GigaAM v3**，俄语准确率高 2–3 倍。

### 🧠 摘要
- **以转写语言生成叙事式摘要** —— 读它即可代替亲临会议。
- **默认本地**，使用 Apple **MLX（Qwen3 1.7B / 4B / 8B）**；也可添加可选的
  **DeepSeek API 密钥**，获得近乎即时的云端摘要，失败时**自动回退**到本地模型。
- **基于事实** —— 人名、数字与决定取自真正说过的内容，减少臆造。
- **就地编辑** —— 阅读时即可修改摘要，改动会同步到导出的文件。

### 🗂 摘要模板
- **决定每份摘要的写法** —— 设置默认模板，或为单场会议单独选择。
- **内置模板库**：Standard、**Daily、Interview、1×1、Final Interview、TODO、Demo、
  Grooming**。
- 模板就是文件夹里的普通 **Markdown 文件** —— 可手动编辑或放入你自己的模板，改动会自动
  生效。每场会议都会记住它所用的模板。

### 📅 整理与导出
- **来自日历的标题** —— 会议以开始录制时正在进行的 Apple 日历事件命名。
- **跨会议搜索**，可自由重命名。
- **Markdown 导出**，按日期文件夹归类（YAML 前置信息、任务、时间戳）。
- **一键在 Obsidian 打开** —— 已安装 **Sage** 时则由 Sage 接管按钮。

### ⚙️ 控制与打磨
- **延后处理**（可选）—— 若紧接着又开始一场通话，转写与摘要会排队等待，待所有通话结束
  后再运行，让 Mac 在通话中保持安静。
- **模型管理** —— 下载 / 选择 / 删除，实时进度、内存提示，分组并排序；模型用完即卸载以
  释放内存。
- **登录时启动**，浅色 / 深色 / 自动主题，**六种强调色**，以及**中文 / 英文 / 俄文**即时
  切换。
- **内置更新**，来自 GitHub Releases，含更新横幅与「新功能」窗口。

## 导出到 Obsidian

每份摘要都可写入你选定文件夹中的 Markdown 文件（YAML 前置信息、任务、时间戳），并可一键在
**Obsidian** 中打开。若已安装 **[Sage](https://github.com/kslive/sage)**，则 Sage 优先：按钮会变为
发光的**「在 Sage 中打开」**，笔记直接在 Sage 中打开（必要时 Sage 会自动切换到笔记所在的空间）。
移除 Sage 后，Obsidian 按钮会自动恢复。

<div align="center"><img src="assets/obsidian.zh.png" width="860" alt="导出到 Markdown / Obsidian"/></div>

## 安装

需要 **Apple Silicon** 上的 **macOS 14.4+**。

1. 从 [Releases](../../releases/latest) 页面下载 `Ember_1.6.0_aarch64.dmg`。
2. 将 **Ember.app** 拖入 **应用程序**。
3. 应用为 ad-hoc 签名（未经过 Apple 公证），首次启动会被拦截。可右键 **Ember.app →
   打开 → 打开**，或在终端运行：
   ```bash
   xattr -dr com.apple.quarantine /Applications/Ember.app
   ```
4. 首次启动时选择语言，然后下载 Whisper 模型和摘要模型。

## 从源码构建

需要较新的 Xcode 和 [Tuist](https://tuist.dev)。

```bash
cd native
tuist install
tuist generate
open Ember.xcworkspace          # 或：xcodebuild -scheme Ember -configuration Release build
```

模型在首次运行时从 Hugging Face 下载。仅使用 ad-hoc 签名 —— 无需 Apple Developer 账号。

## 隐私

- 录制、转写和摘要均在本地完成。
- 音频写入临时文件夹，转写后立即删除；只保留文本（转写 + 摘要），存于 Mac 上的本地
  SQLite 数据库。
- 摘要默认在本地生成。若添加 DeepSeek API 密钥（可选），转写文本会发送给 DeepSeek
  生成摘要；删除密钥即可回到完全本地。密钥以加密形式存储在你的 Mac 上。
- 除此之外，唯一的联网是下载模型（Hugging Face）和检查更新（GitHub）。无遥测、无账号。

## 技术栈

SwiftUI · WhisperKit（CoreML/ANE）· GigaAM v3（sherpa-onnx）· Apple MLX（Qwen3）·
GRDB（SQLite）· CoreAudio。
