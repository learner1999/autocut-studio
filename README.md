# AutoCut Studio

[简体中文](README.zh-CN.md) | English

AutoCut Studio is a local macOS podcast and audio editor built on top of
[mli/autocut](https://github.com/mli/autocut). It keeps the fast subtitle-driven
editing workflow from AutoCut, then adds a native SwiftUI interface with a
waveform timeline, editable transcript rows, preview playback that skips removed
segments, and MP3 export.

The current app is an MVP for single-file audio editing. It is useful for
English podcast cleanup, removing retakes, trimming long pauses, and making
subtitle-guided cuts without opening a full nonlinear editor.

## Features

- Native macOS SwiftUI app in `macos/AutoCutStudio`.
- Local Python backend in `autocut/app_backend.py`.
- Whisper transcription with progress updates in the app status bar.
- Waveform timeline with zoom, tick marks, playhead, and selected/removed
  segment overlays.
- Editable subtitle list with checkboxes.
- Playback preview that jumps over unchecked segments.
- Split selected segments at the playhead.
- Optional segment retranscription after manual splits.
- Export selected ranges to MP3.
- Import/export SRT and Markdown.
- Project files stored as `.autocutproj.json`.

## Requirements

- macOS 14 or later.
- Xcode command line tools with Swift 5.9 or later.
- Python 3.9 or later.
- FFmpeg available on `PATH`.

On macOS, the usual FFmpeg install path is:

```bash
brew install ffmpeg
```

## Install

After cloning the repository, create a virtual environment, install the Python
backend, then build the macOS app:

```bash
cd autocut-studio

python3 -m venv .venv
source .venv/bin/activate
python -m pip install --upgrade pip
pip install -e ".[dev]"

./script/build_and_run.sh
```

The script builds a SwiftPM executable and stages a runnable app bundle at:

```text
dist/AutoCutStudio.app
```

You can double-click that app bundle after it has been built. The bundle stores
the repository root in its generated `Info.plist` so the Swift app can find the
local Python backend at `.venv/bin/python`.

## Basic Workflow

1. Open `dist/AutoCutStudio.app`.
2. Click **Open** and choose an audio file (`m4a`, `mp3`, `wav`, or `flac`).
3. Click **Transcribe**.
4. Uncheck transcript rows that should be removed.
5. Click the timeline or subtitle rows to preview edits.
6. Use **Split** at the playhead when one transcript row contains both useful
   and unwanted audio.
7. Use **Export** to write an MP3 cut.

Keyboard shortcuts:

- `Space`: play or pause.
- `B`: split at the current playhead.
- `Command-O`: open audio.
- `Shift-Command-O`: open project.
- `Command-R`: retranscribe the selected segment.

## Editing Model

The source timeline always keeps the original media duration. The transcript
rows are the editable cut plan.

- Checked rows are kept.
- Unchecked rows are skipped during preview and export.
- Silence rows get a small configurable pad so pause removals do not sound too
  abrupt.
- Manual cuts inside speech rows are treated as exact speech cuts, so the
  surrounding content is not padded back into the removed range.

Project data lives in `.autocutproj.json`, not Markdown. Markdown and SRT import
or export are compatibility paths.

## Development

Useful commands:

```bash
source .venv/bin/activate

# Python core tests
PYTHONPATH=test:. python test/test_app_project.py

# Swift app tests
swift test --package-path macos/AutoCutStudio

# Build and relaunch the app bundle
./script/build_and_run.sh --verify
```

See [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) and
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for more detail.

## Privacy

AutoCut Studio is designed to run locally. Audio files, project files, waveform
data, and transcripts stay on your machine when using the default local Whisper
backend. The legacy AutoCut CLI still contains optional OpenAI Whisper API mode;
do not enable that mode unless you intend to send audio to that API.

See [SECURITY.md](SECURITY.md) for reporting and privacy notes.

## License And Attribution

This repository is derived from
[mli/autocut](https://github.com/mli/autocut), which is licensed under the
Apache License 2.0. AutoCut Studio keeps the same Apache-2.0 license.

This is an independent derivative project. It is not affiliated with or
endorsed by the original AutoCut maintainers unless explicitly stated by those
maintainers.

The root [LICENSE](LICENSE) file contains the Apache-2.0 terms. Attribution,
modification, and third-party dependency notes are in [NOTICE](NOTICE),
[CHANGES.md](CHANGES.md), and [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

This project wraps AutoCut, not Autodesk AutoCAD.
