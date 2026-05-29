# Third-Party Notices

This project is a source distribution. It does not bundle FFmpeg, Whisper model
weights, Python wheels, or a Python runtime by default. If you distribute a
prebuilt app bundle that includes any of those artifacts, review and include the
corresponding license files for the exact versions you ship.

## Direct Runtime Dependencies

The Python backend declares these runtime dependencies in `setup.py`:

| Dependency | Purpose | License observed from local package metadata |
| --- | --- | --- |
| `ffmpeg-python` | Python FFmpeg wrapper | Apache Software License classifier |
| `moviepy<2` | Audio/video export | MIT License |
| `openai-whisper` | Local Whisper transcription | MIT |
| `opencc-python-reimplemented` | Chinese text conversion inherited from AutoCut | Apache License |
| `parameterized` | Existing Python tests | BSD-style license metadata |
| `pydub` | Audio helper used by legacy OpenAI Whisper mode | MIT License |
| `srt` | SRT parsing and writing | MIT License |
| `torchaudio` | Audio/ML dependency path | BSD License classifier |
| `tqdm` | Progress display and backend progress integration | MPL-2.0 AND MIT metadata |

`openai-whisper` also installs machine learning dependencies such as `torch` and
`numpy`. Their license metadata should be reviewed before binary distribution.

## External Tools

FFmpeg is required at runtime and is normally installed separately, for example
with Homebrew on macOS. FFmpeg builds may be LGPL or GPL depending on build
options and linked codecs. This source repository does not redistribute FFmpeg.

## Upstream Project

AutoCut Studio is derived from `mli/autocut` and keeps the upstream Apache-2.0
license terms. See `NOTICE` and `LICENSE`.
