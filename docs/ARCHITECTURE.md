# Architecture

AutoCut Studio has two layers:

- A SwiftUI macOS app in `macos/AutoCutStudio`.
- A Python backend in `autocut/`.

The Swift app owns the editor state, playback preview, timeline, file panels,
and keyboard interactions. The Python backend owns media probing, waveform
sampling, Whisper transcription, silence detection, range planning, and final
audio export.

## Swift App

Important paths:

- `App/AutoCutStudioApp.swift`: app entry point and command menus.
- `Views/ContentView.swift`: root editor composition.
- `Views/TimelineView.swift`: waveform timeline, ticks, playhead, segment
  overlays, and scroll-to-time behavior.
- `Views/SubtitleListView.swift`: editable transcript rows and selection.
- `Stores/ProjectStore.swift`: project state, selection, splitting, preview
  range planning, persistence, and backend orchestration.
- `Services/PythonBackend.swift`: `Process` wrapper for the Python backend.
- `Services/AudioPreviewPlayer.swift`: AVFoundation preview playback that skips
  removed ranges.
- `Models/AutoCutProject.swift`: Swift mirror of `.autocutproj.json`.

## Python Backend

Important paths:

- `autocut/app_backend.py`: command-line JSON backend used by Swift.
- `autocut/app_project.py`: project dataclasses, split logic, selected range
  planning, and export helpers.
- `autocut/app_progress.py`: structured progress events for long-running
  transcription tasks.
- `autocut/package_transcribe.py`: importable transcription wrapper inherited
  from AutoCut.
- `autocut/whisper_model.py`: local Whisper and faster-whisper adapters.

Swift calls the backend with:

```bash
.venv/bin/python -m autocut.app_backend <command> ...
```

Backend stdout must contain only the final JSON response. Progress events and
human-readable logs go to stderr.

## Backend Commands

- `probe --media <path>`: returns media metadata.
- `waveform --media <path> --samples <n>`: returns waveform peak samples.
- `transcribe --media <path> --lang en --model base --progress`: returns a full
  project JSON.
- `retranscribe-range --media <path> --start <sec> --end <sec>`: returns text
  for one segment range.
- `project-from-srt --media <path> --srt <path> [--md <path>]`: imports legacy
  subtitle data.
- `export --project <path> --output <path>`: writes MP3 from selected segments.
- `export-srt --project <path> --output <path>`: writes SRT.
- `export-md --project <path> --output <path>`: writes Markdown.

## Project JSON

`.autocutproj.json` is the source of truth for the app.

```json
{
  "version": 1,
  "mediaPath": "/path/to/audio.m4a",
  "duration": 123.45,
  "segments": [
    {
      "id": "uuid",
      "start": 0.0,
      "end": 2.3,
      "text": "Hello",
      "selected": true,
      "kind": "speech",
      "sourceIndex": 1,
      "needsRetranscribe": false
    }
  ],
  "settings": {
    "lang": "en",
    "whisperModel": "base",
    "padHead": 0.2,
    "padTail": 0.45,
    "mergeGap": 0.5,
    "bitrate": "192k"
  }
}
```

## Cutting Semantics

Selected segments become keep-ranges. Padding is applied around kept segments
unless an adjacent removed segment is speech. This keeps automatically detected
silence cuts natural while preserving exact manual speech cuts.
