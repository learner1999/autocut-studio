# Changes From AutoCut

AutoCut Studio is a derivative work of
[mli/autocut](https://github.com/mli/autocut), which is licensed under the
Apache License, Version 2.0.

This repository preserves the upstream AutoCut git history. The first
AutoCut Studio-specific commit is:

- `a2d8ddab2dd4cb3c9e3d78f40b9756bbd73101a8` - Prepare AutoCut Studio for open
  source release

That commit was based on upstream history through:

- `ba2bb3bfbd57454727780eafad2861d66af58567` - Merge pull request #129 from
  chenqianhe/main

## Major Modifications

Compared with upstream AutoCut, this derivative project adds or changes:

- A native SwiftUI macOS app in `macos/AutoCutStudio`.
- A JSON project format, `.autocutproj.json`, for audio editing state.
- A Python JSON backend for probing media, extracting waveforms, transcribing,
  retranscribing ranges, and exporting selected audio.
- Podcast-oriented preview playback that skips unchecked transcript segments.
- Segment splitting and optional retranscription for manually split ranges.
- Silence-detection behavior for transcript edge pauses and bulk silence
  deselection in the macOS UI.
- MP3-focused export behavior for local podcast editing.
- GitHub Actions and developer documentation for the macOS app and Python
  backend.

## Modified Upstream Areas

The upstream AutoCut source tree is still present. Files in these areas have
been modified for AutoCut Studio behavior:

- `autocut/__init__.py`
- `autocut/cut.py`
- `autocut/main.py`
- `autocut/package_transcribe.py`
- `setup.py`

New AutoCut Studio-specific source files include:

- `autocut/app_backend.py`
- `autocut/app_progress.py`
- `autocut/app_project.py`
- `macos/AutoCutStudio/**`
- `script/build_and_run.sh`
- `docs/**`
- `test/test_app_project.py`

For license and attribution details, see `LICENSE`, `NOTICE`,
`THIRD_PARTY_NOTICES.md`, and `docs/LEGAL.md`.
