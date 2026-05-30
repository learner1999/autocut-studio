# AutoCut Studio

简体中文 | [English](README.md)

AutoCut Studio 是一个本地运行的 macOS 播客 / 音频剪辑应用，基于
[mli/autocut](https://github.com/mli/autocut) 构建。它保留了 AutoCut
“根据字幕选择保留片段”的高效剪辑方式，并增加了原生 SwiftUI 界面：波形时间轴、
可编辑字幕列表、跳过删除片段的试听播放，以及 MP3 导出。

当前版本是一个面向单文件音频剪辑的 MVP。它适合用来剪英文播客、删除口误重录、
清理过长停顿，或者在不打开专业剪辑软件的情况下快速完成基于字幕的音频整理。

## 功能

- 原生 macOS SwiftUI 应用，代码位于 `macos/AutoCutStudio`。
- 本地 Python 后端，入口位于 `autocut/app_backend.py`。
- 使用 Whisper 转录，并在应用底部显示转录进度。
- 波形时间轴支持缩放、时间刻度、播放头，以及保留 / 删除片段覆盖层。
- 字幕列表支持勾选、取消勾选和直接编辑文本。
- 试听播放会自动跳过未勾选片段。
- 可以在播放头位置拆分字幕片段。
- 手动拆分后可对选中片段重新识别。
- 按当前勾选状态导出 MP3。
- 支持导入 / 导出 SRT 和 Markdown。
- 使用 `.autocutproj.json` 保存项目状态。

## 系统要求

- macOS 14 或更高版本。
- Xcode Command Line Tools，Swift 5.9 或更高版本。
- Python 3.9 或更高版本。
- FFmpeg 可在 `PATH` 中找到。

在 macOS 上通常可以用 Homebrew 安装 FFmpeg：

```bash
brew install ffmpeg
```

## 安装和运行

克隆仓库后，进入项目目录，创建虚拟环境，安装 Python 后端，然后构建 macOS App：

```bash
cd autocut-studio

python3 -m venv .venv
source .venv/bin/activate
python -m pip install --upgrade pip
pip install -e ".[dev]"

./script/build_and_run.sh
```

脚本会构建 SwiftPM 可执行文件，并生成可运行的 App：

```text
dist/AutoCutStudio.app
```

构建完成后，可以直接双击 `dist/AutoCutStudio.app`。这个生成的 App bundle
会在 `Info.plist` 里记录当前仓库路径，因此 Swift 应用可以找到本地 Python 后端
`.venv/bin/python`。

## 基本使用流程

1. 打开 `dist/AutoCutStudio.app`。
2. 点击 **Open**，选择音频文件，支持 `m4a`、`mp3`、`wav`、`flac`。
3. 点击 **Transcribe** 进行转录。
4. 在字幕列表里取消勾选需要删除的片段。
5. 点击时间轴或字幕行进行试听定位。
6. 如果一行字幕里既有需要保留的内容，也有需要删除的内容，可以把播放头移动到对应位置后点击 **Split**。
7. 点击 **Export** 导出剪辑后的 MP3。

常用快捷键：

- `Space`：播放 / 暂停。
- `B`：在当前播放头位置拆分。
- `Command-O`：打开音频。
- `Shift-Command-O`：打开项目。
- `Command-R`：重新识别当前选中片段。

## 剪辑模型

上方时间轴始终显示原始音频的完整时长。下方字幕列表是实际的剪辑计划。

- 勾选的行会被保留。
- 未勾选的行会在试听和导出时跳过。
- 静音片段会保留少量前后余量，避免自动剪静音时声音贴得太紧。
- 对语音片段做手动拆分和删除时，会尽量按手动切点精确删除，不把被删内容重新
  padding 回来。

项目状态保存在 `.autocutproj.json` 中，而不是 Markdown。SRT 和 Markdown 主要
作为兼容格式用于导入和导出。

## 开发

常用命令：

```bash
source .venv/bin/activate

# Python 核心测试
PYTHONPATH=test:. python test/test_app_project.py

# Swift App 测试
swift test --package-path macos/AutoCutStudio

# 构建并重新启动 App
./script/build_and_run.sh --verify
```

更多开发细节见 [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) 和
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)。

## 隐私

AutoCut Studio 默认完全本地运行。使用默认本地 Whisper 后端时，音频文件、项目文
件、波形数据和转录文本都会留在你的机器上。

需要注意的是，继承自 AutoCut 的旧 CLI 仍然保留可选的 OpenAI Whisper API 模式。
macOS App MVP 默认不使用这个模式；只有你手动启用它时，音频才可能发送到对应 API
服务。

安全和隐私说明见 [SECURITY.md](SECURITY.md)。

## 许可证和归属

本项目派生自 [mli/autocut](https://github.com/mli/autocut)。AutoCut 使用
Apache License 2.0，本项目继续使用 Apache-2.0。

这是一个独立的衍生项目。除非原 AutoCut 维护者明确说明，否则本项目不代表原项目，
也不表示获得原项目维护者背书。

根目录的 [LICENSE](LICENSE) 是完整许可证文本。上游归属、修改说明和第三方依赖
说明见 [NOTICE](NOTICE)、[CHANGES.md](CHANGES.md) 和
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

本项目包装的是 AutoCut，不是 Autodesk AutoCAD。
